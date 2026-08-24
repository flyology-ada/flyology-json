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
            Next
              (Self,
               Input (Input'First + Offset (Used) .. Input'Last),
               True,
               Result);
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

   Self       : Parser (1);
   Result     : Next_Result;
   Empty      : Ada.Streams.Stream_Element_Array (1 .. 0);
   Last_Byte  : constant Ada.Streams.Stream_Element_Array :=
     [Offset (37) => Character'Pos (' ')];
   Denied_Byte : constant Ada.Streams.Stream_Element_Array :=
     [Offset (-19) => Character'Pos (' ')];
   Primary    : Diagnostic;

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
end Flyology_JSON.Parser_Core.Offset_Tests;
