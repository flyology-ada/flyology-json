package body Flyology_JSON.Tokens is

   use type Ada.Streams.Stream_Element_Count;

   procedure Begin_Token
     (Self : in out Collector; Kind : Token_Kind; Status : out Collector_Status)
   is
   begin
      if Self.Current_State /= Empty then
         Status := Invalid_Order;
         return;
      end if;

      Self.Current_State := Collecting;
      Self.Current_Kind := Kind;
      Self.Staged_Length := 0;
      Self.Public_Length := 0;
      Status := Operation_Accepted;
   end Begin_Token;

   procedure Append
     (Self   : in out Collector;
      Value  : Ada.Streams.Stream_Element_Array;
      Status : out Collector_Status)
   is
      subtype Count is Ada.Streams.Stream_Element_Count;
      subtype Offset is Ada.Streams.Stream_Element_Offset;
      Available : constant Count := Self.Storage'Length - Self.Staged_Length;
   begin
      if Self.Current_State /= Collecting then
         Status := Invalid_Order;
         return;
      end if;

      if Value'Length > Available then
         Self.Current_State := Failed;
         Self.Public_Length := 0;
         Status := Storage_Exhausted;
         return;
      end if;

      if Value'Length > 0 then
         for Position in Count range 0 .. Value'Length - 1 loop
            Self.Storage (Self.Storage'First + Offset (Self.Staged_Length + Position)) :=
              Value (Value'First + Offset (Position));
         end loop;
      end if;
      Self.Staged_Length := Self.Staged_Length + Value'Length;
      Status := Operation_Accepted;
   end Append;

   procedure Complete_Token (Self : in out Collector; Status : out Collector_Status) is
   begin
      if Self.Current_State /= Collecting then
         Status := Invalid_Order;
         return;
      end if;

      Self.Public_Length := Self.Staged_Length;
      Self.Current_State := Complete;
      Status := Token_Completed;
   end Complete_Token;

   procedure Clear_State (Self : in out Collector) is
   begin
      Self.Current_State := Empty;
      Self.Staged_Length := 0;
      Self.Public_Length := 0;
   end Clear_State;

   procedure Abort_Token (Self : in out Collector) is
   begin
      Clear_State (Self);
   end Abort_Token;

   procedure Reset (Self : in out Collector) is
   begin
      Clear_State (Self);
   end Reset;

   function State (Self : Collector) return Collector_State
   is (Self.Current_State);

   function Kind (Self : Collector) return Token_Kind
   is (Self.Current_Kind);

   function Collected_Length (Self : Collector) return Ada.Streams.Stream_Element_Count
   is (Self.Public_Length);

end Flyology_JSON.Tokens;
