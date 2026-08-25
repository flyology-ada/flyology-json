with Ada.Command_Line;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Flyology_JSON.Parser_Core;
with Interfaces;

procedure Flyology_JSON.Corpus_Runner is

   package Core renames Flyology_JSON.Parser_Core;
   package Stream_IO renames Ada.Streams.Stream_IO;

   use type Ada.Streams.Stream_Element_Count;
   use type Core.Byte_Offset;
   use type Core.Error_Code;
   use type Core.Next_Outcome;
   use type Interfaces.Unsigned_32;

   subtype Count is Ada.Streams.Stream_Element_Count;
   subtype Offset is Ada.Streams.Stream_Element_Offset;
   subtype Work_Count is Interfaces.Unsigned_64;

   --  The selected malformed-depth fixtures contain 100,000 opening
   --  containers.  This exact test storage lets the syntax campaign reach
   --  their terminal truncation instead of mistaking resource denial for a
   --  successful malformed-input verdict.  It is not a parser default.
   Campaign_Depth       : constant := 100_000;
   --  Explicit corpus-runner storage.  Resource denials remain distinguishable
   --  from malformed-input verdicts and these values are not parser defaults.
   Campaign_Name_Octets : constant := 262_144;
   Campaign_Names       : constant := Campaign_Depth;

   type Parse_Observation is record
      Outcome    : Core.Next_Outcome := Core.Need_Input;
      Diagnostic : Core.Diagnostic := (Code => Core.No_Error, Offset => 0);
   end record;

   Work_Limit_Exceeded : exception;
   Work_Limit_Active   : Boolean := False;
   Work_Ceiling        : Work_Count := 0;
   Work_Used           : Work_Count := 0;

   procedure Charge_Work (Amount : Work_Count) is
   begin
      if Work_Limit_Active then
         if Amount > Work_Ceiling - Work_Used then
            raise Work_Limit_Exceeded;
         end if;
         Work_Used := Work_Used + Amount;
      end if;
   end Charge_Work;

   procedure Drain
     (Parser      : in out Core.Parser;
      Input       : Ada.Streams.Stream_Element_Array;
      Final_Input : Boolean;
      Observation : out Parse_Observation)
   is
      Used   : Count := 0;
      Result : Core.Next_Result;
   begin
      loop
         --  Charging before every call makes a repeated zero-consumption
         --  Event_Ready result finite under the caller's campaign ceiling.
         Charge_Work (1);
         if Used < Input'Length then
            declare
               First : constant Offset := Input'First + Offset (Used);
            begin
               Core.Next
                 (Parser, Input (First .. Input'Last), Final_Input, Result);
            end;
         else
            declare
               Empty : Ada.Streams.Stream_Element_Array (1 .. 0);
            begin
               Core.Next (Parser, Empty, Final_Input, Result);
            end;
         end if;

         if Result.Consumed > Input'Length - Used then
            raise Program_Error
              with "parser consumed beyond the supplied corpus chunk";
         end if;
         Used := Used + Result.Consumed;

         case Result.Outcome is
            when Core.Event_Ready =>
               null;

            when Core.Need_Input  =>
               if Used /= Input'Length then
                  raise Program_Error
                    with
                      "parser requested input before consuming the corpus chunk";
               end if;
               Observation :=
                 (Outcome => Result.Outcome, Diagnostic => Result.Diagnostic);
               return;

            when others           =>
               Observation :=
                 (Outcome => Result.Outcome, Diagnostic => Result.Diagnostic);
               return;
         end case;
      end loop;
   end Drain;

   function Parse_Monolith
     (Input : Ada.Streams.Stream_Element_Array) return Parse_Observation
   is
      Parser      :
        Core.Parser (Campaign_Depth, Campaign_Name_Octets, Campaign_Names);
      Observation : Parse_Observation;
   begin
      Charge_Work (Work_Count (Input'Length));
      Core.Initialize (Parser);
      Drain (Parser, Input, True, Observation);
      return Observation;
   end Parse_Monolith;

   function Parse_At_Split
     (Input : Ada.Streams.Stream_Element_Array; Split : Count)
      return Parse_Observation
   is
      Parser      :
        Core.Parser (Campaign_Depth, Campaign_Name_Octets, Campaign_Names);
      Observation : Parse_Observation;
   begin
      Charge_Work (Work_Count (Input'Length));
      Core.Initialize (Parser);

      if Split = 0 then
         declare
            Empty : Ada.Streams.Stream_Element_Array (29 .. 28);
         begin
            Drain (Parser, Empty, False, Observation);
         end;
         if Observation.Outcome /= Core.Need_Input then
            return Observation;
         end if;
      else
         Drain
           (Parser,
            Input (Input'First .. Input'First + Offset (Split) - 1),
            False,
            Observation);
         if Observation.Outcome /= Core.Need_Input then
            return Observation;
         end if;
      end if;

      if Split < Input'Length then
         Drain
           (Parser,
            Input (Input'First + Offset (Split) .. Input'Last),
            True,
            Observation);
      else
         declare
            Empty : Ada.Streams.Stream_Element_Array (17 .. 16);
         begin
            Drain (Parser, Empty, True, Observation);
         end;
      end if;
      return Observation;
   end Parse_At_Split;

   function Parse_One_Byte
     (Input : Ada.Streams.Stream_Element_Array) return Parse_Observation
   is
      Parser      :
        Core.Parser (Campaign_Depth, Campaign_Name_Octets, Campaign_Names);
      Observation : Parse_Observation;
   begin
      Core.Initialize (Parser);
      if Input'Length = 0 then
         Drain (Parser, Input, True, Observation);
         return Observation;
      end if;

      for Position in Count range 0 .. Input'Length - 1 loop
         declare
            Element_Index : constant Offset := Input'First + Offset (Position);
         begin
            Drain
              (Parser,
               Input (Element_Index .. Element_Index),
               Position = Input'Length - 1,
               Observation);
         end;
         if Position < Input'Length - 1
           and then Observation.Outcome /= Core.Need_Input
         then
            return Observation;
         end if;
      end loop;
      return Observation;
   end Parse_One_Byte;

   function Parse_Randomized
     (Input : Ada.Streams.Stream_Element_Array; Seed : Interfaces.Unsigned_32)
      return Parse_Observation
   is
      Generator   : Interfaces.Unsigned_32 := Seed;
      Parser      :
        Core.Parser (Campaign_Depth, Campaign_Name_Octets, Campaign_Names);
      Observation : Parse_Observation;
      Position    : Count := 0;
   begin
      Core.Initialize (Parser);
      if Input'Length = 0 then
         Drain (Parser, Input, True, Observation);
         return Observation;
      end if;

      while Position < Input'Length loop
         Generator := Generator * 1_664_525 + 1_013_904_223;
         declare
            Remaining : constant Count := Input'Length - Position;
            Requested : constant Count := Count (Generator mod 257) + 1;
            Length    : constant Count := Count'Min (Remaining, Requested);
            First     : constant Offset := Input'First + Offset (Position);
            Last      : constant Offset := First + Offset (Length) - 1;
         begin
            Drain
              (Parser,
               Input (First .. Last),
               Position + Length = Input'Length,
               Observation);
            Position := Position + Length;
         end;
         if Position < Input'Length
           and then Observation.Outcome /= Core.Need_Input
         then
            return Observation;
         end if;
      end loop;
      return Observation;
   end Parse_Randomized;

   function Matches
     (Observation : Parse_Observation; Expectation : String) return Boolean
   is
      Accepted : constant Boolean :=
        Observation.Outcome = Core.Document_Complete;
   begin
      if Expectation = "accept" or else Expectation = "depth_dependent_accept"
      then
         return Accepted;
      elsif Expectation = "reject_malformed" then
         return
           Observation.Outcome = Core.Parse_Failed
           and then Observation.Diagnostic.Code
                    in Core.Unexpected_Token
                     | Core.Trailing_Input
                     | Core.Truncated_Input
                     | Core.Invalid_Literal
                     | Core.Invalid_Number
                     | Core.Invalid_UTF8
                     | Core.Invalid_Escape
                     | Core.Invalid_Surrogate
                     | Core.Raw_Control_Character;
      elsif Expectation = "reject_duplicate" then
         return
           Observation.Outcome = Core.Parse_Failed
           and then Observation.Diagnostic.Code = Core.Duplicate_Name;
      else
         raise Program_Error with "unknown corpus expectation: " & Expectation;
      end if;
   end Matches;

   procedure Read_And_Run
     (Fixture_Path : String;
      Expectation  : String;
      Schedule     : String;
      Passed       : out Boolean)
   is
      Input_File : Stream_IO.File_Type;
   begin
      Stream_IO.Open (Input_File, Stream_IO.In_File, Fixture_Path);
      declare
         Length   : constant Stream_IO.Count := Stream_IO.Size (Input_File);
         Input    : Ada.Streams.Stream_Element_Array (1 .. Offset (Length));
         Last     : Offset := 0;
         Baseline : Parse_Observation;

         procedure Check_One (Observation : Parse_Observation) is
         begin
            if not Matches (Observation, Expectation) then
               Passed := False;
            elsif Expectation in "reject_malformed" | "reject_duplicate"
              and then (Observation.Diagnostic.Code /= Baseline.Diagnostic.Code
                        or else Observation.Diagnostic.Offset
                                /= Baseline.Diagnostic.Offset)
            then
               Passed := False;
            else
               null;
            end if;
         end Check_One;
      begin
         if Input'Length > 0 then
            Stream_IO.Read (Input_File, Input, Last);
            if Last /= Input'Last then
               raise Program_Error with "short corpus read: " & Fixture_Path;
            end if;
         end if;
         Stream_IO.Close (Input_File);

         Passed := True;
         Baseline := Parse_Monolith (Input);
         Check_One (Baseline);
         if Schedule = "monolith" then
            null;
         elsif Schedule = "one-byte" then
            Check_One (Parse_One_Byte (Input));
         elsif Schedule = "every-split" then
            for Split in Count range 0 .. Input'Length loop
               Check_One (Parse_At_Split (Input, Split));
            end loop;
         elsif Schedule = "randomized" then
            for Seed in Interfaces.Unsigned_32 range 1 .. 8 loop
               Check_One (Parse_Randomized (Input, Seed));
               exit when not Passed;
            end loop;
         else
            raise Program_Error with "unknown schedule: " & Schedule;
         end if;
      end;
   exception
      when others =>
         if Stream_IO.Is_Open (Input_File) then
            Stream_IO.Close (Input_File);
         end if;
         raise;
   end Read_And_Run;

   procedure Run_Expectations
     (Corpus_Root       : String;
      Expectations_File : String;
      Schedule          : String;
      Fixture_Count     : in out Natural;
      Unexpected_Count  : in out Natural)
   is
      Input : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Open (Input, Ada.Text_IO.In_File, Expectations_File);
      while not Ada.Text_IO.End_Of_File (Input) loop
         declare
            Line      : constant String := Ada.Text_IO.Get_Line (Input);
            Separator : constant Natural :=
              Ada.Strings.Fixed.Index (Line, String'(1 => ASCII.HT));
         begin
            if Line'Length > 0 and then Line (Line'First) /= '#' then
               if Separator = 0 then
                  raise Program_Error
                    with "malformed expectation line: " & Line;
               end if;
               declare
                  Relative_Path : constant String :=
                    Line (Line'First .. Separator - 1);
                  Expectation   : constant String :=
                    Line (Separator + 1 .. Line'Last);
                  Passed        : Boolean;
               begin
                  Read_And_Run
                    (Corpus_Root & "/" & Relative_Path,
                     Expectation,
                     Schedule,
                     Passed);
                  Fixture_Count := Fixture_Count + 1;
                  if not Passed then
                     Unexpected_Count := Unexpected_Count + 1;
                     Ada.Text_IO.Put_Line ("UNEXPECTED " & Relative_Path);
                  end if;
               end;
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (Input);
   end Run_Expectations;

   function Every_Split_Minimum_Work (Length : Work_Count) return Work_Count is
   begin
      if Length > Work_Count'Last - 2
        or else Length + 1 > Work_Count'Last / (Length + 2)
      then
         raise Program_Error with "every-split fixture work estimate overflow";
      end if;
      return (Length + 1) * (Length + 2);
   end Every_Split_Minimum_Work;

   procedure Add_Work (Required : Work_Count; Total : in out Work_Count) is
   begin
      if Required > Work_Count'Last - Total then
         raise Program_Error
           with "every-split campaign work estimate overflow";
      end if;
      Total := Total + Required;
   end Add_Work;

   procedure Add_Every_Split_Work
     (Fixture_Path : String; Total : in out Work_Count)
   is
      Input_File : Stream_IO.File_Type;
   begin
      Stream_IO.Open (Input_File, Stream_IO.In_File, Fixture_Path);
      declare
         Length   : constant Work_Count :=
           Work_Count (Stream_IO.Size (Input_File));
         --  One monolithic parse plus Length + 1 split parses.  Each parse
         --  requires at least one Next call and reserves Length planned input
         --  octets.  Additional Next calls are charged by the runtime ledger.
         Required : constant Work_Count := Every_Split_Minimum_Work (Length);
      begin
         Stream_IO.Close (Input_File);
         Add_Work (Required, Total);
      end;
   exception
      when others =>
         if Stream_IO.Is_Open (Input_File) then
            Stream_IO.Close (Input_File);
         end if;
         raise;
   end Add_Every_Split_Work;

   procedure Estimate_Every_Split_Work
     (Corpus_Root       : String;
      Expectations_File : String;
      Total             : in out Work_Count)
   is
      Input : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Open (Input, Ada.Text_IO.In_File, Expectations_File);
      while not Ada.Text_IO.End_Of_File (Input) loop
         declare
            Line      : constant String := Ada.Text_IO.Get_Line (Input);
            Separator : constant Natural :=
              Ada.Strings.Fixed.Index (Line, String'(1 => ASCII.HT));
         begin
            if Line'Length > 0 and then Line (Line'First) /= '#' then
               if Separator = 0 then
                  raise Program_Error
                    with "malformed expectation line: " & Line;
               end if;
               Add_Every_Split_Work
                 (Corpus_Root & "/" & Line (Line'First .. Separator - 1),
                  Total);
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (Input);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (Input) then
            Ada.Text_IO.Close (Input);
         end if;
         raise;
   end Estimate_Every_Split_Work;

   procedure Self_Test_Work_Accounting is
      Total             : Work_Count := 0;
      Addition_Overflow : Boolean := False;
      Product_Overflow  : Boolean := False;
      Total_Overflow    : Boolean := False;
   begin
      if Every_Split_Minimum_Work (5) /= 42 then
         raise Program_Error with "every-split minimum-work formula changed";
      end if;

      begin
         Total := Every_Split_Minimum_Work (Work_Count'Last);
      exception
         when Program_Error =>
            Addition_Overflow := True;
      end;
      if not Addition_Overflow then
         raise Program_Error with "fixture addition overflow was not rejected";
      end if;

      begin
         Total := Every_Split_Minimum_Work (4_294_967_296);
      exception
         when Program_Error =>
            Product_Overflow := True;
      end;
      if not Product_Overflow then
         raise Program_Error with "fixture product overflow was not rejected";
      end if;

      Total := Work_Count'Last - 41;
      begin
         Add_Work (Every_Split_Minimum_Work (5), Total);
      exception
         when Program_Error =>
            Total_Overflow := True;
      end;
      if not Total_Overflow then
         raise Program_Error with "campaign work overflow was not rejected";
      end if;

      Ada.Text_IO.Put_Line ("every-split work-accounting self-test: PASS");
   end Self_Test_Work_Accounting;

   Fixture_Count    : Natural := 0;
   Unexpected_Count : Natural := 0;

begin
   if Ada.Command_Line.Argument_Count = 1
     and then Ada.Command_Line.Argument (1) = "--self-test-work-accounting"
   then
      Self_Test_Work_Accounting;
      return;
   end if;

   if Ada.Command_Line.Argument_Count not in 2 .. 3 then
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "usage: flyology_json-corpus_runner CORPUS-DIRECTORY "
         & "{monolith|one-byte|randomized} | CORPUS-DIRECTORY "
         & "every-split MAX-WORK-UNITS");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   declare
      Corpus_Directory : constant String := Ada.Command_Line.Argument (1);
      Schedule         : constant String := Ada.Command_Line.Argument (2);
   begin
      if Schedule /= "monolith"
        and then Schedule /= "one-byte"
        and then Schedule /= "every-split"
        and then Schedule /= "randomized"
      then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error, "unknown schedule: " & Schedule);
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      if Schedule = "every-split" then
         if Ada.Command_Line.Argument_Count /= 3 then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "every-split requires an explicit positive MAX-WORK-UNITS ceiling");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;

         declare
            Maximum_Work : Work_Count;
            Minimum_Work : Work_Count := 0;
         begin
            begin
               Maximum_Work :=
                 Work_Count'Value (Ada.Command_Line.Argument (3));
            exception
               when Constraint_Error =>
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "MAX-WORK-UNITS must be a positive unsigned integer");
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
                  return;
            end;
            if Maximum_Work = 0 then
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "MAX-WORK-UNITS must be greater than zero");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;

            Estimate_Every_Split_Work
              (Corpus_Directory & "/json_test_suite",
               Corpus_Directory & "/json_test_suite/expectations.tsv",
               Minimum_Work);
            Estimate_Every_Split_Work
              (Corpus_Directory & "/json_schema_test_suite",
               Corpus_Directory & "/json_schema_test_suite/expectations.tsv",
               Minimum_Work);
            if Minimum_Work > Maximum_Work then
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "every-split refused before parsing: minimum work units="
                  & Work_Count'Image (Minimum_Work)
                  & ", caller ceiling="
                  & Work_Count'Image (Maximum_Work));
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               return;
            end if;
            Ada.Text_IO.Put_Line
              ("every-split minimum work units="
               & Work_Count'Image (Minimum_Work)
               & " ceiling="
               & Work_Count'Image (Maximum_Work));
            Work_Ceiling := Maximum_Work;
            Work_Used := 0;
            Work_Limit_Active := True;
         end;
      elsif Ada.Command_Line.Argument_Count /= 2 then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "MAX-WORK-UNITS is accepted only for the every-split schedule");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      Run_Expectations
        (Corpus_Directory & "/json_test_suite",
         Corpus_Directory & "/json_test_suite/expectations.tsv",
         Schedule,
         Fixture_Count,
         Unexpected_Count);
      Run_Expectations
        (Corpus_Directory & "/json_schema_test_suite",
         Corpus_Directory & "/json_schema_test_suite/expectations.tsv",
         Schedule,
         Fixture_Count,
         Unexpected_Count);
   end;

   Ada.Text_IO.Put_Line
     ("corpus parser: fixtures="
      & Natural'Image (Fixture_Count)
      & " unexpected="
      & Natural'Image (Unexpected_Count));
   if Unexpected_Count /= 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
   if Work_Limit_Active then
      Ada.Text_IO.Put_Line
        ("every-split actual work units=" & Work_Count'Image (Work_Used));
   end if;
exception
   when Work_Limit_Exceeded =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "every-split denied by caller work ceiling="
         & Work_Count'Image (Work_Ceiling)
         & " after accepted work units="
         & Work_Count'Image (Work_Used));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Flyology_JSON.Corpus_Runner;
