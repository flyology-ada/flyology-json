with Ada.Streams;
with Ada.Text_IO;
with Flyology_JSON.Destinations;
with Flyology_JSON.Errors;
with Flyology_JSON.Parsing;
with Flyology_JSON.Profiles;
with Flyology_JSON.Writing;

procedure Flyology_JSON.Writer_Corpus_Tests is

   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Array;
   use type Ada.Streams.Stream_Element_Count;
   use type Flyology_JSON.Errors.Error_Code;

   package Errors renames Flyology_JSON.Errors;
   package Profiles renames Flyology_JSON.Profiles;

   subtype Count is Ada.Streams.Stream_Element_Count;
   subtype Offset is Ada.Streams.Stream_Element_Offset;
   subtype Octet_Array is Ada.Streams.Stream_Element_Array;

   --  Test-only physical bounds. They are intentionally not library policy.
   Destination_Capacity : constant Count := 65_536;
   Payload_Capacity     : constant Natural := 128;
   Golden_Hex_Capacity  : constant Natural := 131_072;

   type Test_Destination is limited record
      Storage       : Octet_Array (-101 .. -102 + Offset (Destination_Capacity));
      Staged_Length : Count := 0;
      Active        : Boolean := False;
      Published     : Boolean := False;
   end record;

   procedure Destination_Begin
     (Target : in out Test_Destination;
      Status : out Flyology_JSON.Destinations.Begin_Status)
   is
   begin
      Target.Staged_Length := 0;
      Target.Active := True;
      Target.Published := False;
      Status := Flyology_JSON.Destinations.Begin_Succeeded;
   end Destination_Begin;

   procedure Destination_Write
     (Target  : in out Test_Destination;
      Data    : Octet_Array;
      Written : out Count;
      Status  : out Flyology_JSON.Destinations.Write_Status)
   is
      Available : constant Count := Destination_Capacity - Target.Staged_Length;
   begin
      Written := Count'Min (Data'Length, Available);
      if Written > 0 then
         for Position in Count range 0 .. Written - 1 loop
            Target.Storage (Target.Storage'First + Offset (Target.Staged_Length + Position)) :=
              Data (Data'First + Offset (Position));
         end loop;
      end if;
      Target.Staged_Length := Target.Staged_Length + Written;
      Status :=
        (if Written = Data'Length
         then Flyology_JSON.Destinations.Write_Succeeded
         else Flyology_JSON.Destinations.Write_Exhausted);
   end Destination_Write;

   procedure Destination_Commit
     (Target : in out Test_Destination;
      Status : out Flyology_JSON.Destinations.Commit_Status)
   is
   begin
      Target.Active := False;
      Target.Published := True;
      Status := Flyology_JSON.Destinations.Commit_Succeeded;
   end Destination_Commit;

   procedure Destination_Abort
     (Target : in out Test_Destination;
      Status : out Flyology_JSON.Destinations.Abort_Status)
   is
   begin
      Target.Active := False;
      Target.Staged_Length := 0;
      Status := Flyology_JSON.Destinations.Abort_Succeeded;
   end Destination_Abort;

   package Writers is new Flyology_JSON.Writing
     (Destination_Type   => Test_Destination,
      Destination_Begin  => Destination_Begin,
      Destination_Write  => Destination_Write,
      Destination_Commit => Destination_Commit,
      Destination_Abort  => Destination_Abort);

   package Parsers is new Flyology_JSON.Parsing (Profiles.Reject_Duplicates);

   function Writer_Profile return Profiles.Writer_Profile is
     (Syntax     => (Family => Profiles.RFC_8259, Version => 1),
      Unicode    => (Family => Profiles.Unicode_Scalars, Version => 1),
      Formatting => (Policy => Profiles.Ordinary_Compact, Version => 1));

   function Parser_Profile return Profiles.Parser_Profile is
     (Syntax        => (Family => Profiles.RFC_8259, Version => 1),
      Unicode       => (Family => Profiles.Unicode_Scalars, Version => 1),
      Compatibility => (Family => Profiles.No_Extensions, Version => 1),
      BOM           => Profiles.Reject_BOM,
      Duplicates    => Profiles.Reject_Duplicates,
      Top_Level     => Profiles.Accept_Any_Value);

   procedure Check (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Check;

   function Hex_Value (Item : Character) return Ada.Streams.Stream_Element is
   begin
      case Item is
         when '0' .. '9' =>
            return Character'Pos (Item) - Character'Pos ('0');
         when 'a' .. 'f' =>
            return 10 + Character'Pos (Item) - Character'Pos ('a');
         when 'A' .. 'F' =>
            return 10 + Character'Pos (Item) - Character'Pos ('A');
         when others =>
            raise Program_Error with "nonhex golden oracle";
      end case;
   end Hex_Value;

   function Load_Golden (Path : String) return Octet_Array is
      File : Ada.Text_IO.File_Type;
      Line : String (1 .. Golden_Hex_Capacity);
      Last : Natural;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      Ada.Text_IO.Get_Line (File, Line, Last);
      Check (Ada.Text_IO.End_Of_File (File), Path & ": golden must contain one line");
      Ada.Text_IO.Close (File);
      Check (Last > 0 and then Last mod 2 = 0, Path & ": invalid golden length");

      declare
         Result : Octet_Array (-17 .. -18 + Offset (Last / 2));
      begin
         for Position in Result'Range loop
            declare
               Pair : constant Natural := Natural (Position - Result'First) * 2;
            begin
               Result (Position) :=
                 16 * Hex_Value (Line (Pair + 1)) + Hex_Value (Line (Pair + 2));
            end;
         end loop;
         return Result;
      end;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise;
   end Load_Golden;

   type Action_Kind is
     (Object_Begin,
      Object_End,
      Array_Begin,
      Array_End,
      Name_Value,
      String_Value,
      Number_Value,
      Null_Value,
      True_Value,
      False_Value);

   type Action is record
      Kind    : Action_Kind;
      Length  : Natural range 0 .. Payload_Capacity;
      Payload : String (1 .. Payload_Capacity);
   end record;

   type Action_Array is array (Positive range <>) of Action;

   function Make_Action (Kind : Action_Kind) return Action is
     (Kind => Kind, Length => 0, Payload => [others => Character'Val (0)]);

   function Make_Action (Kind : Action_Kind; Payload : String) return Action is
      Result : Action := Make_Action (Kind);
   begin
      Check (Payload'Length <= Payload_Capacity, "test tape payload capacity exceeded");
      Result.Length := Payload'Length;
      if Payload'Length > 0 then
         Result.Payload (1 .. Payload'Length) := Payload;
      end if;
      return Result;
   end Make_Action;

   function Bytes
     (Item        : Action;
      First_Count : Natural;
      Length      : Natural;
      First       : Offset) return Octet_Array
   is
      Result : Octet_Array (First .. First + Offset (Length) - 1);
   begin
      Check (First_Count + Length <= Item.Length, "tape fragment outside payload");
      for Position in Natural range 0 .. Length - 1 loop
         Result (First + Offset (Position)) := Character'Pos (Item.Payload (First_Count + Position + 1));
      end loop;
      return Result;
   end Bytes;

   procedure Check_Writer_Result (Diagnostic : Errors.Diagnostic; Label : String) is
   begin
      Check (Diagnostic.Code = Errors.No_Error, Label & ": writer rejected valid tape");
   end Check_Writer_Result;

   type Fragment_Schedule is (Whole_Token, One_Octet, Single_Split, Randomized);
   type Random_State is mod 2 ** 32;

   procedure Emit_Payload
     (Subject         : in out Writers.Writer;
      Item            : Action;
      Schedule        : Fragment_Schedule;
      Selected_Action : Positive;
      Action_Index    : Positive;
      Split           : Natural;
      Random          : in out Random_State;
      Label           : String)
   is
      Diagnostic : Errors.Diagnostic;

      procedure Emit (First_Count : Natural; Length : Natural) is
         First : constant Offset := -2_000 + Offset (Action_Index * 17 + First_Count mod 13);
      begin
         case Item.Kind is
            when Name_Value =>
               Writers.Put_Name_Fragment
                 (Subject, Bytes (Item, First_Count, Length, First), Diagnostic);
            when String_Value =>
               Writers.Put_String_Fragment
                 (Subject, Bytes (Item, First_Count, Length, First), Diagnostic);
            when Number_Value =>
               Writers.Put_Number_Fragment
                 (Subject, Bytes (Item, First_Count, Length, First), Diagnostic);
            when others =>
               raise Program_Error with Label & ": nonfragment action has payload";
         end case;
         Check_Writer_Result (Diagnostic, Label);
      end Emit;

      Cursor : Natural := 0;
   begin
      case Schedule is
         when Whole_Token =>
            Emit (0, Item.Length);

         when One_Octet =>
            if Item.Length = 0 then
               Emit (0, 0);
            else
               while Cursor < Item.Length loop
                  Emit (Cursor, 1);
                  Cursor := Cursor + 1;
               end loop;
            end if;

         when Single_Split =>
            if Action_Index = Selected_Action then
               Emit (0, Split);
               Emit (Split, Item.Length - Split);
            else
               Emit (0, Item.Length);
            end if;

         when Randomized =>
            if Item.Length = 0 then
               Emit (0, 0);
            else
               while Cursor < Item.Length loop
                  Random := Random * 1_664_525 + 1_013_904_223;
                  declare
                     Span : constant Natural :=
                       Natural'Min (Item.Length - Cursor, 1 + Natural (Random mod 7));
                  begin
                     Emit (Cursor, Span);
                     Cursor := Cursor + Span;
                  end;
               end loop;
            end if;
      end case;
   end Emit_Payload;

   type Parser_Chunk_Schedule is (Whole_Input, One_Byte_Input, Two_Chunks, Random_Chunks);

   procedure Accept_With_Public_Parser
     (Data     : Octet_Array;
      Label    : String;
      Schedule : Parser_Chunk_Schedule;
      Split    : Count;
      Seed     : Random_State)
   is
      Subject    : Parsers.Parser
        (Maximum_Depth => 16, Name_Octet_Capacity => 4_096, Name_Capacity => 256);
      Diagnostic : Errors.Diagnostic;
      Result     : Parsers.Step_Result;
      Cursor     : Count := 0;
      Completed  : Boolean := False;
      Random     : Random_State := Seed;

      procedure Feed (Length : Count; Final : Boolean) is
         Within : Count := 0;
      begin
         loop
            if Within < Length then
               Parsers.Step
                 (Subject,
                  Data
                    (Data'First + Offset (Cursor + Within) ..
                     Data'First + Offset (Cursor + Length) - 1),
                  Final,
                  Result);
            else
               declare
                  Empty : constant Octet_Array (73 .. 72) := [others => 0];
               begin
                  Parsers.Step (Subject, Empty, Final, Result);
               end;
            end if;

            Within := Within + Result.Consumed;
            case Result.Outcome is
               when Parsers.Event_Ready =>
                  null;
               when Parsers.Document_Complete =>
                  Completed := True;
                  exit;
               when Parsers.Need_Input =>
                  Check (Within = Length, Label & ": parser left a chunk suffix");
                  exit;
               when Parsers.Step_Failed | Parsers.Call_Rejected =>
                  raise Program_Error with Label & ": public parser rejected writer output";
            end case;
         end loop;
         Cursor := Cursor + Within;
      end Feed;
   begin
      Parsers.Initialize (Subject, Parser_Profile, Diagnostic);
      Check (Diagnostic.Code = Errors.No_Error, Label & ": parser profile rejected");

      case Schedule is
         when Whole_Input =>
            Feed (Data'Length, True);

         when One_Byte_Input =>
            while Cursor < Data'Length and then not Completed loop
               Feed (1, Cursor + 1 = Data'Length);
            end loop;

         when Two_Chunks =>
            Check (Split <= Data'Length, Label & ": parser split outside output");
            Feed (Split, False);
            if not Completed then
               Feed (Data'Length - Cursor, True);
            end if;

         when Random_Chunks =>
            while Cursor < Data'Length and then not Completed loop
               Random := Random * 1_664_525 + 1_013_904_223;
               declare
                  Span : constant Count :=
                    Count'Min (Data'Length - Cursor, 1 + Count (Random mod 11));
               begin
                  Feed (Span, Cursor + Span = Data'Length);
               end;
            end loop;
      end case;

      if not Completed then
         Feed (0, True);
      end if;
      Check (Cursor = Data'Length, Label & ": parser completed before consuming output");
      Check (Completed, Label & ": parser did not complete");
   end Accept_With_Public_Parser;

   procedure Run_Emission
     (Label           : String;
      Tape            : Action_Array;
      Golden          : Octet_Array;
      Maximum_Depth   : Natural;
      Schedule        : Fragment_Schedule;
      Selected_Action : Positive;
      Split           : Natural;
      Seed            : Random_State)
   is
      Target     : aliased Test_Destination;
      Subject    : Writers.Writer (Target'Access, Maximum_Depth);
      Diagnostic : Errors.Diagnostic;
      Random     : Random_State := Seed;
   begin
      Writers.Initialize (Subject, Writer_Profile, Diagnostic);
      Check_Writer_Result (Diagnostic, Label);
      Writers.Begin_Document (Subject, Diagnostic);
      Check_Writer_Result (Diagnostic, Label);

      for Index in Tape'Range loop
         case Tape (Index).Kind is
            when Object_Begin =>
               Writers.Begin_Object (Subject, Diagnostic);
            when Object_End =>
               Writers.End_Object (Subject, Diagnostic);
            when Array_Begin =>
               Writers.Begin_Array (Subject, Diagnostic);
            when Array_End =>
               Writers.End_Array (Subject, Diagnostic);
            when Name_Value =>
               Writers.Begin_Name (Subject, Diagnostic);
               Check_Writer_Result (Diagnostic, Label);
               Emit_Payload
                 (Subject,
                  Tape (Index),
                  Schedule,
                  Selected_Action,
                  Index,
                  Split,
                  Random,
                  Label);
               Writers.End_Name (Subject, Diagnostic);
            when String_Value =>
               Writers.Begin_String (Subject, Diagnostic);
               Check_Writer_Result (Diagnostic, Label);
               Emit_Payload
                 (Subject,
                  Tape (Index),
                  Schedule,
                  Selected_Action,
                  Index,
                  Split,
                  Random,
                  Label);
               Writers.End_String (Subject, Diagnostic);
            when Number_Value =>
               Writers.Begin_Number (Subject, Diagnostic);
               Check_Writer_Result (Diagnostic, Label);
               Emit_Payload
                 (Subject,
                  Tape (Index),
                  Schedule,
                  Selected_Action,
                  Index,
                  Split,
                  Random,
                  Label);
               Writers.End_Number (Subject, Diagnostic);
            when Null_Value =>
               Writers.Put_Null (Subject, Diagnostic);
            when True_Value =>
               Writers.Put_Boolean (Subject, True, Diagnostic);
            when False_Value =>
               Writers.Put_Boolean (Subject, False, Diagnostic);
         end case;
         Check_Writer_Result (Diagnostic, Label);
      end loop;

      Writers.Finish_Document (Subject, Diagnostic);
      Check_Writer_Result (Diagnostic, Label);
      Check (Target.Published, Label & ": writer did not publish");
      Check (Target.Staged_Length = Golden'Length, Label & ": golden length differs");
      for Position in Count range 0 .. Golden'Length - 1 loop
         Check
           (Target.Storage (Target.Storage'First + Offset (Position)) =
              Golden (Golden'First + Offset (Position)),
            Label & ": golden octet differs");
      end loop;
      Accept_With_Public_Parser
        (Target.Storage
           (Target.Storage'First .. Target.Storage'First + Offset (Target.Staged_Length) - 1),
         Label,
         Whole_Input,
         0,
         1);
   end Run_Emission;

   procedure Run_Fixture
     (Label : String; Tape : Action_Array; Golden_Path : String; Maximum_Depth : Natural)
   is
      Golden : constant Octet_Array := Load_Golden (Golden_Path);
   begin
      Run_Emission (Label, Tape, Golden, Maximum_Depth, Whole_Token, Tape'First, 0, 1);
      Run_Emission (Label, Tape, Golden, Maximum_Depth, One_Octet, Tape'First, 0, 1);

      for Index in Tape'Range loop
         if Tape (Index).Kind in Name_Value | String_Value | Number_Value then
            for Split in Natural range 0 .. Tape (Index).Length loop
               Run_Emission
                 (Label, Tape, Golden, Maximum_Depth, Single_Split, Index, Split, 1);
            end loop;
         end if;
      end loop;

      for Seed in Random_State range 1 .. 4 loop
         Run_Emission
           (Label, Tape, Golden, Maximum_Depth, Randomized, Tape'First, 0, Seed);
      end loop;

      Accept_With_Public_Parser (Golden, Label, One_Byte_Input, 0, 1);
      for Split in Count range 0 .. Golden'Length loop
         Accept_With_Public_Parser (Golden, Label, Two_Chunks, Split, 1);
      end loop;
      for Seed in Random_State range 1 .. 4 loop
         Accept_With_Public_Parser (Golden, Label, Random_Chunks, 0, Seed);
      end loop;
   end Run_Fixture;

   UTF8_E_Acute : constant String := Character'Val (16#C3#) & Character'Val (16#A9#);
   UTF8_Euro : constant String :=
     Character'Val (16#E2#) & Character'Val (16#82#) & Character'Val (16#AC#);
   UTF8_Grinning : constant String :=
     Character'Val (16#F0#)
     & Character'Val (16#9F#)
     & Character'Val (16#98#)
     & Character'Val (16#80#);

   Structure_Tape : constant Action_Array :=
     [Make_Action (Object_Begin),
      Make_Action (Name_Value, "meta"),
      Make_Action (Object_Begin),
      Make_Action (Name_Value, "u64"),
      Make_Action (Number_Value, "18446744073709551615"),
      Make_Action (Name_Value, "i64"),
      Make_Action (Number_Value, "-9223372036854775808"),
      Make_Action (Name_Value, "decimal"),
      Make_Action (Number_Value, "-0.000001e+9"),
      Make_Action (Object_End),
      Make_Action (Name_Value, "items"),
      Make_Action (Array_Begin),
      Make_Action (Null_Value),
      Make_Action (True_Value),
      Make_Action (False_Value),
      Make_Action (Array_Begin),
      Make_Action (String_Value, "plain"),
      Make_Action (String_Value, ""),
      Make_Action (Array_End),
      Make_Action (Array_End),
      Make_Action (Object_End)];

   Escaping_Tape : constant Action_Array :=
     [Make_Action (Object_Begin),
      Make_Action (Name_Value, "q""slash\"),
      Make_Action
        (String_Value,
         "a"
         & Character'Val (0)
         & Character'Val (8)
         & Character'Val (9)
         & Character'Val (10)
         & Character'Val (12)
         & Character'Val (13)
         & '"'
         & '\'
         & '/'
         & UTF8_E_Acute
         & UTF8_Euro
         & UTF8_Grinning),
      Make_Action (Object_End)];

   Depth_Tape : constant Action_Array :=
     [Make_Action (Array_Begin),
      Make_Action (Array_Begin),
      Make_Action (Array_Begin),
      Make_Action (Array_Begin),
      Make_Action (Array_Begin),
      Make_Action (Object_Begin),
      Make_Action (Name_Value, "x"),
      Make_Action (Array_Begin),
      Make_Action (Number_Value, "0"),
      Make_Action (Number_Value, "-0"),
      Make_Action (Number_Value, "1.2300e-10"),
      Make_Action (Number_Value, "1E+9"),
      Make_Action (Array_End),
      Make_Action (Object_End),
      Make_Action (Array_End),
      Make_Action (Array_End),
      Make_Action (Array_End),
      Make_Action (Array_End),
      Make_Action (Array_End)];

   Annotations_Tape : constant Action_Array :=
     [Make_Action (Object_Begin),
      Make_Action (Name_Value, "annotations"),
      Make_Action (Object_Begin),
      Make_Action (Name_Value, "org.opencontainers.image.ref.name"),
      Make_Action (String_Value, "v1"),
      Make_Action (Name_Value, "x-custom"),
      Make_Action (Array_Begin),
      Make_Action (Number_Value, "1"),
      Make_Action (Object_Begin),
      Make_Action (Name_Value, "enabled"),
      Make_Action (True_Value),
      Make_Action (Object_End),
      Make_Action (Array_End),
      Make_Action (Object_End),
      Make_Action (Name_Value, "unknown"),
      Make_Action (Null_Value),
      Make_Action (Object_End)];

begin
   Run_Fixture
     ("structure", Structure_Tape, "tests/writer-corpus/golden/structure.hex", 3);
   Run_Fixture
     ("escaping", Escaping_Tape, "tests/writer-corpus/golden/escaping.hex", 1);
   Run_Fixture ("depth", Depth_Tape, "tests/writer-corpus/golden/depth.hex", 7);
   Run_Fixture
     ("annotations", Annotations_Tape, "tests/writer-corpus/golden/annotations.hex", 4);
   Ada.Text_IO.Put_Line ("writer corpus: 4 event tapes passed exact output and public-parser replay");
end Flyology_JSON.Writer_Corpus_Tests;
