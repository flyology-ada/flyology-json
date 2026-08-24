package body Flyology_JSON.Parser_UTF8 is

   use type Ada.Streams.Stream_Element;

   subtype Octet is Ada.Streams.Stream_Element;

   First_Continuation : constant Octet := 16#80#;
   Last_Continuation  : constant Octet := 16#BF#;

   function Is_Continuation (Value : Octet) return Boolean is
     (Value in First_Continuation .. Last_Continuation);

   procedure Reset (Self : out Decoder) is
   begin
      Self := (Octets => [others => 0], Length => 0, Expected_Length => 0);
   end Reset;

   procedure Reject
     (Self   : in out Decoder;
      Blame  : Blame_Position;
      Result : out Feed_Result)
   is
   begin
      Self.Length := 0;
      Self.Expected_Length := 0;
      Result := (Status => Invalid, Blame => Blame);
   end Reject;

   procedure Complete (Self : in out Decoder; Result : out Feed_Result) is
      Value : constant Scalar :=
        (Length => Self.Length,
         Octets => Self.Octets);
   begin
      Self.Length := 0;
      Self.Expected_Length := 0;
      Result := (Status => Scalar_Ready, Value => Value);
   end Complete;

   procedure Feed
     (Self   : in out Decoder;
      Octet  : Ada.Streams.Stream_Element;
      Result : out Feed_Result)
   is
   begin
      if Self.Length = 0 then
         Self.Octets (1) := Octet;

         if Octet <= 16#7F# then
            Self.Length := 1;
            Self.Expected_Length := 1;
            Complete (Self, Result);
         elsif Octet in 16#C2# .. 16#DF# then
            Self.Length := 1;
            Self.Expected_Length := 2;
            Result := (Status => Need_More);
         elsif Octet in 16#E0# .. 16#EF# then
            Self.Length := 1;
            Self.Expected_Length := 3;
            Result := (Status => Need_More);
         elsif Octet in 16#F0# .. 16#F4# then
            Self.Length := 1;
            Self.Expected_Length := 4;
            Result := (Status => Need_More);
         else
            Reject (Self, Current_Octet, Result);
         end if;

         return;
      end if;

      if not Is_Continuation (Octet) then
         Reject (Self, Current_Octet, Result);
         return;
      end if;

      if Self.Length = 1 then
         case Self.Octets (1) is
            when 16#E0# =>
               if Octet < 16#A0# then
                  Reject (Self, Stored_Lead_Octet, Result);
                  return;
               end if;
            when 16#ED# =>
               if Octet > 16#9F# then
                  Reject (Self, Stored_Lead_Octet, Result);
                  return;
               end if;
            when 16#F0# =>
               if Octet < 16#90# then
                  Reject (Self, Stored_Lead_Octet, Result);
                  return;
               end if;
            when 16#F4# =>
               if Octet > 16#8F# then
                  Reject (Self, Stored_Lead_Octet, Result);
                  return;
               end if;
            when others =>
               null;
         end case;
      end if;

      Self.Length := Self.Length + 1;
      Self.Octets (Self.Length) := Octet;

      if Self.Length = Self.Expected_Length then
         Complete (Self, Result);
      else
         Result := (Status => Need_More);
      end if;
   end Feed;

   function Has_Pending_Octets (Self : Decoder) return Boolean is
     (Self.Length /= 0);

end Flyology_JSON.Parser_UTF8;
