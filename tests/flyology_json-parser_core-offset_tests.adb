with Ada.Streams;

procedure Flyology_JSON.Parser_Core.Offset_Tests is

   use type Ada.Streams.Stream_Element_Count;
   use type Byte_Offset;

   subtype Offset is Ada.Streams.Stream_Element_Offset;

   procedure Check (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Check;

   function To_Input (Text : String; First : Offset) return Ada.Streams.Stream_Element_Array is
      Result : Ada.Streams.Stream_Element_Array (First .. First + Offset (Text'Length) - 1);
   begin
      for Position in Text'Range loop
         Result (First + Offset (Position - Text'First)) := Character'Pos (Text (Position));
      end loop;
      return Result;
   end To_Input;

   procedure Drain_Reused_Parser (Self : in out Parser) is
      Input  : constant Ada.Streams.Stream_Element_Array :=
        [Offset (-7) => Character'Pos ('n'),
         Offset (-6) => Character'Pos ('u'),
         Offset (-5) => Character'Pos ('l'),
         Offset (-4) => Character'Pos ('l')];
      Used   : Ada.Streams.Stream_Element_Count := 0;
      Result : Next_Result;
   begin
      loop
         if Used < Input'Length then
            Next (Self, Input (Input'First + Offset (Used) .. Input'Last), True, Result);
         else
            declare
               Empty : Ada.Streams.Stream_Element_Array (1 .. 0);
            begin
               Next (Self, Empty, True, Result);
            end;
         end if;

         Check (Result.Consumed <= Input'Length - Used, "reuse consumed beyond its input");
         Used := Used + Result.Consumed;
         exit when Result.Outcome /= Event_Ready;
      end loop;

      Check (Result.Outcome = Document_Complete, "reset parser did not complete a new document");
      Check (Used = Input'Length, "reset parser did not consume the complete new document");
   end Drain_Reused_Parser;

   procedure Begin_At (Self : in out Parser; At_Offset : Byte_Offset) is
      Begin_Result : Next_Result;
      No_Input     : Ada.Streams.Stream_Element_Array (1 .. 0);
   begin
      Initialize (Self);
      Next (Self, No_Input, False, Begin_Result);
      Check (Begin_Result.Outcome = Event_Ready, "literal offset setup omitted document begin");
      Self.Next_Offset := At_Offset;
   end Begin_At;

   procedure Check_Literal_Offset_Boundaries is
   begin
      declare
         Subject : Parser (0, 0, 0, Reject_Duplicates);
         Input   : constant Ada.Streams.Stream_Element_Array :=
           [Offset (-11) => Character'Pos ('n'),
            Offset (-10) => Character'Pos ('u'),
            Offset (-9)  => Character'Pos ('l'),
            Offset (-8)  => Character'Pos ('l')];
         Item    : Next_Result;
      begin
         Begin_At (Subject, Byte_Offset'Last - 4);
         Next (Subject, Input, True, Item);
         Check (Item.Outcome = Event_Ready, "literal ending at Last was rejected");
         Check (Item.Item.Kind = Null_Value, "literal ending at Last emitted the wrong event");
         Check (Item.Consumed = 4, "literal ending at Last changed its consumed count");
         Check (Subject.Next_Offset = Byte_Offset'Last, "literal ending at Last changed its offset");
      end;

      declare
         Subject : Parser (0, 0, 0, Reject_Duplicates);
         Input   : constant Ada.Streams.Stream_Element_Array := To_Input ("null", -13);
         Item    : Next_Result;
      begin
         Begin_At (Subject, Byte_Offset'Last - 3);
         Next (Subject, Input, True, Item);
         Check (Item.Outcome = Parse_Failed, "unrepresentable literal byte was accepted");
         Check (Item.Consumed = 3, "offset denial consumed the literal's denied byte");
         Check (Item.Diagnostic.Code = Offset_Exhausted, "literal offset denial changed status");
         Check (Item.Diagnostic.Offset = Byte_Offset'Last, "literal offset denial moved");
      end;

      declare
         Subject : Parser (0, 0, 0, Reject_Duplicates);
         Input   : constant Ada.Streams.Stream_Element_Array := To_Input ("false", -17);
         Item    : Next_Result;
      begin
         Begin_At (Subject, Byte_Offset'Last - 5);
         Next (Subject, Input, True, Item);
         Check (Item.Outcome = Event_Ready, "five-byte literal ending at Last was rejected");
         Check (Item.Item.Kind = Boolean_Value, "five-byte literal emitted the wrong event");
         Check (not Item.Item.Boolean_Data, "false literal changed its Boolean value");
         Check (Item.Consumed = 5, "five-byte literal changed its consumed count");
         Check
           (Subject.Next_Offset = Byte_Offset'Last, "five-byte literal ending at Last changed its offset");
      end;

      declare
         Subject : Parser (0, 0, 0, Reject_Duplicates);
         Input   : constant Ada.Streams.Stream_Element_Array := To_Input ("false", -21);
         Item    : Next_Result;
      begin
         Begin_At (Subject, Byte_Offset'Last - 4);
         Next (Subject, Input, True, Item);
         Check (Item.Outcome = Parse_Failed, "five-byte literal exceeded Last");
         Check (Item.Consumed = 4, "five-byte denial consumed the denied byte");
         Check (Item.Diagnostic.Code = Offset_Exhausted, "five-byte denial changed status");
         Check (Item.Diagnostic.Offset = Byte_Offset'Last, "five-byte denial moved");
      end;

      declare
         Subject : Parser (0, 0, 0, Reject_Duplicates);
         Input   : constant Ada.Streams.Stream_Element_Array := To_Input ("nXll", 19);
         Item    : Next_Result;
      begin
         Begin_At (Subject, Byte_Offset'Last - 4);
         Next (Subject, Input, True, Item);
         Check (Item.Outcome = Parse_Failed, "literal mismatch before Last was accepted");
         Check (Item.Consumed = 2, "literal mismatch changed its consumed count");
         Check (Item.Diagnostic.Code = Invalid_Literal, "literal mismatch changed status");
         Check (Item.Diagnostic.Offset = Byte_Offset'Last - 3, "literal mismatch changed its exact offset");
      end;

      declare
         Subject : Parser (0, 0, 0, Reject_Duplicates);
         Input   : constant Ada.Streams.Stream_Element_Array := To_Input ("nulX", 23);
         Item    : Next_Result;
      begin
         Begin_At (Subject, Byte_Offset'Last - 3);
         Next (Subject, Input, True, Item);
         Check (Item.Outcome = Parse_Failed, "denied mismatching literal byte was accepted");
         Check (Item.Consumed = 3, "denied mismatch consumed the unrepresentable byte");
         Check (Item.Diagnostic.Code = Offset_Exhausted, "denied mismatch lost offset precedence");
         Check (Item.Diagnostic.Offset = Byte_Offset'Last, "denied mismatch moved the offset");
      end;

      declare
         Subject : Parser (0, 0, 0, Reject_Duplicates);
         Input   : constant Ada.Streams.Stream_Element_Array := To_Input ("nullx", -31);
         Item    : Next_Result;
      begin
         Begin_At (Subject, Byte_Offset'Last - 4);
         Next (Subject, Input, True, Item);
         Check (Item.Outcome = Parse_Failed, "invalid suffix beyond Last was accepted");
         Check (Item.Consumed = 4, "invalid suffix beyond Last consumed the denied byte");
         Check (Item.Diagnostic.Code = Offset_Exhausted, "invalid suffix changed status");
         Check (Item.Diagnostic.Offset = Byte_Offset'Last, "invalid suffix moved");
      end;

      declare
         Subject : Parser (0, 0, 0, Reject_Duplicates);
         Input   : constant Ada.Streams.Stream_Element_Array := To_Input ("null ", -37);
         Item    : Next_Result;
      begin
         Begin_At (Subject, Byte_Offset'Last - 4);
         Next (Subject, Input, True, Item);
         Check (Item.Outcome = Event_Ready, "legal literal lookahead was not provisional");
         Check (Item.Item.Kind = Null_Value, "legal literal lookahead changed the value");
         Check (Item.Consumed = 4, "legal literal lookahead consumed its delimiter");
         Next (Subject, Input (Input'Last .. Input'Last), True, Item);
         Check (Item.Outcome = Event_Ready, "literal at Last omitted document end");
         Check (Item.Item.Kind = Document_End, "literal at Last changed document-end ordering");
         Check (Item.Consumed = 0, "document end consumed the delimiter beyond Last");
         Next (Subject, Input (Input'Last .. Input'Last), True, Item);
         Check (Item.Outcome = Parse_Failed, "delimiter beyond Last was accepted");
         Check (Item.Consumed = 0, "delimiter beyond Last was consumed");
         Check (Item.Diagnostic.Code = Offset_Exhausted, "delimiter beyond Last changed status");
         Check (Item.Diagnostic.Offset = Byte_Offset'Last, "delimiter beyond Last moved");
      end;
   end Check_Literal_Offset_Boundaries;

   procedure Check_Drain_Offset_Boundaries is
      Input : constant Ada.Streams.Stream_Element_Array := To_Input ("null ", -47);
   begin
      declare
         Subject : Parser (0, 0, 0, Reject_Duplicates);
         Events  : Event_Array (11 .. 18);
         Item    : Drain_Result;
      begin
         Begin_At (Subject, Byte_Offset'Last - 4);
         Drain (Subject, Input, True, Events, Item);
         Check (Item.Stop = Drain_Parse_Failed, "underfull drain accepted a byte beyond Last");
         Check (Item.Consumed = 4, "underfull drain consumed its denied byte");
         Check (Item.Produced = 2, "underfull drain lost provisional terminal events");
         Check (Events (11).Kind = Null_Value, "underfull drain changed literal ordering");
         Check (Events (12).Kind = Document_End, "underfull drain changed document-end ordering");
         Check (Item.Diagnostic.Code = Offset_Exhausted, "underfull drain changed offset status");
         Check (Item.Diagnostic.Offset = Byte_Offset'Last, "underfull drain moved offset failure");
         Check (Subject.Next_Offset = Byte_Offset'Last, "underfull drain wrapped source offset");
      end;

      declare
         Subject : Parser (0, 0, 0, Reject_Duplicates);
         Events  : Event_Array (-13 .. -12);
         Item    : Drain_Result;
      begin
         Begin_At (Subject, Byte_Offset'Last - 4);
         Drain (Subject, Input, True, Events, Item);
         Check (Item.Stop = Drain_Buffer_Full, "exact drain did not stop at its event boundary");
         Check (Item.Consumed = 4, "exact drain consumed beyond its final event");
         Check (Item.Produced = 2, "exact drain changed its event count");
         Check (State (Subject) = Active, "exact drain reported following failure early");

         Drain (Subject, Input (Input'Last .. Input'Last), True, Events, Item);
         Check (Item.Stop = Drain_Parse_Failed, "exact drain did not report following exhaustion");
         Check (Item.Consumed = 0, "exact drain consumed its denied byte");
         Check (Item.Produced = 0, "exact drain published an event with exhaustion");
         Check (Item.Diagnostic.Code = Offset_Exhausted, "exact drain changed offset status");
         Check (Item.Diagnostic.Offset = Byte_Offset'Last, "exact drain moved offset failure");
      end;
   end Check_Drain_Offset_Boundaries;

   procedure Check_Dense_Zero_Offset_Boundaries is
      Prefix : constant Ada.Streams.Stream_Element_Array := To_Input ("[null,", -53);
      Suffix : constant Ada.Streams.Stream_Element_Array := To_Input (",0]", 61);

      procedure Prepare (Subject : in out Parser; Item : out Drain_Result) is
         Setup_Events : Event_Array (-9 .. -7);
      begin
         Initialize (Subject);
         Drain (Subject, Prefix, False, Setup_Events, Item);
         Check (Item.Stop = Drain_Buffer_Full, "dense-zero setup did not stop before its comma");
         Check (Item.Consumed = Prefix'Length - 1, "dense-zero setup consumed its comma");
         Check (Item.Produced = Setup_Events'Length, "dense-zero setup changed its transcript");
         Check (State (Subject) = Active, "dense-zero setup changed parser state");
      end Prepare;
   begin
      declare
         Subject : Parser (1, 0, 0, Reject_Duplicates);
         Events  : Event_Array (-5 .. 2);
         Item    : Drain_Result;
      begin
         Prepare (Subject, Item);
         Subject.Next_Offset := Byte_Offset'Last - 2;
         Drain (Subject, Suffix, True, Events, Item);
         Check (Item.Stop = Drain_Parse_Failed, "dense zero accepted a byte beyond Last");
         Check (Item.Consumed = 2, "dense zero consumed its denied closing bracket");
         Check (Item.Produced = 3, "dense zero changed its complete transcript");
         Check (Events (-5).Kind = Number_Begin, "dense zero omitted number begin");
         Check (Events (-4).Kind = Number_Fragment, "dense zero omitted number fragment");
         Check (Events (-3).Kind = Number_End, "dense zero omitted number end");
         Check (Events (-5).Source.First = Byte_Offset'Last - 1, "dense zero moved number begin");
         Check (Events (-4).Source.First = Byte_Offset'Last - 1, "dense zero moved number fragment");
         Check (Events (-3).Source.First = Byte_Offset'Last, "dense zero moved number end");
         Check (Item.Diagnostic.Code = Offset_Exhausted, "dense zero changed offset status");
         Check (Item.Diagnostic.Offset = Byte_Offset'Last, "dense zero moved offset failure");
      end;

      declare
         Subject : Parser (1, 0, 0, Reject_Duplicates);
         Events  : Event_Array (17 .. 24);
         Item    : Drain_Result;
      begin
         Prepare (Subject, Item);
         Subject.Next_Offset := Byte_Offset'Last - 1;
         Drain (Subject, Suffix, True, Events, Item);
         Check (Item.Stop = Drain_Parse_Failed, "dense zero crossed Last from its comma");
         Check (Item.Consumed = 1, "dense zero consumed its unrepresentable value byte");
         Check (Item.Produced = 1, "dense zero lost its provisional number begin");
         Check (Events (17).Kind = Number_Begin, "dense zero changed fallback ordering");
         Check (Events (17).Source.First = Byte_Offset'Last, "dense zero moved fallback begin");
         Check (Item.Diagnostic.Code = Offset_Exhausted, "dense fallback changed offset status");
         Check (Item.Diagnostic.Offset = Byte_Offset'Last, "dense fallback moved offset failure");
      end;
   end Check_Dense_Zero_Offset_Boundaries;

   --  Explicit storage for the reset fixture; these values are not defaults.
   Self        : Parser (1, 16, 4, Reject_Duplicates);
   Result      : Next_Result;
   Empty       : Ada.Streams.Stream_Element_Array (1 .. 0);
   Last_Byte   : constant Ada.Streams.Stream_Element_Array := [Offset (37) => Character'Pos (' ')];
   Denied_Byte : constant Ada.Streams.Stream_Element_Array := [Offset (-19) => Character'Pos (' ')];
   Primary     : Diagnostic;

begin
   Initialize (Self);
   Next (Self, Empty, False, Result);
   Check (Result.Outcome = Event_Ready, "offset setup did not emit Document_Begin");
   Check (Result.Item.Kind = Document_Begin, "offset setup emitted the wrong event");
   Check (Result.Consumed = 0, "Document_Begin consumed input");

   --  This assignment is possible only because this test is a private child
   --  of Parser_Core.  It creates no production seam or externally visible
   --  way to forge source coordinates.
   Self.Next_Offset := Byte_Offset'Last - 1;

   Next (Self, Last_Byte, False, Result);
   Check (Result.Outcome = Need_Input, "the source byte at Last - 1 was rejected");
   Check (Result.Consumed = 1, "the source byte at Last - 1 was not consumed once");
   Check (Self.Next_Offset = Byte_Offset'Last, "the source offset wrapped or advanced incorrectly");
   Check (State (Self) = Active, "accepting the final source byte changed parser state");

   Next (Self, Denied_Byte, False, Result);
   Check (Result.Outcome = Parse_Failed, "an unrepresentable source byte was accepted");
   Check (Result.Consumed = 0, "offset exhaustion consumed the denied byte");
   Check (Result.Diagnostic.Code = Offset_Exhausted, "wrong offset-exhaustion status");
   Check (Result.Diagnostic.Offset = Byte_Offset'Last, "wrong offset-exhaustion coordinate");
   Check (Self.Next_Offset = Byte_Offset'Last, "offset exhaustion wrapped the source coordinate");
   Check (State (Self) = Failed, "offset exhaustion did not enter Failed");

   Primary := Terminal_Diagnostic (Self);
   Next (Self, Denied_Byte, False, Result);
   Check (Result.Outcome = Call_Rejected, "a call after offset exhaustion was not rejected");
   Check (Result.Consumed = 0, "a rejected terminal call consumed input");
   Check (Terminal_Diagnostic (Self) = Primary, "a rejected call replaced the primary diagnostic");
   Check (Self.Next_Offset = Byte_Offset'Last, "a rejected call changed the terminal offset");

   Reset (Self);
   Check (State (Self) = Ready, "offset-exhausted parser did not reset");
   Check (Self.Next_Offset = 0, "reset did not restore the source origin");
   Drain_Reused_Parser (Self);
   Check_Literal_Offset_Boundaries;
   Check_Drain_Offset_Boundaries;
   Check_Dense_Zero_Offset_Boundaries;
end Flyology_JSON.Parser_Core.Offset_Tests;
