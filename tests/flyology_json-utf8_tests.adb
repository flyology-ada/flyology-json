with Ada.Streams;
with Flyology_JSON.Parser_UTF8;

procedure Flyology_JSON.UTF8_Tests is
   package UTF8 renames Flyology_JSON.Parser_UTF8;

   use type Ada.Streams.Stream_Element;
   use type UTF8.Blame_Position;
   use type UTF8.Feed_Status;
   use type UTF8.Scalar_Octets;

   subtype Octet is Ada.Streams.Stream_Element;
   type Octet_Array is array (Positive range <>) of Octet;

   procedure Expect_Valid (Input : Octet_Array) is
      State  : UTF8.Decoder;
      Result : UTF8.Feed_Result;
   begin
      UTF8.Reset (State);

      for Index in Input'Range loop
         UTF8.Feed (State, Input (Index), Result);

         if Index = Input'Last then
            pragma Assert (Result.Status = UTF8.Scalar_Ready);
            pragma Assert (Result.Value.Length = Input'Length);

            for Offset in 0 .. Input'Length - 1 loop
               pragma Assert (Result.Value.Octets (Offset + 1) = Input (Input'First + Offset));
            end loop;
         else
            pragma Assert (Result.Status = UTF8.Need_More);
            pragma Assert (UTF8.Has_Pending_Octets (State));
         end if;
      end loop;

      pragma Assert (not UTF8.Has_Pending_Octets (State));
   end Expect_Valid;

   procedure Expect_Invalid
     (Input : Octet_Array;
      Blame : UTF8.Blame_Position)
   is
      State  : UTF8.Decoder;
      Result : UTF8.Feed_Result;
   begin
      UTF8.Reset (State);

      for Value of Input loop
         UTF8.Feed (State, Value, Result);
      end loop;

      pragma Assert (Result.Status = UTF8.Invalid);
      pragma Assert (Result.Blame = Blame);
      pragma Assert (not UTF8.Has_Pending_Octets (State));
   end Expect_Invalid;

   procedure Expect_All_Unicode_Scalars is
      Data   : Octet_Array (1 .. 4);
      Length : Positive range 1 .. Data'Length;
   begin
      for Code_Point in 0 .. 16#10_FFFF# loop
         if Code_Point not in 16#D800# .. 16#DFFF# then
            if Code_Point <= 16#7F# then
               Length := 1;
               Data (1) := Octet (Code_Point);
            elsif Code_Point <= 16#7FF# then
               Length := 2;
               Data (1) := 16#C0# + Octet (Code_Point / 2**6);
               Data (2) := 16#80# + Octet (Code_Point mod 2**6);
            elsif Code_Point <= 16#FFFF# then
               Length := 3;
               Data (1) := 16#E0# + Octet (Code_Point / 2**12);
               Data (2) := 16#80# + Octet ((Code_Point / 2**6) mod 2**6);
               Data (3) := 16#80# + Octet (Code_Point mod 2**6);
            else
               Length := 4;
               Data (1) := 16#F0# + Octet (Code_Point / 2**18);
               Data (2) := 16#80# + Octet ((Code_Point / 2**12) mod 2**6);
               Data (3) := 16#80# + Octet ((Code_Point / 2**6) mod 2**6);
               Data (4) := 16#80# + Octet (Code_Point mod 2**6);
            end if;

            Expect_Valid (Data (1 .. Length));
         end if;
      end loop;
   end Expect_All_Unicode_Scalars;

   State  : UTF8.Decoder;
   Result : UTF8.Feed_Result;
begin
   Expect_Valid ([16#00#]);
   Expect_Valid ([16#7F#]);
   Expect_Valid ([16#C2#, 16#80#]);
   Expect_Valid ([16#DF#, 16#BF#]);
   Expect_Valid ([16#E0#, 16#A0#, 16#80#]);
   Expect_Valid ([16#ED#, 16#9F#, 16#BF#]);
   Expect_Valid ([16#EE#, 16#80#, 16#80#]);
   Expect_Valid ([16#F0#, 16#90#, 16#80#, 16#80#]);
   Expect_Valid ([16#F4#, 16#8F#, 16#BF#, 16#BF#]);

   Expect_Invalid ([16#80#], UTF8.Current_Octet);
   Expect_Invalid ([16#C0#], UTF8.Current_Octet);
   Expect_Invalid ([16#C1#], UTF8.Current_Octet);
   Expect_Invalid ([16#F5#], UTF8.Current_Octet);
   Expect_Invalid ([16#FF#], UTF8.Current_Octet);
   Expect_Invalid ([16#C2#, 16#41#], UTF8.Current_Octet);
   Expect_Invalid ([16#E1#, 16#80#, 16#41#], UTF8.Current_Octet);
   Expect_Invalid ([16#F1#, 16#80#, 16#80#, 16#41#], UTF8.Current_Octet);
   Expect_Invalid ([16#E0#, 16#9F#], UTF8.Stored_Lead_Octet);
   Expect_Invalid ([16#ED#, 16#A0#], UTF8.Stored_Lead_Octet);
   Expect_Invalid ([16#F0#, 16#8F#], UTF8.Stored_Lead_Octet);
   Expect_Invalid ([16#F4#, 16#90#], UTF8.Stored_Lead_Octet);

   UTF8.Reset (State);
   UTF8.Feed (State, 16#F0#, Result);
   pragma Assert (UTF8.Has_Pending_Octets (State));
   UTF8.Reset (State);
   pragma Assert (not UTF8.Has_Pending_Octets (State));
   UTF8.Feed (State, 16#41#, Result);
   pragma Assert (Result.Status = UTF8.Scalar_Ready);

   UTF8.Feed (State, 16#FF#, Result);
   pragma Assert (Result.Status = UTF8.Invalid);
   UTF8.Feed (State, 16#42#, Result);
   pragma Assert (Result.Status = UTF8.Scalar_Ready);

   UTF8.Reset (State);
   UTF8.Feed (State, 16#E2#, Result);
   pragma Assert (Result.Status = UTF8.Need_More);
   UTF8.Feed (State, 16#82#, Result);
   pragma Assert (Result.Status = UTF8.Need_More);
   UTF8.Feed (State, 16#AC#, Result);
   pragma Assert (Result.Status = UTF8.Scalar_Ready);
   pragma Assert (Result.Value.Length = 3);
   pragma Assert (Result.Value.Octets (1 .. 3) = [16#E2#, 16#82#, 16#AC#]);

   Expect_All_Unicode_Scalars;
end Flyology_JSON.UTF8_Tests;
