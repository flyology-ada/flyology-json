with Ada.Streams;
with Flyology_JSON.Errors;
with Flyology_JSON.Numbers.Signed_Integers;
with Flyology_JSON.Numbers.Unsigned_Integers;
with Flyology_JSON.Parsing;
with Flyology_JSON.Profiles;
with Flyology_JSON.Tokens;
with Interfaces;

procedure Flyology_JSON_External_Consumer_Smoke is
   package Errors renames Flyology_JSON.Errors;
   package Profiles renames Flyology_JSON.Profiles;
   package Tokens renames Flyology_JSON.Tokens;

   package Parsing is new Flyology_JSON.Parsing (Profiles.Reject_Duplicates);
   package UInt32_JSON is new
     Flyology_JSON.Numbers.Unsigned_Integers (Interfaces.Unsigned_32);
   package UInt64_JSON is new
     Flyology_JSON.Numbers.Unsigned_Integers (Interfaces.Unsigned_64);
   package Int64_JSON is new
     Flyology_JSON.Numbers.Signed_Integers (Interfaces.Integer_64);

   use type Ada.Streams.Stream_Element_Count;
   use type Errors.Error_Code;
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type Parsing.Drain_Stop;
   use type Parsing.Event_Kind;
   use type Parsing.Slice_Status;
   use type Tokens.Collector_Status;
   use type UInt32_JSON.Parse_Status;
   use type UInt64_JSON.Parse_Status;
   use type Int64_JSON.Parse_Status;

   subtype Count is Ada.Streams.Stream_Element_Count;
   subtype Offset is Ada.Streams.Stream_Element_Offset;

   procedure Check (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Check;

   function To_Input
     (Text  : String;
      First : Offset) return Ada.Streams.Stream_Element_Array
   is
      Result : Ada.Streams.Stream_Element_Array
        (First .. First + Offset (Text'Length) - 1);
   begin
      for Position in Text'Range loop
         Result (First + Offset (Position - Text'First)) := Character'Pos (Text (Position));
      end loop;
      return Result;
   end To_Input;

   Profile : constant Profiles.Parser_Profile :=
     (Syntax        => (Family => Profiles.RFC_8259, Version => 1),
      Unicode       => (Family => Profiles.Unicode_Scalars, Version => 1),
      Compatibility => (Family => Profiles.No_Extensions, Version => 1),
      BOM           => Profiles.Reject_BOM,
      Duplicates    => Profiles.Reject_Duplicates,
      Top_Level     => Profiles.Accept_Any_Value);

   Input : constant Ada.Streams.Stream_Element_Array :=
     To_Input ("[4294967295,18446744073709551615,-9223372036854775808]", -37);
   Storage : aliased Tokens.Token_Storage := Tokens.Token_Storage'(19 .. 63 => 0);
   Collector : Tokens.Collector (Storage'Access);
   Parser : Parsing.Parser (Maximum_Depth => 1, Name_Octet_Capacity => 0, Name_Capacity => 0);
   Events : Parsing.Event_Array (-9 .. -2);
   Diagnostic : Errors.Diagnostic;
   Result : Parsing.Drain_Result;
   Status : Tokens.Collector_Status;
   Used : Count := 0;
   Numbers_Seen : Natural := 0;

   procedure Append_Raw
     (Item         : Parsing.Event;
      Input_Origin : Errors.Byte_Offset;
      Window_First : Offset)
   is
      Slice       : Parsing.Chunk_Range;
      Slice_State : Parsing.Slice_Status;
      First       : Offset;
      Last        : Offset;
   begin
      Parsing.Resolve_Raw_Range
        (Item,
         Input_Origin,
         Input'Last - Window_First + 1,
         Slice,
         Slice_State);
      Check (Slice_State = Parsing.Slice_Resolved, "number fragment did not resolve");
      First := Window_First + Offset (Slice.First_Count);
      Last := First + Offset (Slice.Octet_Length) - 1;
      Tokens.Append (Collector, Input (First .. Last), Status);
      Check (Status = Tokens.Operation_Accepted, "number collector append failed");
   end Append_Raw;

   procedure Check_Completed_Number is
      Length : constant Count := Tokens.Collected_Length (Collector);
      Last   : constant Offset := Storage'First + Offset (Length) - 1;
   begin
      Numbers_Seen := Numbers_Seen + 1;
      case Numbers_Seen is
         when 1 =>
            declare
               Parsed : UInt32_JSON.Parse_Result;
            begin
               UInt32_JSON.Parse (Storage (Storage'First .. Last), Parsed);
               Check
                 (Parsed.Status = UInt32_JSON.Converted
                  and then Parsed.Value = Interfaces.Unsigned_32'Last,
                  "uint32 endpoint changed");
            end;

         when 2 =>
            declare
               Parsed : UInt64_JSON.Parse_Result;
            begin
               UInt64_JSON.Parse (Storage (Storage'First .. Last), Parsed);
               Check
                 (Parsed.Status = UInt64_JSON.Converted
                  and then Parsed.Value = Interfaces.Unsigned_64'Last,
                  "uint64 endpoint changed");
            end;

         when 3 =>
            declare
               Parsed : Int64_JSON.Parse_Result;
            begin
               Int64_JSON.Parse (Storage (Storage'First .. Last), Parsed);
               Check
                 (Parsed.Status = Int64_JSON.Converted
                  and then Parsed.Value = Interfaces.Integer_64'First,
                  "int64 endpoint changed");
            end;

         when others =>
            raise Program_Error with "unexpected extra number";
      end case;
      Tokens.Reset (Collector);
   end Check_Completed_Number;

begin
   Parsing.Initialize (Parser, Profile, Diagnostic);
   Check (Diagnostic.Code = Errors.No_Error, "public parser initialization failed");

   loop
      declare
         Window_First : constant Offset := Input'First + Offset (Used);
      begin
         Parsing.Drain
           (Parser,
            Input (Window_First .. Input'Last),
            End_Of_Input => True,
            Events       => Events,
            Result       => Result);

         if Result.Produced > 0 then
            for Published in Count range 0 .. Result.Produced - 1 loop
               declare
                  Item : Parsing.Event renames Events (Events'First + Offset (Published));
               begin
                  case Parsing.Kind (Item) is
                     when Parsing.Number_Begin    =>
                        Tokens.Begin_Token (Collector, Tokens.Exact_Number, Status);
                        Check (Status = Tokens.Operation_Accepted, "number collector begin failed");

                     when Parsing.Number_Fragment =>
                        Append_Raw (Item, Result.Input_Origin, Window_First);

                     when Parsing.Number_End      =>
                        Tokens.Complete_Token (Collector, Status);
                        Check (Status = Tokens.Token_Completed, "number collector completion failed");
                        Check_Completed_Number;

                     when others                  =>
                        null;
                  end case;
               end;
            end loop;
         end if;
         Used := Used + Result.Consumed;
      end;

      exit when Result.Stop = Parsing.Drain_Document_Complete;
      Check
        (Result.Stop in Parsing.Output_Full | Parsing.Drain_Need_Input,
         "public parser stopped before document completion");
   end loop;

   Check (Used = Input'Length, "public parser did not consume the document");
   Check (Numbers_Seen = 3, "public parser did not expose every number");
end Flyology_JSON_External_Consumer_Smoke;
