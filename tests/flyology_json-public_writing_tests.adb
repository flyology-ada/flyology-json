with Ada.Streams;
with Flyology_JSON.Destinations;
with Flyology_JSON.Errors;
with Flyology_JSON.Profiles;
with Flyology_JSON.Writing;

procedure Flyology_JSON.Public_Writing_Tests is

   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Array;
   use type Ada.Streams.Stream_Element_Count;
   use type Errors.Byte_Offset;
   use type Errors.Coordinate_Kind;
   use type Errors.Diagnostic;
   use type Errors.Error_Code;
   use type Profiles.Writer_Profile;

   subtype Count is Ada.Streams.Stream_Element_Count;
   subtype Offset is Ada.Streams.Stream_Element_Offset;

   Fixture_Capacity : constant := 4_096;

   protected Transfer_Gate is
      procedure Reset;
      procedure Signal;
      entry Wait;
   private
      Signalled : Boolean := False;
   end Transfer_Gate;

   protected body Transfer_Gate is
      procedure Reset is
      begin
         Signalled := False;
      end Reset;

      procedure Signal is
      begin
         Signalled := True;
      end Signal;

      entry Wait when Signalled is
      begin
         null;
      end Wait;
   end Transfer_Gate;

   type Test_Destination is limited record
      Storage       : Ada.Streams.Stream_Element_Array (-31 .. -32 + Fixture_Capacity);
      Capacity      : Count := Fixture_Capacity;
      Staged_Length : Count := 0;
      Active        : Boolean := False;
      Published     : Boolean := False;
      Begin_Calls   : Natural := 0;
      Write_Calls   : Natural := 0;
      Commit_Calls  : Natural := 0;
      Abort_Calls   : Natural := 0;
      Pause_Begin   : Boolean := False;
      Pause_Write   : Boolean := False;
      Pause_Commit  : Boolean := False;
      Pause_Abort   : Boolean := False;
      Fail_Abort    : Boolean := False;
   end record;

   procedure Destination_Begin
     (Target : in out Test_Destination;
      Status : out Destinations.Begin_Status)
   is
   begin
      Target.Begin_Calls := Target.Begin_Calls + 1;
      if Target.Pause_Begin then
         Transfer_Gate.Signal;
         delay 0.05;
      end if;
      Target.Staged_Length := 0;
      Target.Active := True;
      Target.Published := False;
      Status := Destinations.Begin_Succeeded;
   end Destination_Begin;

   procedure Destination_Write
     (Target  : in out Test_Destination;
      Data    : Ada.Streams.Stream_Element_Array;
      Written : out Count;
      Status  : out Destinations.Write_Status)
   is
      Available : constant Count := Target.Capacity - Target.Staged_Length;
   begin
      Target.Write_Calls := Target.Write_Calls + 1;
      if Target.Pause_Write then
         Transfer_Gate.Signal;
         delay 0.05;
      end if;

      Written := Count'Min (Data'Length, Available);
      if Written > 0 then
         for Position in Count range 0 .. Written - 1 loop
            Target.Storage
              (Target.Storage'First + Offset (Target.Staged_Length + Position)) :=
                Data (Data'First + Offset (Position));
         end loop;
      end if;
      Target.Staged_Length := Target.Staged_Length + Written;
      Status :=
        (if Written = Data'Length
         then Destinations.Write_Succeeded
         else Destinations.Write_Exhausted);
   end Destination_Write;

   procedure Destination_Commit
     (Target : in out Test_Destination;
      Status : out Destinations.Commit_Status)
   is
   begin
      Target.Commit_Calls := Target.Commit_Calls + 1;
      if Target.Pause_Commit then
         Transfer_Gate.Signal;
         delay 0.05;
      end if;
      Target.Active := False;
      Target.Published := True;
      Status := Destinations.Commit_Succeeded;
   end Destination_Commit;

   procedure Destination_Abort
     (Target : in out Test_Destination;
      Status : out Destinations.Abort_Status)
   is
   begin
      Target.Abort_Calls := Target.Abort_Calls + 1;
      if Target.Pause_Abort then
         Transfer_Gate.Signal;
         delay 0.05;
      end if;
      Target.Active := False;
      Target.Staged_Length := 0;
      Status :=
        (if Target.Fail_Abort
         then Destinations.Abort_Failed
         else Destinations.Abort_Succeeded);
   end Destination_Abort;

   package Writers is new Flyology_JSON.Writing
     (Destination_Type   => Test_Destination,
      Destination_Begin  => Destination_Begin,
      Destination_Write  => Destination_Write,
      Destination_Commit => Destination_Commit,
      Destination_Abort  => Destination_Abort);

   use type Writers.Writer_State;

   type Raise_Point is
     (Raise_Nowhere,
      Raise_In_Begin,
      Raise_In_Write,
      Raise_In_Commit,
      Raise_In_Abort);

   Destination_Contract_Error : exception;

   type Raising_Destination is limited record
      Raise_At     : Raise_Point := Raise_Nowhere;
      Active       : Boolean := False;
      Published    : Boolean := False;
      Begin_Calls  : Natural := 0;
      Write_Calls  : Natural := 0;
      Commit_Calls : Natural := 0;
      Abort_Calls  : Natural := 0;
   end record;

   procedure Raising_Begin
     (Target : in out Raising_Destination;
      Status : out Destinations.Begin_Status)
   is
   begin
      Target.Begin_Calls := Target.Begin_Calls + 1;
      if Target.Raise_At = Raise_In_Begin then
         raise Destination_Contract_Error;
      end if;
      Target.Active := True;
      Status := Destinations.Begin_Succeeded;
   end Raising_Begin;

   procedure Raising_Write
     (Target  : in out Raising_Destination;
      Data    : Ada.Streams.Stream_Element_Array;
      Written : out Count;
      Status  : out Destinations.Write_Status)
   is
   begin
      Target.Write_Calls := Target.Write_Calls + 1;
      if Target.Raise_At = Raise_In_Write then
         raise Destination_Contract_Error;
      end if;
      Written := Data'Length;
      Status := Destinations.Write_Succeeded;
   end Raising_Write;

   procedure Raising_Commit
     (Target : in out Raising_Destination;
      Status : out Destinations.Commit_Status)
   is
   begin
      Target.Commit_Calls := Target.Commit_Calls + 1;
      if Target.Raise_At = Raise_In_Commit then
         --  Model the most dangerous contract violation: publication may
         --  already have happened when the exception crosses the boundary.
         Target.Active := False;
         Target.Published := True;
         raise Destination_Contract_Error;
      end if;
      Target.Active := False;
      Target.Published := True;
      Status := Destinations.Commit_Succeeded;
   end Raising_Commit;

   procedure Raising_Abort
     (Target : in out Raising_Destination;
      Status : out Destinations.Abort_Status)
   is
   begin
      Target.Abort_Calls := Target.Abort_Calls + 1;
      Target.Active := False;
      if Target.Raise_At = Raise_In_Abort then
         raise Destination_Contract_Error;
      end if;
      Status := Destinations.Abort_Succeeded;
   end Raising_Abort;

   package Raising_Writers is new Flyology_JSON.Writing
     (Destination_Type   => Raising_Destination,
      Destination_Begin  => Raising_Begin,
      Destination_Write  => Raising_Write,
      Destination_Commit => Raising_Commit,
      Destination_Abort  => Raising_Abort);

   procedure Check (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Check;

   function Profile (Version : Positive := 1) return Profiles.Writer_Profile is
     (Syntax     => (Family => Profiles.RFC_8259, Version => Version),
      Unicode    => (Family => Profiles.Unicode_Scalars, Version => 1),
      Formatting => (Policy => Profiles.Ordinary_Compact, Version => 1));

   function To_Input
     (Text : String; First : Offset) return Ada.Streams.Stream_Element_Array
   is
      Result : Ada.Streams.Stream_Element_Array
        (First .. First + Offset (Text'Length) - 1);
   begin
      for Position in Text'Range loop
         Result (First + Offset (Position - Text'First)) :=
           Character'Pos (Text (Position));
      end loop;
      return Result;
   end To_Input;

   procedure Check_Output (Target : Test_Destination; Expected : String) is
   begin
      Check (Target.Published, "writer did not publish");
      Check (Target.Staged_Length = Expected'Length, "writer output length differs");
      for Position in Expected'Range loop
         Check
           (Target.Storage
              (Target.Storage'First + Offset (Position - Expected'First)) =
              Character'Pos (Expected (Position)),
            "writer output octet differs");
      end loop;
   end Check_Output;

   procedure Test_Profile_And_Lifecycle is
      Target     : aliased Test_Destination;
      Subject    : Writers.Writer (Target'Access, Maximum_Depth => 0);
      Diagnostic : Errors.Diagnostic;
   begin
      Writers.Put_Null (Subject, Diagnostic);
      Check (Diagnostic.Code = Errors.Invalid_State, "uninitialized call was admitted");

      Writers.Initialize (Subject, Profile (2), Diagnostic);
      Check (Diagnostic.Code = Errors.Unsupported_Profile, "unknown profile was accepted");
      Check (Writers.State (Subject) = Writers.Failed, "profile failure state differs");
      Check (not Writers.Has_Applied_Profile (Subject), "failed profile was published");
      Check (Target.Begin_Calls = 0, "profile validation touched destination");

      Writers.Reset (Subject, Profile, Diagnostic);
      Check (Diagnostic.Code = Errors.No_Error, "valid reset did not recover profile failure");
      Check (Writers.State (Subject) = Writers.Ready, "valid reset state differs");
      Check (Writers.Has_Applied_Profile (Subject), "valid profile was not frozen");
      Check (Writers.Applied_Profile (Subject) = Profile, "applied profile identity differs");

      Writers.Abort_Document (Subject, Diagnostic);
      Writers.Reset (Subject, Profile (2), Diagnostic);
      Check (Diagnostic.Code = Errors.Unsupported_Profile, "invalid reuse profile was accepted");
      Writers.Reset (Subject, Profile, Diagnostic);
      Check (Diagnostic.Code = Errors.No_Error, "valid second reset did not recover");

      Writers.Finish_Document (Subject, Diagnostic);
      Check (Diagnostic.Code = Errors.Invalid_Writer_Grammar, "ready finish was not grammar failure");
      Check (Diagnostic.Coordinate = Errors.JSON_Call_Ordinal, "ready finish coordinate differs");
      Check (Diagnostic.Offset = 0, "ready finish ordinal differs");
      Check (Target.Begin_Calls = 0, "ready finish touched destination");
   end Test_Profile_And_Lifecycle;

   procedure Test_Ordinary_Compact is
      Target     : aliased Test_Destination;
      Subject    : Writers.Writer (Target'Access, Maximum_Depth => 3);
      Diagnostic : Errors.Diagnostic;
      UTF8_Lead  : constant Ada.Streams.Stream_Element_Array (41 .. 41) := [41 => 16#C3#];
      UTF8_Tail  : constant Ada.Streams.Stream_Element_Array (-8 .. -8) := [-8 => 16#A9#];
   begin
      Writers.Initialize (Subject, Profile, Diagnostic);
      Writers.Begin_Document (Subject, Diagnostic);
      Writers.Begin_Object (Subject, Diagnostic);
      Writers.Begin_Name (Subject, Diagnostic);
      Writers.Put_Name_Fragment (Subject, To_Input ("s", -12), Diagnostic);
      Writers.End_Name (Subject, Diagnostic);
      Writers.Begin_String (Subject, Diagnostic);
      Writers.Put_String_Fragment
        (Subject,
         [17 => Character'Pos ('x'), 18 => 16#0A#, 19 => Character'Pos ('"')],
         Diagnostic);
      Writers.Put_String_Fragment (Subject, UTF8_Lead, Diagnostic);
      Writers.Put_String_Fragment (Subject, UTF8_Tail, Diagnostic);
      Writers.End_String (Subject, Diagnostic);
      Writers.Begin_Name (Subject, Diagnostic);
      Writers.Put_Name_Fragment (Subject, To_Input ("n", 200), Diagnostic);
      Writers.End_Name (Subject, Diagnostic);
      Writers.Begin_Number (Subject, Diagnostic);
      Writers.Put_Number_Fragment (Subject, To_Input ("-12.", -100), Diagnostic);
      Writers.Put_Number_Fragment (Subject, To_Input ("3e+4", 70), Diagnostic);
      Writers.End_Number (Subject, Diagnostic);
      Writers.Begin_Name (Subject, Diagnostic);
      Writers.Put_Name_Fragment (Subject, To_Input ("b", 5), Diagnostic);
      Writers.End_Name (Subject, Diagnostic);
      Writers.Begin_Array (Subject, Diagnostic);
      Writers.Put_Boolean (Subject, True, Diagnostic);
      Writers.Put_Null (Subject, Diagnostic);
      Writers.End_Array (Subject, Diagnostic);
      Writers.End_Object (Subject, Diagnostic);
      Writers.Finish_Document (Subject, Diagnostic);
      Check (Diagnostic.Code = Errors.No_Error, "ordinary compact writer failed");
      Check (Writers.State (Subject) = Writers.Completed, "writer did not complete");
      Check_Output
        (Target,
         "{""s"":""x\n\""" & Character'Val (16#C3#) & Character'Val (16#A9#)
         & """,""n"":-12.3e+4,""b"":[true,null]}");
      Check (Target.Abort_Calls = 0, "successful writer aborted");
   end Test_Ordinary_Compact;

   procedure Test_Depth_And_Exhaustion is
      Target     : aliased Test_Destination;
      Subject    : Writers.Writer (Target'Access, Maximum_Depth => 0);
      Diagnostic : Errors.Diagnostic;
   begin
      Writers.Initialize (Subject, Profile, Diagnostic);
      Writers.Begin_Document (Subject, Diagnostic);
      Writers.Begin_Array (Subject, Diagnostic);
      Check (Diagnostic.Code = Errors.Depth_Exhausted, "depth boundary was not enforced");
      Check (Diagnostic.Offset = 1, "depth boundary ordinal differs");
      Check (Target.Abort_Calls = 1, "depth failure did not abort once");

      Writers.Reset (Subject, Profile, Diagnostic);
      Target.Capacity := 2;
      Writers.Begin_Document (Subject, Diagnostic);
      Writers.Begin_String (Subject, Diagnostic);
      Writers.Put_String_Fragment (Subject, To_Input ("ab", 50), Diagnostic);
      Check (Diagnostic.Code = Errors.Destination_Exhausted, "destination exhaustion was missed");
      Check (Diagnostic.Coordinate = Errors.Staged_Output_Byte, "exhaustion coordinate differs");
      Check (Diagnostic.Offset = 2, "exhaustion offset differs");
      Check (not Target.Published, "exhausted destination published");
      Check (Target.Abort_Calls = 2, "exhaustion did not abort exactly once");
   end Test_Depth_And_Exhaustion;

   procedure Test_Controlled_Cleanup is
      Target     : aliased Test_Destination;
      Diagnostic : Errors.Diagnostic;
   begin
      declare
         Subject : Writers.Writer (Target'Access, Maximum_Depth => 0);
      begin
         Writers.Initialize (Subject, Profile, Diagnostic);
         Writers.Begin_Document (Subject, Diagnostic);
         Check (Target.Active, "cleanup fixture did not own a transaction");
      end;
      Check (Target.Abort_Calls = 1, "controlled writer did not abort on scope exit");
      Check (not Target.Active, "controlled cleanup leaked a transaction");
   end Test_Controlled_Cleanup;

   procedure Test_Extreme_Array_Bounds is
      Target     : aliased Test_Destination;
      Subject    : Writers.Writer (Target'Access, Maximum_Depth => 1);
      Diagnostic : Errors.Diagnostic;
      High_Empty : constant Ada.Streams.Stream_Element_Array
        (Offset'Last .. Offset'Last - 1) := [others => 0];
      High_One : constant Ada.Streams.Stream_Element_Array
        (Offset'Last .. Offset'Last) := [Offset'Last => Character'Pos ('a')];
      High_Text : constant Ada.Streams.Stream_Element_Array
        (Offset'Last - 2 .. Offset'Last) :=
          [Character'Pos ('b'), Character'Pos ('c'), Character'Pos ('d')];
      High_Number : constant Ada.Streams.Stream_Element_Array
        (Offset'Last - 2 .. Offset'Last) :=
          [Character'Pos ('1'), Character'Pos ('2'), Character'Pos ('3')];
      Low_Empty : constant Ada.Streams.Stream_Element_Array
        (Offset'First + 1 .. Offset'First) := [others => 0];
      Low_One : constant Ada.Streams.Stream_Element_Array
        (Offset'First .. Offset'First) := [Offset'First => Character'Pos ('e')];
      Low_Text : constant Ada.Streams.Stream_Element_Array
        (Offset'First .. Offset'First + 2) :=
          [Character'Pos ('f'), Character'Pos ('g'), Character'Pos ('h')];
      Low_Number : constant Ada.Streams.Stream_Element_Array
        (Offset'First .. Offset'First + 2) :=
          [Character'Pos ('4'), Character'Pos ('5'), Character'Pos ('6')];
   begin
      Writers.Initialize (Subject, Profile, Diagnostic);
      Writers.Begin_Document (Subject, Diagnostic);
      Writers.Begin_Object (Subject, Diagnostic);
      Writers.Begin_Name (Subject, Diagnostic);
      Writers.Put_Name_Fragment (Subject, High_Empty, Diagnostic);
      Writers.Put_Name_Fragment (Subject, High_One, Diagnostic);
      Writers.Put_Name_Fragment (Subject, High_Text, Diagnostic);
      Writers.Put_Name_Fragment (Subject, Low_Empty, Diagnostic);
      Writers.Put_Name_Fragment (Subject, Low_One, Diagnostic);
      Writers.Put_Name_Fragment (Subject, Low_Text, Diagnostic);
      Writers.End_Name (Subject, Diagnostic);
      Writers.Begin_String (Subject, Diagnostic);
      Writers.Put_String_Fragment (Subject, High_Empty, Diagnostic);
      Writers.Put_String_Fragment (Subject, High_One, Diagnostic);
      Writers.Put_String_Fragment (Subject, High_Text, Diagnostic);
      Writers.Put_String_Fragment (Subject, Low_Empty, Diagnostic);
      Writers.Put_String_Fragment (Subject, Low_One, Diagnostic);
      Writers.Put_String_Fragment (Subject, Low_Text, Diagnostic);
      Writers.End_String (Subject, Diagnostic);
      Writers.End_Object (Subject, Diagnostic);
      Writers.Finish_Document (Subject, Diagnostic);
      Check (Diagnostic.Code = Errors.No_Error, "extreme-bound text write failed");

      Writers.Reset (Subject, Profile, Diagnostic);
      Writers.Begin_Document (Subject, Diagnostic);
      Writers.Begin_Number (Subject, Diagnostic);
      Writers.Put_Number_Fragment (Subject, High_Empty, Diagnostic);
      Writers.Put_Number_Fragment (Subject, High_Number, Diagnostic);
      Writers.Put_Number_Fragment (Subject, Low_Empty, Diagnostic);
      Writers.Put_Number_Fragment (Subject, Low_Number, Diagnostic);
      Writers.End_Number (Subject, Diagnostic);
      Writers.Finish_Document (Subject, Diagnostic);
      Check (Diagnostic.Code = Errors.No_Error, "extreme-bound number write failed");
   end Test_Extreme_Array_Bounds;

   procedure Test_Escape_Batching is
      Target      : aliased Test_Destination;
      Subject     : Writers.Writer (Target'Access, Maximum_Depth => 0);
      Diagnostic  : Errors.Diagnostic;
      Before      : Natural;
      All_Control : constant Ada.Streams.Stream_Element_Array (-300 .. -173) :=
        [others => 0];
      Mixed       : Ada.Streams.Stream_Element_Array (700 .. 999);
   begin
      Writers.Initialize (Subject, Profile, Diagnostic);
      Writers.Begin_Document (Subject, Diagnostic);
      Writers.Begin_String (Subject, Diagnostic);
      Before := Target.Write_Calls;
      Writers.Put_String_Fragment (Subject, All_Control, Diagnostic);
      Check (Diagnostic.Code = Errors.No_Error, "control-heavy fragment failed");
      Check (Target.Write_Calls - Before = 4, "control-heavy fragment was not batched");
      Writers.End_String (Subject, Diagnostic);
      Writers.Finish_Document (Subject, Diagnostic);
      Check (Target.Staged_Length = 770, "control-heavy output length differs");
      for Item in Count range 0 .. 127 loop
         declare
            First : constant Offset := Target.Storage'First + 1 + Offset (Item * 6);
         begin
            Check
              (Target.Storage (First .. First + 5) = To_Input ("\u0000", First),
               "control-heavy escape output differs");
         end;
      end loop;

      for Position in Mixed'Range loop
         Mixed (Position) :=
           (if (Position - Mixed'First) mod 2 = 0 then Character'Pos ('a') else 0);
      end loop;
      Writers.Reset (Subject, Profile, Diagnostic);
      Writers.Begin_Document (Subject, Diagnostic);
      Writers.Begin_String (Subject, Diagnostic);
      Before := Target.Write_Calls;
      Writers.Put_String_Fragment (Subject, Mixed, Diagnostic);
      Check (Diagnostic.Code = Errors.No_Error, "mixed escape fragment failed");
      Check (Target.Write_Calls - Before = 5, "mixed escape fragment was not batched");
      Writers.End_String (Subject, Diagnostic);
      Writers.Finish_Document (Subject, Diagnostic);
      Check (Target.Staged_Length = 1_052, "mixed escape output length differs");
      for Item in Count range 0 .. 149 loop
         declare
            First : constant Offset := Target.Storage'First + 1 + Offset (Item * 7);
         begin
            Check (Target.Storage (First) = Character'Pos ('a'), "mixed raw output differs");
            Check
              (Target.Storage (First + 1 .. First + 6) = To_Input ("\u0000", First + 1),
               "mixed escape output differs");
         end;
      end loop;
   end Test_Escape_Batching;

   procedure Test_Escape_Batch_Boundaries is
      procedure Run
        (Short_Escapes   : Positive;
         Add_Raw         : Boolean;
         Escape          : Ada.Streams.Stream_Element;
         As_Name         : Boolean;
         First           : Offset;
         Expected_Octets : Count)
      is
         Input : Ada.Streams.Stream_Element_Array
           (First .. First + Offset (Short_Escapes + Boolean'Pos (Add_Raw) - 1));
         Target     : aliased Test_Destination;
         Subject    : Writers.Writer
           (Target'Access, Maximum_Depth => (if As_Name then 1 else 0));
         Diagnostic : Errors.Diagnostic;
         Expected : Ada.Streams.Stream_Element_Array
           (1 .. Offset (Expected_Octets + (if As_Name then 9 else 2)));
         Cursor : Count := 0;

         procedure Add (Item : Ada.Streams.Stream_Element) is
         begin
            Expected (Expected'First + Offset (Cursor)) := Item;
            Cursor := Cursor + 1;
         end Add;
      begin
         for Position in 0 .. Short_Escapes - 1 loop
            Input (First + Offset (Position)) := Escape;
         end loop;
         if Add_Raw then
            Input (Input'Last) := Character'Pos ('a');
         end if;

         Writers.Initialize (Subject, Profile, Diagnostic);
         Writers.Begin_Document (Subject, Diagnostic);
         if As_Name then
            Writers.Begin_Object (Subject, Diagnostic);
            Writers.Begin_Name (Subject, Diagnostic);
            Writers.Put_Name_Fragment (Subject, Input, Diagnostic);
         else
            Writers.Begin_String (Subject, Diagnostic);
            Writers.Put_String_Fragment (Subject, Input, Diagnostic);
         end if;
         Check (Diagnostic.Code = Errors.No_Error, "escape batch boundary fragment failed");
         if As_Name then
            Writers.End_Name (Subject, Diagnostic);
            Writers.Put_Null (Subject, Diagnostic);
            Writers.End_Object (Subject, Diagnostic);
         else
            Writers.End_String (Subject, Diagnostic);
         end if;
         Writers.Finish_Document (Subject, Diagnostic);
         Check (Diagnostic.Code = Errors.No_Error, "escape batch boundary document failed");

         if As_Name then
            Add (Character'Pos ('{'));
         end if;
         Add (Character'Pos ('"'));
         for Position in 1 .. Short_Escapes loop
            Add (Character'Pos ('\'));
            Add ((if Escape = 16#0A# then Character'Pos ('n') else Escape));
         end loop;
         if Add_Raw then
            Add (Character'Pos ('a'));
         end if;
         Add (Character'Pos ('"'));
         if As_Name then
            Add (Character'Pos (':'));
            Add (Character'Pos ('n'));
            Add (Character'Pos ('u'));
            Add (Character'Pos ('l'));
            Add (Character'Pos ('l'));
            Add (Character'Pos ('}'));
         end if;
         Check (Cursor = Expected'Length, "public escape expected output length differs");
         Check (Target.Published, "public escape boundary document did not publish");
         Check (Target.Staged_Length = Expected'Length, "public escape output length differs");
         for Position in Count range 0 .. Expected'Length - 1 loop
            Check
              (Target.Storage (Target.Storage'First + Offset (Position)) =
                 Expected (Expected'First + Offset (Position)),
               "public escape boundary output byte differs");
         end loop;
      end Run;

      Input      : Ada.Streams.Stream_Element_Array (-500 .. -372);
      Target     : aliased Test_Destination;
      Subject    : Writers.Writer (Target'Access, Maximum_Depth => 0);
      Diagnostic : Errors.Diagnostic;
   begin
      Run
        (127, True, Character'Pos ('"'), False, First => -300, Expected_Octets => 255);
      Run
        (128, False, Character'Pos ('\'), False, First => 700, Expected_Octets => 256);
      Run
        (128, True, Character'Pos ('"'), False, First => -500, Expected_Octets => 257);
      Run
        (128, True, Character'Pos ('\'), True, First => 900, Expected_Octets => 257);
      Run
        (128, True, 16#0A#, False, First => -900, Expected_Octets => 257);

      for Position in Input'First .. Input'Last - 1 loop
         Input (Position) := Character'Pos ('"');
      end loop;
      Input (Input'Last) := Character'Pos ('a');
      Target.Capacity := 257;
      Writers.Initialize (Subject, Profile, Diagnostic);
      Writers.Begin_Document (Subject, Diagnostic);
      Writers.Begin_String (Subject, Diagnostic);
      Writers.Put_String_Fragment (Subject, Input, Diagnostic);
      Check
        (Diagnostic.Code = Errors.Destination_Exhausted,
         "public escape batch boundary exhaustion was missed");
      Check
        (Diagnostic.Coordinate = Errors.Staged_Output_Byte and then Diagnostic.Offset = 257,
         "public escape batch boundary exhaustion coordinate differs");
      Check
        (Target.Abort_Calls = 1,
         "public escape batch boundary exhaustion did not abort once");
      Check (not Target.Published, "public escape batch boundary exhaustion published output");
      Check
        (Writers.State (Subject) = Writers.Failed,
         "public escape batch boundary failure state differs");
      Check
        (Writers.Terminal_Diagnostic (Subject) = Diagnostic,
         "public escape batch boundary failure diagnostic was not retained");
   end Test_Escape_Batch_Boundaries;

   procedure Test_Interrupted_Write is
      Target     : aliased Test_Destination;
      Subject    : Writers.Writer (Target'Access, Maximum_Depth => 0);
      Diagnostic : Errors.Diagnostic;
   begin
      Writers.Initialize (Subject, Profile, Diagnostic);
      Writers.Begin_Document (Subject, Diagnostic);
      Writers.Begin_String (Subject, Diagnostic);
      Target.Pause_Write := True;
      Transfer_Gate.Reset;
      declare
         task Worker;

         task body Worker is
            Ignored : Errors.Diagnostic;
         begin
            Writers.Put_String_Fragment (Subject, To_Input ("abcd", -40), Ignored);
         end Worker;
      begin
         Transfer_Gate.Wait;
         abort Worker;
      end;
      Target.Pause_Write := False;

      Check (Writers.State (Subject) = Writers.Interrupted, "interruption state differs");
      Diagnostic := Writers.Terminal_Diagnostic (Subject);
      Check (Diagnostic.Code = Errors.Writer_Interrupted, "interruption primary differs");
      Check (Diagnostic.Coordinate = Errors.JSON_Call_Ordinal, "interruption coordinate differs");
      Check (Diagnostic.Offset = 2, "interruption call ordinal differs");
      Check (Target.Abort_Calls = 0, "interruption performed hidden cleanup");
      Check (not Target.Published, "interruption published output");

      Target.Fail_Abort := True;
      Writers.Abort_Document (Subject, Diagnostic);
      Check (Writers.State (Subject) = Writers.Aborted, "interrupted abort state differs");
      Check (Target.Abort_Calls = 1, "interrupted abort count differs");
      Check (Diagnostic.Code = Errors.Writer_Interrupted, "interrupted abort lost primary");
      Check (Diagnostic.Secondary = Errors.Abort_Failed, "interrupted abort lost secondary");
      Check
        (Diagnostic.Secondary_Coordinate = Errors.No_Coordinate,
         "unknown interrupted prefix gained a coordinate");
      Check (Diagnostic.Secondary_Offset = 0, "unknown interrupted prefix gained an offset");
   end Test_Interrupted_Write;

   procedure Test_Boundary_Task_Transfer is
      Target     : aliased Test_Destination;
      Subject    : Writers.Writer (Target'Access, Maximum_Depth => 0);
      Diagnostic : Errors.Diagnostic;
   begin
      Writers.Initialize (Subject, Profile, Diagnostic);
      Target.Pause_Begin := True;
      Transfer_Gate.Reset;
      declare
         task Worker;

         task body Worker is
            Ignored : Errors.Diagnostic;
         begin
            Writers.Begin_Document (Subject, Ignored);
         end Worker;
      begin
         Transfer_Gate.Wait;
         abort Worker;
      end;
      Target.Pause_Begin := False;
      Check (Target.Begin_Calls = 1, "interrupted begin was repeated");
      Check (Target.Active, "interrupted begin lost transaction ownership");
      Writers.Abort_Document (Subject, Diagnostic);
      Check (Target.Abort_Calls = 1, "interrupted begin cleanup count differs");

      Writers.Reset (Subject, Profile, Diagnostic);
      Writers.Begin_Document (Subject, Diagnostic);
      Writers.Put_Null (Subject, Diagnostic);
      Target.Pause_Commit := True;
      Transfer_Gate.Reset;
      declare
         task Worker;

         task body Worker is
            Ignored : Errors.Diagnostic;
         begin
            Writers.Finish_Document (Subject, Ignored);
         end Worker;
      begin
         Transfer_Gate.Wait;
         abort Worker;
      end;
      Target.Pause_Commit := False;
      Check (Target.Commit_Calls = 1, "interrupted commit was repeated");
      Check (Target.Published, "successful interrupted commit was not authoritative");
      Writers.Abort_Document (Subject, Diagnostic);
      Check (Target.Abort_Calls = 1, "completed commit was subsequently aborted");

      Writers.Reset (Subject, Profile, Diagnostic);
      Writers.Begin_Document (Subject, Diagnostic);
      Target.Pause_Abort := True;
      Transfer_Gate.Reset;
      declare
         task Worker;

         task body Worker is
            Ignored : Errors.Diagnostic;
         begin
            Writers.Abort_Document (Subject, Ignored);
         end Worker;
      begin
         Transfer_Gate.Wait;
         abort Worker;
      end;
      Target.Pause_Abort := False;
      Writers.Abort_Document (Subject, Diagnostic);
      Check (Target.Abort_Calls = 2, "interrupted explicit abort was repeated");
      Check (not Target.Active, "interrupted explicit abort leaked its transaction");
   end Test_Boundary_Task_Transfer;

   procedure Test_Raising_Destination_Contracts is
      Diagnostic : Errors.Diagnostic;
   begin
      declare
         Target : aliased Raising_Destination := (Raise_At => Raise_In_Begin, others => <>);
      begin
         declare
            Subject : Raising_Writers.Writer (Target'Access, Maximum_Depth => 0);
         begin
            Raising_Writers.Initialize (Subject, Profile, Diagnostic);
            Raising_Writers.Begin_Document (Subject, Diagnostic);
            raise Program_Error with "raising begin returned";
         exception
            when Destination_Contract_Error =>
               null;
         end;
         Check (Target.Begin_Calls = 1, "raising begin was repeated");
         Check (Target.Abort_Calls = 0, "raising begin invented transaction ownership");
      end;

      declare
         Target : aliased Raising_Destination := (Raise_At => Raise_In_Write, others => <>);
      begin
         declare
            Subject : Raising_Writers.Writer (Target'Access, Maximum_Depth => 0);
         begin
            Raising_Writers.Initialize (Subject, Profile, Diagnostic);
            Raising_Writers.Begin_Document (Subject, Diagnostic);
            Raising_Writers.Begin_String (Subject, Diagnostic);
            Raising_Writers.Put_String_Fragment (Subject, To_Input ("x", 1), Diagnostic);
            raise Program_Error with "raising write returned";
         exception
            when Destination_Contract_Error =>
               null;
         end;
         Check (Target.Write_Calls = 1, "raising write was repeated");
         Check (Target.Abort_Calls = 1, "raising write was not cleaned once");
         Check (not Target.Published, "raising write published output");
      end;

      declare
         Target : aliased Raising_Destination := (Raise_At => Raise_In_Commit, others => <>);
      begin
         declare
            Subject : Raising_Writers.Writer (Target'Access, Maximum_Depth => 0);
         begin
            Raising_Writers.Initialize (Subject, Profile, Diagnostic);
            Raising_Writers.Begin_Document (Subject, Diagnostic);
            Raising_Writers.Put_Null (Subject, Diagnostic);
            Raising_Writers.Finish_Document (Subject, Diagnostic);
            raise Program_Error with "raising commit returned";
         exception
            when Destination_Contract_Error =>
               null;
         end;
         Check (Target.Commit_Calls = 1, "raising commit was repeated");
         Check (Target.Abort_Calls = 0, "raising commit was unsafely aborted");
         Check (Target.Published, "raising commit uncertainty fixture did not publish");
      end;

      declare
         Target : aliased Raising_Destination := (Raise_At => Raise_In_Abort, others => <>);
      begin
         declare
            Subject : Raising_Writers.Writer (Target'Access, Maximum_Depth => 0);
         begin
            Raising_Writers.Initialize (Subject, Profile, Diagnostic);
            Raising_Writers.Begin_Document (Subject, Diagnostic);
            Raising_Writers.Abort_Document (Subject, Diagnostic);
            raise Program_Error with "raising abort returned";
         exception
            when Destination_Contract_Error =>
               null;
         end;
         Check (Target.Abort_Calls = 1, "raising abort was retried during finalization");
         Check (not Target.Published, "raising abort published output");
      end;

      declare
         Target : aliased Raising_Destination := (Raise_At => Raise_In_Abort, others => <>);
      begin
         declare
            Subject : Raising_Writers.Writer (Target'Access, Maximum_Depth => 0);
         begin
            Raising_Writers.Initialize (Subject, Profile, Diagnostic);
            Raising_Writers.Begin_Document (Subject, Diagnostic);
         end;
         Check (Target.Abort_Calls = 1, "raising finalization abort was repeated");
         Check (not Target.Published, "raising finalization abort published output");
      end;
   end Test_Raising_Destination_Contracts;

begin
   Test_Profile_And_Lifecycle;
   Test_Ordinary_Compact;
   Test_Depth_And_Exhaustion;
   Test_Controlled_Cleanup;
   Test_Extreme_Array_Bounds;
   Test_Escape_Batching;
   Test_Escape_Batch_Boundaries;
   Test_Interrupted_Write;
   Test_Boundary_Task_Transfer;
   Test_Raising_Destination_Contracts;
end Flyology_JSON.Public_Writing_Tests;
