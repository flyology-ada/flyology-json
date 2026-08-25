with Ada.Streams;
with Flyology_JSON.Destinations;
with Flyology_JSON.Errors;
with Flyology_JSON.Writer_Core;

procedure Flyology_JSON.Writer_Core_Tests is

   package Core renames Flyology_JSON.Writer_Core;
   package Destinations renames Flyology_JSON.Destinations;
   package Errors renames Flyology_JSON.Errors;

   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Count;
   use type Destinations.Abort_Status;
   use type Destinations.Begin_Status;
   use type Destinations.Commit_Status;
   use type Destinations.Write_Status;
   use type Core.Byte_Offset;
   use type Errors.Coordinate_Kind;
   use type Errors.Diagnostic;
   use type Errors.Error_Code;
   use type Core.Writer_State;

   subtype Count is Ada.Streams.Stream_Element_Count;
   subtype Offset is Ada.Streams.Stream_Element_Offset;

   --  Fixture storage tests destination boundaries; it is not a writer limit
   --  or public default.
   Fixture_Capacity : constant := 8_192;

   type Transfer_Window is
     (No_Transfer_Window,
      Begin_Transfer_Window,
      Write_Transfer_Window,
      Commit_Transfer_Window,
      Abort_Transfer_Window);

   protected Transfer_Gate is
      procedure Reset;
      procedure Signal (Window : Transfer_Window);
      entry Wait_For_Transfer (Window : out Transfer_Window);
   private
      Current : Transfer_Window := No_Transfer_Window;
   end Transfer_Gate;

   protected body Transfer_Gate is
      procedure Reset is
      begin
         Current := No_Transfer_Window;
      end Reset;

      procedure Signal (Window : Transfer_Window) is
      begin
         Current := Window;
      end Signal;

      entry Wait_For_Transfer (Window : out Transfer_Window)
        when Current /= No_Transfer_Window
      is
      begin
         Window := Current;
      end Wait_For_Transfer;
   end Transfer_Gate;

   type Test_Destination is limited record
      Storage       : Ada.Streams.Stream_Element_Array (101 .. 100 + Fixture_Capacity);
      Capacity      : Count := Fixture_Capacity;
      Staged_Length : Count := 0;
      Staged_High_Water : Count := 0;
      Published     : Boolean := False;
      Active        : Boolean := False;
      Begin_Calls   : Natural := 0;
      Write_Calls   : Natural := 0;
      Commit_Calls  : Natural := 0;
      Abort_Calls   : Natural := 0;
      Fail_Begin    : Boolean := False;
      Fail_Write    : Boolean := False;
      Fail_Commit   : Boolean := False;
      Fail_Abort    : Boolean := False;
      Pause_Begin   : Boolean := False;
      Pause_Write   : Boolean := False;
      Pause_Commit  : Boolean := False;
      Pause_Abort   : Boolean := False;
   end record;

   procedure Destination_Begin
     (Target : in out Test_Destination; Status : out Core.Begin_Status)
   is
   begin
      Target.Begin_Calls := Target.Begin_Calls + 1;
      if Target.Pause_Begin then
         Transfer_Gate.Signal (Begin_Transfer_Window);
         delay 0.05;
      end if;
      if Target.Fail_Begin then
         Status := Destinations.Begin_Failed;
      else
         Target.Active := True;
         Target.Staged_Length := 0;
         Target.Staged_High_Water := 0;
         Status := Destinations.Begin_Succeeded;
      end if;
   end Destination_Begin;

   procedure Destination_Write
     (Target  : in out Test_Destination;
      Data    : Ada.Streams.Stream_Element_Array;
      Written : out Count;
      Status  : out Core.Write_Status)
   is
      Available : constant Count := Target.Capacity - Target.Staged_Length;
   begin
      Target.Write_Calls := Target.Write_Calls + 1;
      if Target.Pause_Write then
         Transfer_Gate.Signal (Write_Transfer_Window);
         delay 0.05;
      end if;
      if Target.Fail_Write then
         Written := 0;
         Status := Destinations.Write_Failed;
         return;
      end if;

      Written := Count'Min (Data'Length, Available);
      if Written > 0 then
         for Position in Count range 0 .. Written - 1 loop
            Target.Storage
              (Target.Storage'First + Offset (Target.Staged_Length) + Offset (Position)) :=
                Data (Data'First + Offset (Position));
         end loop;
      end if;
      Target.Staged_Length := Target.Staged_Length + Written;
      Target.Staged_High_Water := Count'Max (Target.Staged_High_Water, Target.Staged_Length);

      if Written = Data'Length then
         Status := Destinations.Write_Succeeded;
      else
         Status := Destinations.Write_Exhausted;
      end if;
   end Destination_Write;

   procedure Destination_Commit
     (Target : in out Test_Destination; Status : out Core.Commit_Status)
   is
   begin
      Target.Commit_Calls := Target.Commit_Calls + 1;
      if Target.Pause_Commit then
         Transfer_Gate.Signal (Commit_Transfer_Window);
         delay 0.05;
      end if;
      if Target.Fail_Commit then
         Status := Destinations.Commit_Failed;
      else
         Target.Active := False;
         Target.Published := True;
         Status := Destinations.Commit_Succeeded;
      end if;
   end Destination_Commit;

   procedure Destination_Abort
     (Target : in out Test_Destination; Status : out Core.Abort_Status)
   is
   begin
      Target.Abort_Calls := Target.Abort_Calls + 1;
      if Target.Pause_Abort then
         Transfer_Gate.Signal (Abort_Transfer_Window);
         delay 0.05;
      end if;
      Target.Active := False;
      Target.Staged_Length := 0;
      if Target.Fail_Abort then
         Status := Destinations.Abort_Failed;
      else
         Status := Destinations.Abort_Succeeded;
      end if;
   end Destination_Abort;

   package Writers is new Core.Destination_Writers
     (Destination_Type   => Test_Destination,
      Destination_Begin  => Destination_Begin,
      Destination_Write  => Destination_Write,
      Destination_Commit => Destination_Commit,
      Destination_Abort  => Destination_Abort);

   procedure Check (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Check;

   function To_Input
     (Text : String; First : Offset := 1) return Ada.Streams.Stream_Element_Array
   is
      Result : Ada.Streams.Stream_Element_Array (First .. First + Offset (Text'Length) - 1);
   begin
      for Position in 0 .. Text'Length - 1 loop
         Result (First + Offset (Position)) :=
           Ada.Streams.Stream_Element (Character'Pos (Text (Text'First + Position)));
      end loop;
      return Result;
   end To_Input;

   procedure Check_Clear (Item : Core.Diagnostic; Context : String) is
   begin
      Check
        (Item =
           (Errors.No_Error,
            Errors.No_Coordinate,
            0,
            Errors.No_Error,
            Errors.No_Coordinate,
            0),
         Context);
   end Check_Clear;

   procedure Check_Output (Target : Test_Destination; Expected : Ada.Streams.Stream_Element_Array) is
   begin
      Check (Target.Published, "destination did not publish");
      Check (Target.Staged_Length = Expected'Length, "published output length differs");
      for Position in Count range 0 .. Expected'Length - 1 loop
         Check
           (Target.Storage (Target.Storage'First + Offset (Position)) =
              Expected (Expected'First + Offset (Position)),
            "published output byte differs");
      end loop;
   end Check_Output;

   procedure Test_Ordinary_Compact is
      Target     : aliased Test_Destination;
      Writer     : Writers.Writer (Target'Access, Maximum_Depth => 4);
      Diagnostic : Core.Diagnostic;
      UTF8_First : constant Ada.Streams.Stream_Element_Array (31 .. 31) := [31 => 16#C3#];
      UTF8_Last  : constant Ada.Streams.Stream_Element_Array (7 .. 7) := [7 => 16#A9#];
      Escapes    : constant Ada.Streams.Stream_Element_Array (40 .. 44) :=
        [40 => Character'Pos ('x'),
         41 => 16#0A#,
         42 => Character'Pos ('"'),
         43 => Character'Pos ('/'),
         44 => Character'Pos ('\')];
      Expected : constant Ada.Streams.Stream_Element_Array :=
        To_Input
          ("{""s"":""x\n\""/\\" & Character'Val (16#C3#) & Character'Val (16#A9#)
           & """,""n"":-12.3e+4,""b"":[true,null]}",
           First => 77);
   begin
      Writers.Initialize (Writer, Diagnostic);
      Check_Clear (Diagnostic, "initialize failed");
      Writers.Begin_Document (Writer, Diagnostic);
      Writers.Begin_Object (Writer, Diagnostic);
      Writers.Begin_Name (Writer, Diagnostic);
      Writers.Put_Name_Fragment (Writer, To_Input ("s", -19), Diagnostic);
      Writers.End_Name (Writer, Diagnostic);
      Writers.Begin_String (Writer, Diagnostic);
      Writers.Put_String_Fragment (Writer, Escapes, Diagnostic);
      Writers.Put_String_Fragment (Writer, UTF8_First, Diagnostic);
      Writers.Put_String_Fragment (Writer, UTF8_Last, Diagnostic);
      Writers.End_String (Writer, Diagnostic);
      Writers.Begin_Name (Writer, Diagnostic);
      Writers.Put_Name_Fragment (Writer, To_Input ("n", 55), Diagnostic);
      Writers.End_Name (Writer, Diagnostic);
      Writers.Begin_Number (Writer, Diagnostic);
      Writers.Put_Number_Fragment (Writer, To_Input ("-12.", -23), Diagnostic);
      Writers.Put_Number_Fragment (Writer, To_Input ("3e+4", 91), Diagnostic);
      Writers.End_Number (Writer, Diagnostic);
      Writers.Begin_Name (Writer, Diagnostic);
      Writers.Put_Name_Fragment (Writer, To_Input ("b", 71), Diagnostic);
      Writers.End_Name (Writer, Diagnostic);
      Writers.Begin_Array (Writer, Diagnostic);
      Writers.Put_Boolean (Writer, True, Diagnostic);
      Writers.Put_Null (Writer, Diagnostic);
      Writers.End_Array (Writer, Diagnostic);
      Writers.End_Object (Writer, Diagnostic);
      Writers.Finish_Document (Writer, Diagnostic);

      Check_Clear (Diagnostic, "ordinary compact document failed");
      Check (Writers.State (Writer) = Core.Completed, "writer did not complete");
      Check (Target.Abort_Calls = 0, "successful document aborted");
      Check_Output (Target, Expected);
   end Test_Ordinary_Compact;

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
         Writer     : Writers.Writer
           (Target'Access, Maximum_Depth => (if As_Name then 1 else 0));
         Diagnostic : Core.Diagnostic;
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

         Writers.Initialize (Writer, Diagnostic);
         Writers.Begin_Document (Writer, Diagnostic);
         if As_Name then
            Writers.Begin_Object (Writer, Diagnostic);
            Writers.Begin_Name (Writer, Diagnostic);
            Writers.Put_Name_Fragment (Writer, Input, Diagnostic);
         else
            Writers.Begin_String (Writer, Diagnostic);
            Writers.Put_String_Fragment (Writer, Input, Diagnostic);
         end if;
         Check_Clear (Diagnostic, "escape batch boundary fragment failed");
         if As_Name then
            Writers.End_Name (Writer, Diagnostic);
            Writers.Put_Null (Writer, Diagnostic);
            Writers.End_Object (Writer, Diagnostic);
         else
            Writers.End_String (Writer, Diagnostic);
         end if;
         Writers.Finish_Document (Writer, Diagnostic);
         Check_Clear (Diagnostic, "escape batch boundary document failed");

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
         Check (Cursor = Expected'Length, "escape batch expected output length differs");
         Check_Output (Target, Expected);
      end Run;

      Input      : Ada.Streams.Stream_Element_Array (-500 .. -372);
      Target     : aliased Test_Destination;
      Writer     : Writers.Writer (Target'Access, Maximum_Depth => 0);
      Diagnostic : Core.Diagnostic;
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
      Writers.Initialize (Writer, Diagnostic);
      Writers.Begin_Document (Writer, Diagnostic);
      Writers.Begin_String (Writer, Diagnostic);
      Writers.Put_String_Fragment (Writer, Input, Diagnostic);
      Check
        (Diagnostic.Code = Errors.Destination_Exhausted,
         "escape batch boundary exhaustion was missed");
      Check
        (Diagnostic.Coordinate = Errors.Staged_Output_Byte and then Diagnostic.Offset = 257,
         "escape batch boundary exhaustion coordinate differs");
      Check (Target.Abort_Calls = 1, "escape batch boundary exhaustion did not abort once");
      Check (not Target.Published, "escape batch boundary exhaustion published output");
      Check (Writers.State (Writer) = Core.Failed, "escape batch boundary failure state differs");
      Check
        (Writers.Terminal_Diagnostic (Writer) = Diagnostic,
         "escape batch boundary failure diagnostic was not retained");
   end Test_Escape_Batch_Boundaries;

   procedure Test_Depth_And_Grammar is
      Target     : aliased Test_Destination;
      Writer     : Writers.Writer (Target'Access, Maximum_Depth => 1);
      Diagnostic : Core.Diagnostic;
   begin
      Writers.Initialize (Writer, Diagnostic);
      Writers.Begin_Document (Writer, Diagnostic);
      Writers.Begin_Array (Writer, Diagnostic);
      Writers.Begin_Array (Writer, Diagnostic);
      Check (Diagnostic.Code = Errors.Depth_Exhausted, "depth denial code differs");
      Check (Diagnostic.Coordinate = Errors.JSON_Call_Ordinal, "depth denial coordinate differs");
      Check (Diagnostic.Offset = 2, "depth denial ordinal differs");
      Check (Target.Abort_Calls = 1, "depth failure did not abort exactly once");
      Writers.Abort_Document (Writer, Diagnostic);
      Check (Target.Abort_Calls = 1, "failed writer aborted twice");
   end Test_Depth_And_Grammar;

   procedure Test_Invalid_UTF8_And_Number is
      Target     : aliased Test_Destination;
      Writer     : Writers.Writer (Target'Access, Maximum_Depth => 1);
      Diagnostic : Core.Diagnostic;
      Lead       : constant Ada.Streams.Stream_Element_Array (5 .. 5) := [5 => 16#E0#];
      Invalid    : constant Ada.Streams.Stream_Element_Array (9 .. 9) := [9 => 16#80#];
   begin
      Writers.Initialize (Writer, Diagnostic);
      Writers.Begin_Document (Writer, Diagnostic);
      Writers.Begin_String (Writer, Diagnostic);
      Writers.Put_String_Fragment (Writer, Lead, Diagnostic);
      Writers.Put_String_Fragment (Writer, Invalid, Diagnostic);
      Check (Diagnostic.Code = Errors.Invalid_UTF8, "invalid UTF-8 code differs");
      Check (Diagnostic.Coordinate = Errors.Writer_Token_Byte, "invalid UTF-8 coordinate differs");
      Check (Diagnostic.Offset = 0, "overlong UTF-8 did not blame its lead");
      Check (Target.Abort_Calls = 1, "invalid UTF-8 did not abort once");

      Writers.Reset (Writer, Diagnostic);
      Writers.Begin_Document (Writer, Diagnostic);
      Writers.Begin_Number (Writer, Diagnostic);
      Writers.Put_Number_Fragment (Writer, To_Input ("1e", 88), Diagnostic);
      Writers.End_Number (Writer, Diagnostic);
      Check (Diagnostic.Code = Errors.Invalid_Number, "truncated number code differs");
      Check (Diagnostic.Coordinate = Errors.Writer_Token_Byte, "truncated number coordinate differs");
      Check (Diagnostic.Offset = 2, "truncated number offset differs");
      Check (Target.Abort_Calls = 2, "truncated number did not abort once");

      Writers.Reset (Writer, Diagnostic);
      Writers.Begin_Document (Writer, Diagnostic);
      Writers.Begin_Number (Writer, Diagnostic);
      Writers.Put_Number_Fragment (Writer, To_Input ("01", 111), Diagnostic);
      Check (Diagnostic.Code = Errors.Invalid_Number, "invalid number transition code differs");
      Check (Diagnostic.Offset = 1, "invalid number offset differs");
      Check (Target.Abort_Calls = 3, "invalid number transition did not abort once");
   end Test_Invalid_UTF8_And_Number;

   procedure Test_Destination_Failures is
      Target     : aliased Test_Destination;
      Writer     : Writers.Writer (Target'Access, Maximum_Depth => 1);
      Diagnostic : Core.Diagnostic;
   begin
      Target.Capacity := 3;
      Writers.Initialize (Writer, Diagnostic);
      Writers.Begin_Document (Writer, Diagnostic);
      Writers.Begin_String (Writer, Diagnostic);
      Writers.Put_String_Fragment (Writer, To_Input ("abcd", 40), Diagnostic);
      Check (Diagnostic.Code = Errors.Destination_Exhausted, "destination exhaustion code differs");
      Check (Diagnostic.Coordinate = Errors.Staged_Output_Byte, "destination exhaustion coordinate differs");
      Check (Diagnostic.Offset = 3, "destination exhaustion offset differs");
      Check (Target.Abort_Calls = 1, "destination exhaustion did not abort once");
      Check (not Target.Published, "destination exhaustion published output");

      Target.Capacity := Fixture_Capacity;
      Target.Fail_Commit := True;
      Target.Fail_Abort := True;
      Writers.Reset (Writer, Diagnostic);
      Writers.Begin_Document (Writer, Diagnostic);
      Writers.Put_Null (Writer, Diagnostic);
      Writers.Finish_Document (Writer, Diagnostic);
      Check (Diagnostic.Code = Errors.Commit_Failed, "commit failure lost primary code");
      Check (Diagnostic.Secondary = Errors.Abort_Failed, "abort failure was not secondary");
      Check (Target.Abort_Calls = 2, "commit failure cleanup count differs");
      Check (not Target.Published, "commit failure published output");

      Target.Fail_Commit := False;
      Target.Fail_Abort := False;
      Target.Fail_Write := True;
      Writers.Reset (Writer, Diagnostic);
      Writers.Begin_Document (Writer, Diagnostic);
      Writers.Put_Null (Writer, Diagnostic);
      Check (Diagnostic.Code = Errors.Destination_Failed, "destination write failure code differs");
      Check (Diagnostic.Coordinate = Errors.Staged_Output_Byte, "write failure coordinate differs");
      Check (Diagnostic.Offset = 0, "write failure offset differs");
      Check (Target.Abort_Calls = 3, "write failure did not abort once");
   end Test_Destination_Failures;

   procedure Test_Grammar_And_Truncation is
      Target     : aliased Test_Destination;
      Writer     : Writers.Writer (Target'Access, Maximum_Depth => 1);
      Diagnostic : Core.Diagnostic;
      Lead       : constant Ada.Streams.Stream_Element_Array (13 .. 13) := [13 => 16#C3#];
   begin
      Writers.Initialize (Writer, Diagnostic);
      Writers.Begin_Document (Writer, Diagnostic);
      Writers.Begin_Object (Writer, Diagnostic);
      Writers.Put_Null (Writer, Diagnostic);
      Check (Diagnostic.Code = Errors.Invalid_Writer_Grammar, "object grammar failure code differs");
      Check (Diagnostic.Coordinate = Errors.JSON_Call_Ordinal, "object grammar coordinate differs");
      Check (Diagnostic.Offset = 2, "object grammar ordinal differs");
      Check (Target.Abort_Calls = 1, "object grammar failure did not abort once");

      Writers.Reset (Writer, Diagnostic);
      Writers.Begin_Document (Writer, Diagnostic);
      Writers.Begin_String (Writer, Diagnostic);
      Writers.Put_String_Fragment (Writer, Lead, Diagnostic);
      Writers.End_String (Writer, Diagnostic);
      Check (Diagnostic.Code = Errors.Invalid_UTF8, "truncated UTF-8 code differs");
      Check (Diagnostic.Offset = 1, "truncated UTF-8 missing-byte offset differs");
      Check (Target.Abort_Calls = 2, "truncated UTF-8 did not abort once");
   end Test_Grammar_And_Truncation;

   procedure Test_Offset_Boundaries is
      Target     : aliased Test_Destination;
      Writer     : Writers.Writer (Target'Access, Maximum_Depth => 0);
      Diagnostic : Core.Diagnostic;
      Last       : constant Core.Byte_Offset := Core.Byte_Offset'Last;
   begin
      Writers.Initialize (Writer, Diagnostic);
      Writers.Begin_Document (Writer, Diagnostic);
      Writers.Begin_Number (Writer, Diagnostic);
      Writers.Set_Offsets_For_Test (Writer, Next_Staged => Last - 2, Next_Token => 0);
      Writers.Put_Number_Fragment (Writer, To_Input ("123", -7), Diagnostic);
      Check (Diagnostic.Code = Errors.Offset_Exhausted, "staged offset boundary code differs");
      Check (Diagnostic.Coordinate = Errors.Staged_Output_Byte, "staged boundary coordinate differs");
      Check (Diagnostic.Offset = Last, "staged boundary did not report the last coordinate");
      Check (Target.Staged_High_Water = 2, "representable staged prefix was not accepted");
      Check (Target.Abort_Calls = 1, "staged boundary did not abort exactly once");
      Check (not Target.Published, "staged boundary published output");

      Writers.Reset (Writer, Diagnostic);
      Target.Capacity := 1;
      Writers.Begin_Document (Writer, Diagnostic);
      Writers.Begin_Number (Writer, Diagnostic);
      Writers.Set_Offsets_For_Test (Writer, Next_Staged => Last - 2, Next_Token => 0);
      Writers.Put_Number_Fragment (Writer, To_Input ("123", 17), Diagnostic);
      Check
        (Diagnostic.Code = Errors.Destination_Exhausted,
         "destination exhaustion did not precede staged boundary");
      Check (Diagnostic.Offset = Last - 1, "near-boundary destination offset differs");
      Check (Target.Staged_High_Water = 1, "near-boundary destination prefix differs");
      Check (Target.Abort_Calls = 2, "near-boundary exhaustion abort count differs");

      Writers.Reset (Writer, Diagnostic);
      Target.Capacity := Fixture_Capacity;
      Target.Fail_Write := True;
      Writers.Begin_Document (Writer, Diagnostic);
      Writers.Begin_Number (Writer, Diagnostic);
      Writers.Set_Offsets_For_Test (Writer, Next_Staged => Last - 2, Next_Token => 0);
      Writers.Put_Number_Fragment (Writer, To_Input ("123", 61), Diagnostic);
      Check
        (Diagnostic.Code = Errors.Destination_Failed,
         "destination error did not precede staged boundary");
      Check (Diagnostic.Offset = Last - 2, "near-boundary destination failure offset differs");
      Check (Target.Staged_High_Water = 0, "failed destination accepted a prefix");
      Check (Target.Abort_Calls = 3, "near-boundary destination failure abort count differs");

      Writers.Reset (Writer, Diagnostic);
      Target.Fail_Write := False;
      Writers.Begin_Document (Writer, Diagnostic);
      Writers.Begin_Number (Writer, Diagnostic);
      Writers.Set_Offsets_For_Test (Writer, Next_Staged => 0, Next_Token => Last - 2);
      Writers.Put_Number_Fragment (Writer, To_Input ("123", 5), Diagnostic);
      Check (Diagnostic.Code = Errors.Offset_Exhausted, "token offset boundary code differs");
      Check (Diagnostic.Coordinate = Errors.Writer_Token_Byte, "token boundary coordinate differs");
      Check (Diagnostic.Offset = Last, "token boundary did not report the last coordinate");
      Check (Target.Staged_High_Water = 2, "token boundary omitted its valid output prefix");
      Check (Target.Abort_Calls = 4, "token boundary did not abort exactly once");

      Writers.Reset (Writer, Diagnostic);
      Target.Capacity := 1;
      Writers.Begin_Document (Writer, Diagnostic);
      Writers.Begin_Number (Writer, Diagnostic);
      Writers.Set_Offsets_For_Test (Writer, Next_Staged => 0, Next_Token => Last - 2);
      Writers.Put_Number_Fragment (Writer, To_Input ("123", -29), Diagnostic);
      Check
        (Diagnostic.Code = Errors.Destination_Exhausted,
         "destination exhaustion did not precede token boundary");
      Check (Diagnostic.Offset = 1, "token-boundary destination offset differs");
      Check (Target.Staged_High_Water = 1, "token-boundary destination prefix differs");
      Check (Target.Abort_Calls = 5, "token-boundary destination abort count differs");
   end Test_Offset_Boundaries;

   procedure Test_Ordered_Failure_Precedence is

      type Observation is record
         Diagnostic : Core.Diagnostic;
         Accepted   : Count;
         Aborts     : Natural;
         Published  : Boolean;
      end record;

      procedure Run_Text
        (Schedule        : Natural;
         Prefix_Capacity : Count;
         Fail_Write      : Boolean;
         Seen            : out Observation)
      is
         Target     : aliased Test_Destination;
         Writer     : Writers.Writer (Target'Access, Maximum_Depth => 0);
         Diagnostic : Core.Diagnostic;
         Base       : Count;
         Whole      : constant Ada.Streams.Stream_Element_Array (31 .. 33) :=
           [31 => Character'Pos ('a'), 32 => Character'Pos ('b'), 33 => 16#FF#];
         Tail       : constant Ada.Streams.Stream_Element_Array (21 .. 22) :=
           [21 => Character'Pos ('b'), 22 => 16#FF#];
         Invalid    : constant Ada.Streams.Stream_Element_Array (-3 .. -3) := [-3 => 16#FF#];
      begin
         Writers.Initialize (Writer, Diagnostic);
         Writers.Begin_Document (Writer, Diagnostic);
         Writers.Begin_String (Writer, Diagnostic);
         Base := Target.Staged_Length;
         Target.Capacity := Base + Prefix_Capacity;
         Target.Fail_Write := Fail_Write;

         case Schedule is
            when 0 =>
               Writers.Put_String_Fragment (Writer, Whole, Diagnostic);
            when 1 =>
               Writers.Put_String_Fragment (Writer, To_Input ("a", -11), Diagnostic);
               if Writers.State (Writer) = Core.Active then
                  Writers.Put_String_Fragment (Writer, Tail, Diagnostic);
               end if;
            when 2 =>
               Writers.Put_String_Fragment (Writer, To_Input ("ab", -11), Diagnostic);
               if Writers.State (Writer) = Core.Active then
                  Writers.Put_String_Fragment (Writer, Invalid, Diagnostic);
               end if;
            when 3 =>
               Writers.Put_String_Fragment (Writer, To_Input ("a", -11), Diagnostic);
               if Writers.State (Writer) = Core.Active then
                  Writers.Put_String_Fragment (Writer, To_Input ("b", 49), Diagnostic);
               end if;
               if Writers.State (Writer) = Core.Active then
                  Writers.Put_String_Fragment (Writer, Invalid, Diagnostic);
               end if;
            when others =>
               raise Program_Error with "unknown text test schedule";
         end case;

         Seen :=
           (Diagnostic => Diagnostic,
            Accepted   => Target.Staged_High_Water - Base,
            Aborts     => Target.Abort_Calls,
            Published  => Target.Published);
      end Run_Text;

      procedure Run_Number
        (Schedule        : Natural;
         Prefix_Capacity : Count;
         Fail_Write      : Boolean;
         Seen            : out Observation)
      is
         Target     : aliased Test_Destination;
         Writer     : Writers.Writer (Target'Access, Maximum_Depth => 0);
         Diagnostic : Core.Diagnostic;
         Base       : Count;
      begin
         Writers.Initialize (Writer, Diagnostic);
         Writers.Begin_Document (Writer, Diagnostic);
         Writers.Begin_Number (Writer, Diagnostic);
         Base := Target.Staged_Length;
         Target.Capacity := Base + Prefix_Capacity;
         Target.Fail_Write := Fail_Write;

         case Schedule is
            when 0 =>
               Writers.Put_Number_Fragment (Writer, To_Input ("12x", 9), Diagnostic);
            when 1 =>
               Writers.Put_Number_Fragment (Writer, To_Input ("1", 71), Diagnostic);
               if Writers.State (Writer) = Core.Active then
                  Writers.Put_Number_Fragment (Writer, To_Input ("2x", -41), Diagnostic);
               end if;
            when 2 =>
               Writers.Put_Number_Fragment (Writer, To_Input ("12", 71), Diagnostic);
               if Writers.State (Writer) = Core.Active then
                  Writers.Put_Number_Fragment (Writer, To_Input ("x", -41), Diagnostic);
               end if;
            when 3 =>
               Writers.Put_Number_Fragment (Writer, To_Input ("1", 71), Diagnostic);
               if Writers.State (Writer) = Core.Active then
                  Writers.Put_Number_Fragment (Writer, To_Input ("2", 13), Diagnostic);
               end if;
               if Writers.State (Writer) = Core.Active then
                  Writers.Put_Number_Fragment (Writer, To_Input ("x", -41), Diagnostic);
               end if;
            when others =>
               raise Program_Error with "unknown number test schedule";
         end case;

         Seen :=
           (Diagnostic => Diagnostic,
            Accepted   => Target.Staged_High_Water - Base,
            Aborts     => Target.Abort_Calls,
            Published  => Target.Published);
      end Run_Number;

      Single : Observation;
      Partitioned : Observation;
   begin
      for Fail_Write in Boolean loop
         for Capacity in Count range 0 .. 2 loop
            Run_Text (0, Capacity, Fail_Write, Single);
            for Schedule in 1 .. 3 loop
               Run_Text (Schedule, Capacity, Fail_Write, Partitioned);
               Check
                 (Single = Partitioned,
                  "text failure precedence changed across fragment schedules");
            end loop;
            Check (Single.Aborts = 1, "text failure did not abort exactly once");
            Check (not Single.Published, "text failure published output");
            if Fail_Write then
               Check (Single.Diagnostic.Code = Errors.Destination_Failed, "text write error lost precedence");
               Check (Single.Accepted = 0, "failed text write accepted an output prefix");
            elsif Capacity < 2 then
               Check
                 (Single.Diagnostic.Code = Errors.Destination_Exhausted,
                  "text capacity denial lost precedence");
               Check (Single.Accepted = Capacity, "text capacity denial accepted the wrong prefix");
            else
               Check (Single.Diagnostic.Code = Errors.Invalid_UTF8, "later malformed UTF-8 was missed");
               Check (Single.Diagnostic.Offset = 2, "later malformed UTF-8 offset differs");
            end if;

            Run_Number (0, Capacity, Fail_Write, Single);
            for Schedule in 1 .. 3 loop
               Run_Number (Schedule, Capacity, Fail_Write, Partitioned);
               Check
                 (Single = Partitioned,
                  "number failure precedence changed across fragment schedules");
            end loop;
            Check (Single.Aborts = 1, "number failure did not abort exactly once");
            Check (not Single.Published, "number failure published output");

            if Fail_Write then
               Check (Single.Diagnostic.Code = Errors.Destination_Failed, "write error lost precedence");
               Check (Single.Accepted = 0, "failed write accepted an output prefix");
            elsif Capacity < 2 then
               Check
                 (Single.Diagnostic.Code = Errors.Destination_Exhausted,
                  "capacity denial lost precedence");
               Check (Single.Accepted = Capacity, "capacity denial accepted the wrong prefix");
            else
               Check (Single.Diagnostic.Code = Errors.Invalid_Number, "later malformed number was missed");
               Check (Single.Diagnostic.Offset = 2, "later malformed number offset differs");
            end if;
         end loop;
      end loop;
   end Test_Ordered_Failure_Precedence;

   procedure Test_Begin_Abort_Cleanup is
      Target     : aliased Test_Destination;
      Diagnostic : Core.Diagnostic;
   begin
      Target.Fail_Begin := True;
      declare
         Writer : Writers.Writer (Target'Access, Maximum_Depth => 0);
      begin
         Writers.Initialize (Writer, Diagnostic);
         Writers.Begin_Document (Writer, Diagnostic);
         Check (Diagnostic.Code = Errors.Destination_Failed, "begin failure code differs");
         Writers.Cleanup (Writer);
      end;
      Check (Target.Abort_Calls = 0, "failed begin incorrectly aborted");

      Target.Fail_Begin := False;
      declare
         Writer : Writers.Writer (Target'Access, Maximum_Depth => 0);
      begin
         Writers.Initialize (Writer, Diagnostic);
         Writers.Begin_Document (Writer, Diagnostic);
         Writers.Cleanup (Writer);
      end;
      Check (Target.Abort_Calls = 1, "explicit cleanup did not abort owned transaction");

      declare
         Writer : Writers.Writer (Target'Access, Maximum_Depth => 0);
      begin
         Writers.Initialize (Writer, Diagnostic);
         Writers.Begin_Document (Writer, Diagnostic);
         Writers.Abort_Document (Writer, Diagnostic);
         Writers.Abort_Document (Writer, Diagnostic);
         Writers.Cleanup (Writer);
      end;
      Check (Target.Abort_Calls = 2, "explicit abort was not exactly once");
   end Test_Begin_Abort_Cleanup;

   procedure Test_Task_Abort_Transfers is
      Target     : aliased Test_Destination;
      Writer     : Writers.Writer (Target'Access, Maximum_Depth => 0);
      Diagnostic : Core.Diagnostic;
      Seen       : Transfer_Window;
      Before     : Natural;
   begin
      Writers.Initialize (Writer, Diagnostic);

      --  An abort before the destination call has no ownership effect.
      declare
         task Worker;

         task body Worker is
            Ignored : Core.Diagnostic;
         begin
            delay 0.05;
            Writers.Begin_Document (Writer, Ignored);
         end Worker;
      begin
         abort Worker;
      end;
      Check (Writers.State (Writer) = Core.Ready, "pre-call task abort changed writer state");
      Check (Target.Begin_Calls = 0, "pre-call task abort reached the destination");

      --  The abort request is pending while Begin is inside its formal and at
      --  its return edge. The controlled Initialize must finish ownership
      --  transfer before the worker can terminate.
      Transfer_Gate.Reset;
      Target.Pause_Begin := True;
      declare
         task Worker;

         task body Worker is
            Ignored : Core.Diagnostic;
         begin
            Writers.Begin_Document (Writer, Ignored);
         end Worker;
      begin
         Transfer_Gate.Wait_For_Transfer (Seen);
         Check (Seen = Begin_Transfer_Window, "begin abort window signal differs");
         abort Worker;
      end;
      Target.Pause_Begin := False;
      Check (Writers.State (Writer) = Core.Active, "task-aborted begin lost coherent ownership");
      Check (Target.Active, "task-aborted begin lost its abortable transaction");
      Check (Target.Begin_Calls = 1, "aborted begin call count differs");
      Check (Target.Abort_Calls = 0, "task-aborted begin cleaned up before owner request");
      Writers.Abort_Document (Writer, Diagnostic);
      Check (Writers.State (Writer) = Core.Aborted, "task-aborted begin did not abort explicitly");
      Check (Target.Abort_Calls = 1, "task-aborted begin did not clean up exactly once");
      Check_Clear (Writers.Terminal_Diagnostic (Writer), "clean boundary abort retained an error");

      --  A failed begin records failure without inventing ownership or an
      --  abort obligation when task abort is pending at the return edge.
      Writers.Reset (Writer, Diagnostic);
      Transfer_Gate.Reset;
      Target.Pause_Begin := True;
      Target.Fail_Begin := True;
      Before := Target.Abort_Calls;
      declare
         task Worker;

         task body Worker is
            Ignored : Core.Diagnostic;
         begin
            Writers.Begin_Document (Writer, Ignored);
         end Worker;
      begin
         Transfer_Gate.Wait_For_Transfer (Seen);
         abort Worker;
      end;
      Target.Pause_Begin := False;
      Target.Fail_Begin := False;
      Check (Writers.State (Writer) = Core.Failed, "aborted failed begin lost its failure state");
      Check (not Target.Active, "aborted failed begin invented destination ownership");
      Check (Target.Abort_Calls = Before, "aborted failed begin incorrectly called abort");
      Check
        (Writers.Terminal_Diagnostic (Writer).Code = Errors.Destination_Failed,
         "aborted failed begin lost its primary diagnostic");
      Writers.Abort_Document (Writer, Diagnostic);
      Check (Writers.State (Writer) = Core.Failed, "failed begin abort changed retained state");

      --  A successful commit publishes and records Completed before the
      --  pending task abort can take effect.
      Writers.Reset (Writer, Diagnostic);
      Target.Published := False;
      Writers.Begin_Document (Writer, Diagnostic);
      Writers.Put_Null (Writer, Diagnostic);
      Transfer_Gate.Reset;
      Target.Pause_Commit := True;
      declare
         task Worker;

         task body Worker is
            Ignored : Core.Diagnostic;
         begin
            Writers.Finish_Document (Writer, Ignored);
         end Worker;
      begin
         Transfer_Gate.Wait_For_Transfer (Seen);
         Check (Seen = Commit_Transfer_Window, "commit abort window signal differs");
         abort Worker;
      end;
      Target.Pause_Commit := False;
      Check (Writers.State (Writer) = Core.Completed, "aborted successful commit was not completed");
      Check (Target.Published, "aborted successful commit lost publication");
      Check (Target.Commit_Calls = 1, "successful commit call count differs");
      Check (Target.Abort_Calls = 1, "successful commit was incorrectly aborted");

      --  A failed commit and its required abort are one outer deferred
      --  transfer; the pending task abort cannot strand the transaction.
      Writers.Reset (Writer, Diagnostic);
      Target.Published := False;
      Target.Fail_Commit := True;
      Writers.Begin_Document (Writer, Diagnostic);
      Writers.Put_Null (Writer, Diagnostic);
      Transfer_Gate.Reset;
      Target.Pause_Commit := True;
      Before := Target.Abort_Calls;
      declare
         task Worker;

         task body Worker is
            Ignored : Core.Diagnostic;
         begin
            Writers.Finish_Document (Writer, Ignored);
         end Worker;
      begin
         Transfer_Gate.Wait_For_Transfer (Seen);
         abort Worker;
      end;
      Target.Pause_Commit := False;
      Target.Fail_Commit := False;
      Check (Writers.State (Writer) = Core.Failed, "aborted failed commit lost its failure state");
      Check (Target.Abort_Calls = Before + 1, "aborted failed commit did not clean up exactly once");
      Check (not Target.Active, "aborted failed commit leaked destination ownership");
      Check (not Target.Published, "aborted failed commit falsely published");
      Check
        (Writers.Terminal_Diagnostic (Writer).Code = Errors.Commit_Failed,
         "aborted failed commit lost its primary diagnostic");

      --  Explicit abort reaches Aborted in the same deferred region that ends
      --  destination ownership.
      Writers.Reset (Writer, Diagnostic);
      Writers.Begin_Document (Writer, Diagnostic);
      Transfer_Gate.Reset;
      Target.Pause_Abort := True;
      Before := Target.Abort_Calls;
      declare
         task Worker;

         task body Worker is
            Ignored : Core.Diagnostic;
         begin
            Writers.Abort_Document (Writer, Ignored);
         end Worker;
      begin
         Transfer_Gate.Wait_For_Transfer (Seen);
         Check (Seen = Abort_Transfer_Window, "abort window signal differs");
         abort Worker;
      end;
      Target.Pause_Abort := False;
      Check (Writers.State (Writer) = Core.Aborted, "task-aborted explicit abort left an active state");
      Check (Target.Abort_Calls = Before + 1, "task-aborted explicit abort was not exactly once");
      Check (not Target.Active, "task-aborted explicit abort leaked ownership");
      Check (not Target.Published, "task-aborted explicit abort published output");

      --  Abort failure still ends ownership and retains its diagnostic before
      --  the pending task abort is delivered.
      Writers.Reset (Writer, Diagnostic);
      Writers.Begin_Document (Writer, Diagnostic);
      Transfer_Gate.Reset;
      Target.Pause_Abort := True;
      Target.Fail_Abort := True;
      Before := Target.Abort_Calls;
      declare
         task Worker;

         task body Worker is
            Ignored : Core.Diagnostic;
         begin
            Writers.Abort_Document (Writer, Ignored);
         end Worker;
      begin
         Transfer_Gate.Wait_For_Transfer (Seen);
         abort Worker;
      end;
      Target.Pause_Abort := False;
      Target.Fail_Abort := False;
      Check (Writers.State (Writer) = Core.Aborted, "failed abort did not reach Aborted");
      Check (Target.Abort_Calls = Before + 1, "failed abort was not exactly once");
      Check (not Target.Active, "failed abort leaked destination ownership");
      Check
        (Writers.Terminal_Diagnostic (Writer).Code = Errors.Abort_Failed,
         "failed abort lost its diagnostic under task abort");
   end Test_Task_Abort_Transfers;

   procedure Test_Task_Abort_Mutating_Calls is
      subtype Large_Index is Offset range -2_047 .. 2_048;
      Large_Text   : constant Ada.Streams.Stream_Element_Array (Large_Index) :=
        [others => Character'Pos ('a')];
      Large_Number : Ada.Streams.Stream_Element_Array (Large_Index) :=
        [others => Character'Pos ('2')];

      procedure Check_Sealed
        (Writer : in out Writers.Writer;
         Target : Test_Destination;
         Before : Natural;
         Context : String)
      is
         Diagnostic  : Core.Diagnostic;
         Write_Calls : Natural;
      begin
         Check (Writers.State (Writer) = Core.Interrupted, Context & " did not expose Interrupted");
         Check (Target.Abort_Calls = Before, Context & " aborted before the owner requested cleanup");
         Check
           (Writers.Terminal_Diagnostic (Writer).Code = Errors.Writer_Interrupted,
            Context & " did not synthesize the interruption primary");
         Check
           (Writers.Terminal_Diagnostic (Writer).Coordinate = Errors.JSON_Call_Ordinal,
            Context & " interruption coordinate differs");
         Writers.Abort_Document (Writer, Diagnostic);
         Check (Writers.State (Writer) = Core.Aborted, Context & " did not reach Aborted");
         Check (Target.Abort_Calls = Before + 1, Context & " did not abort exactly once");
         Check (not Target.Active, Context & " leaked destination ownership");
         Check (not Target.Published, Context & " published output");
         Check
           (Writers.Terminal_Diagnostic (Writer).Code = Errors.Writer_Interrupted,
            Context & " did not retain the interruption primary");
         Write_Calls := Target.Write_Calls;
         Writers.Put_Null (Writer, Diagnostic);
         Check (Writers.State (Writer) = Core.Aborted, Context & " allowed continuation");
         Check (Target.Write_Calls = Write_Calls, Context & " continuation wrote output");
         Check (Target.Abort_Calls = Before + 1, Context & " continuation aborted twice");
      end Check_Sealed;
   begin
      Large_Number (Large_Number'First) := Character'Pos ('1');

      --  Structural write.
      declare
         Target     : aliased Test_Destination;
         Writer     : Writers.Writer (Target'Access, Maximum_Depth => 1);
         Diagnostic : Core.Diagnostic;
         Seen       : Transfer_Window;
         Before     : Natural;
      begin
         Writers.Initialize (Writer, Diagnostic);
         Writers.Begin_Document (Writer, Diagnostic);
         Target.Pause_Write := True;
         Transfer_Gate.Reset;
         Before := Target.Abort_Calls;
         declare
            task Worker;

            task body Worker is
               Ignored : Core.Diagnostic;
            begin
               Writers.Begin_Object (Writer, Ignored);
            end Worker;
         begin
            Transfer_Gate.Wait_For_Transfer (Seen);
            abort Worker;
         end;
         Target.Pause_Write := False;
         Check (Seen = Write_Transfer_Window, "structural write window signal differs");
         Check_Sealed (Writer, Target, Before, "task-aborted structural call");
      end;

      --  Bulk decoded name fragment.
      declare
         Target     : aliased Test_Destination;
         Writer     : Writers.Writer (Target'Access, Maximum_Depth => 1);
         Diagnostic : Core.Diagnostic;
         Seen       : Transfer_Window;
         Before     : Natural;
      begin
         Writers.Initialize (Writer, Diagnostic);
         Writers.Begin_Document (Writer, Diagnostic);
         Writers.Begin_Object (Writer, Diagnostic);
         Writers.Begin_Name (Writer, Diagnostic);
         Target.Pause_Write := True;
         Transfer_Gate.Reset;
         Before := Target.Abort_Calls;
         declare
            task Worker;

            task body Worker is
               Ignored : Core.Diagnostic;
            begin
               Writers.Put_Name_Fragment (Writer, Large_Text, Ignored);
            end Worker;
         begin
            Transfer_Gate.Wait_For_Transfer (Seen);
            abort Worker;
         end;
         Target.Pause_Write := False;
         Check_Sealed (Writer, Target, Before, "task-aborted name fragment");
      end;

      --  Bulk string fragment.
      declare
         Target     : aliased Test_Destination;
         Writer     : Writers.Writer (Target'Access, Maximum_Depth => 0);
         Diagnostic : Core.Diagnostic;
         Seen       : Transfer_Window;
         Before     : Natural;
      begin
         Writers.Initialize (Writer, Diagnostic);
         Writers.Begin_Document (Writer, Diagnostic);
         Writers.Begin_String (Writer, Diagnostic);
         Target.Pause_Write := True;
         Transfer_Gate.Reset;
         Before := Target.Abort_Calls;
         declare
            task Worker;

            task body Worker is
               Ignored : Core.Diagnostic;
            begin
               Writers.Put_String_Fragment (Writer, Large_Text, Ignored);
            end Worker;
         begin
            Transfer_Gate.Wait_For_Transfer (Seen);
            abort Worker;
         end;
         Target.Pause_Write := False;
         Check_Sealed (Writer, Target, Before, "task-aborted string fragment");
      end;

      --  Bulk exact number fragment.
      declare
         Target     : aliased Test_Destination;
         Writer     : Writers.Writer (Target'Access, Maximum_Depth => 0);
         Diagnostic : Core.Diagnostic;
         Seen       : Transfer_Window;
         Before     : Natural;
      begin
         Writers.Initialize (Writer, Diagnostic);
         Writers.Begin_Document (Writer, Diagnostic);
         Writers.Begin_Number (Writer, Diagnostic);
         Target.Pause_Write := True;
         Transfer_Gate.Reset;
         Before := Target.Abort_Calls;
         declare
            task Worker;

            task body Worker is
               Ignored : Core.Diagnostic;
            begin
               Writers.Put_Number_Fragment (Writer, Large_Number, Ignored);
            end Worker;
         begin
            Transfer_Gate.Wait_For_Transfer (Seen);
            abort Worker;
         end;
         Target.Pause_Write := False;
         Check_Sealed (Writer, Target, Before, "task-aborted number fragment");
      end;

      --  Complete scalar write.
      declare
         Target     : aliased Test_Destination;
         Writer     : Writers.Writer (Target'Access, Maximum_Depth => 0);
         Diagnostic : Core.Diagnostic;
         Seen       : Transfer_Window;
         Before     : Natural;
      begin
         Writers.Initialize (Writer, Diagnostic);
         Writers.Begin_Document (Writer, Diagnostic);
         Target.Pause_Write := True;
         Transfer_Gate.Reset;
         Before := Target.Abort_Calls;
         declare
            task Worker;

            task body Worker is
               Ignored : Core.Diagnostic;
            begin
               Writers.Put_Boolean (Writer, True, Ignored);
            end Worker;
         begin
            Transfer_Gate.Wait_For_Transfer (Seen);
            abort Worker;
         end;
         Target.Pause_Write := False;
         Check_Sealed (Writer, Target, Before, "task-aborted scalar call");
      end;
   end Test_Task_Abort_Mutating_Calls;

begin
   Test_Ordinary_Compact;
   Test_Escape_Batch_Boundaries;
   Test_Depth_And_Grammar;
   Test_Invalid_UTF8_And_Number;
   Test_Destination_Failures;
   Test_Grammar_And_Truncation;
   Test_Offset_Boundaries;
   Test_Ordered_Failure_Precedence;
   Test_Begin_Abort_Cleanup;
   Test_Task_Abort_Transfers;
   Test_Task_Abort_Mutating_Calls;
end Flyology_JSON.Writer_Core_Tests;
