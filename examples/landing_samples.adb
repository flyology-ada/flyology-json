with Ada.Streams;
with Flyology_JSON.Errors;
with Flyology_JSON.Numbers.Unsigned_Integers;
with Flyology_JSON.Parsing;
with Flyology_JSON.Profiles;
with Interfaces;

procedure Landing_Samples is
   package Errors renames Flyology_JSON.Errors;
   package Profiles renames Flyology_JSON.Profiles;
   package Parsing is new Flyology_JSON.Parsing (Profiles.Reject_Duplicates);
   package Unsigned_64_JSON is new
     Flyology_JSON.Numbers.Unsigned_Integers (Interfaces.Unsigned_64);

   use type Errors.Error_Code;
   use type Interfaces.Unsigned_64;
   use type Parsing.Drain_Stop;
   use type Unsigned_64_JSON.Parse_Status;

   function To_Octets (Text : String) return Ada.Streams.Stream_Element_Array is
      Result : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Text'Length));
   begin
      for Position in Text'Range loop
         Result (Ada.Streams.Stream_Element_Offset (Position - Text'First + 1)) :=
           Character'Pos (Text (Position));
      end loop;
      return Result;
   end To_Octets;

   Profile : constant Profiles.Parser_Profile :=
     (Syntax        => (Family => Profiles.RFC_8259, Version => 1),
      Unicode       => (Family => Profiles.Unicode_Scalars, Version => 1),
      Compatibility => (Family => Profiles.No_Extensions, Version => 1),
      BOM           => Profiles.Reject_BOM,
      Duplicates    => Profiles.Reject_Duplicates,
      Top_Level     => Profiles.Accept_Any_Value);

   Parser : Parsing.Parser
     (Maximum_Depth       => 0,
      Name_Octet_Capacity => 0,
      Name_Capacity       => 0);
   Chunk  : constant Ada.Streams.Stream_Element_Array := To_Octets ("null");
   Events : Parsing.Event_Array (1 .. 16);
   Result : Parsing.Drain_Result;

   Number        : constant Ada.Streams.Stream_Element_Array :=
     To_Octets ("18446744073709551615");
   Number_Result : Unsigned_64_JSON.Parse_Result;
   Diagnostic    : Errors.Diagnostic;
begin
   --  BEGIN quick-start-parser
   declare
      Quick_Profile : constant Profiles.Parser_Profile :=
        (Syntax        => (Family => Profiles.RFC_8259, Version => 1),
         Unicode       => (Family => Profiles.Unicode_Scalars, Version => 1),
         Compatibility => (Family => Profiles.No_Extensions, Version => 1),
         BOM           => Profiles.Reject_BOM,
         Duplicates    => Profiles.Reject_Duplicates,
         Top_Level     => Profiles.Accept_Any_Value);
      Quick_Parser : Parsing.Parser
        (Maximum_Depth       => 0,
         Name_Octet_Capacity => 0,
         Name_Capacity       => 0);
      Input : constant Ada.Streams.Stream_Element_Array :=
        [Character'Pos ('n'), Character'Pos ('u'), Character'Pos ('l'), Character'Pos ('l')];
      Quick_Events     : Parsing.Event_Array (1 .. 4);
      Quick_Result     : Parsing.Drain_Result;
      Quick_Diagnostic : Errors.Diagnostic;
   begin
      Parsing.Initialize (Quick_Parser, Quick_Profile, Quick_Diagnostic);
      if Quick_Diagnostic.Code /= Errors.No_Error then
         raise Program_Error with "parser initialization failed";
      end if;

      Parsing.Drain
        (Self         => Quick_Parser,
         Input        => Input,
         End_Of_Input => True,
         Events       => Quick_Events,
         Result       => Quick_Result);
      if Quick_Result.Stop /= Parsing.Drain_Document_Complete then
         raise Program_Error with "JSON document was not accepted";
      end if;
   end;
   --  END quick-start-parser

   Parsing.Initialize (Parser, Profile, Diagnostic);
   if Diagnostic.Code /= Errors.No_Error then
      raise Program_Error with "parser initialization failed";
   end if;

   --  BEGIN landing-parser
   Parsing.Drain
     (Self         => Parser,
      Input        => Chunk,
      End_Of_Input => True,
      Events       => Events,
      Result       => Result);
   --  END landing-parser

   if Result.Stop /= Parsing.Drain_Document_Complete then
      raise Program_Error with
        "parser did not accept the scalar: " & Parsing.Drain_Stop'Image (Result.Stop)
        & " / " & Errors.Error_Code'Image (Result.Diagnostic.Code);
   end if;

   --  BEGIN landing-number
   Unsigned_64_JSON.Parse
     (Lexeme => Number,
      Result => Number_Result);
   --  END landing-number

   if Number_Result.Status /= Unsigned_64_JSON.Converted
     or else Number_Result.Value /= Interfaces.Unsigned_64'Last
   then
      raise Program_Error with "unsigned conversion failed";
   end if;
end Landing_Samples;
