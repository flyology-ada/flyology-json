with Ada.Streams;
with Ada.Text_IO;
with Flyology_JSON.Parser_Numbers;

procedure Flyology_JSON.Number_DFA_Tests is

   package Numbers renames Flyology_JSON.Parser_Numbers;
   use type Numbers.Transition_Result;

   Failures : Natural := 0;

   procedure Check (Condition : Boolean; Label : String) is
   begin
      if not Condition then
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "FAIL: " & Label);
         Failures := Failures + 1;
      end if;
   end Check;

   function To_Octet (Item : Character) return Ada.Streams.Stream_Element
   is (Character'Pos (Item));

   procedure Check_Valid (Lexeme : String) is
      State  : Numbers.Number_State;
      Result : Numbers.Transition_Result;
   begin
      Numbers.Reset (State);
      Check (not Numbers.Accepting_End (State), "empty lexeme is not accepting");

      for Index in Lexeme'Range loop
         Numbers.Push (State, To_Octet (Lexeme (Index)), Result);
         Check (Result /= Numbers.Transition_Invalid, "valid transition in " & Lexeme);
         Check
           ((Result = Numbers.Transition_Accepted) = Numbers.Accepting_End (State),
            "transition result agrees with accepting state in " & Lexeme);
      end loop;

      Check (Numbers.Accepting_End (State), "valid final state for " & Lexeme);
      Check (Result = Numbers.Transition_Accepted, "accepted result for " & Lexeme);
   end Check_Valid;

   procedure Check_Incomplete (Lexeme : String) is
      State  : Numbers.Number_State;
      Result : Numbers.Transition_Result;
   begin
      Numbers.Reset (State);
      for Item of Lexeme loop
         Numbers.Push (State, To_Octet (Item), Result);
         Check (Result /= Numbers.Transition_Invalid, "incomplete transition in " & Lexeme);
      end loop;
      Check (not Numbers.Accepting_End (State), "incomplete final state for " & Lexeme);
      Check (Result = Numbers.Transition_Continues, "continuation result for " & Lexeme);
   end Check_Incomplete;

   procedure Check_Invalid (Lexeme : String; Invalid_At : Positive) is
      State  : Numbers.Number_State;
      Result : Numbers.Transition_Result;
   begin
      Numbers.Reset (State);
      for Index in Lexeme'Range loop
         Numbers.Push (State, To_Octet (Lexeme (Index)), Result);
         if Index - Lexeme'First + 1 < Invalid_At then
            Check (Result /= Numbers.Transition_Invalid, "valid prefix in " & Lexeme);
         else
            Check (Result = Numbers.Transition_Invalid, "invalid suffix in " & Lexeme);
         end if;
      end loop;
      Check (not Numbers.Accepting_End (State), "invalid final state for " & Lexeme);
   end Check_Invalid;

   procedure Check_Reset is
      State  : Numbers.Number_State;
      Result : Numbers.Transition_Result;
   begin
      Numbers.Reset (State);
      Numbers.Push (State, To_Octet ('+'), Result);
      Check (Result = Numbers.Transition_Invalid, "invalid before reset");
      Numbers.Reset (State);
      Check (not Numbers.Accepting_End (State), "reset returns to nonaccepting start");
      Numbers.Push (State, To_Octet ('0'), Result);
      Check (Result = Numbers.Transition_Accepted, "valid after reset");
   end Check_Reset;

begin
   Check_Valid ("0");
   Check_Valid ("-0");
   Check_Valid ("1");
   Check_Valid ("-1");
   Check_Valid ("10");
   Check_Valid ("1234567890");
   Check_Valid ("0.0");
   Check_Valid ("-0.125");
   Check_Valid ("1e0");
   Check_Valid ("1E+2");
   Check_Valid ("1e-2");
   Check_Valid ("12.34e+56");

   Check_Incomplete ("-");
   Check_Incomplete ("1.");
   Check_Incomplete ("1e");
   Check_Incomplete ("1E+");
   Check_Incomplete ("1e-");

   Check_Invalid ("+1", 1);
   Check_Invalid (".1", 1);
   Check_Invalid ("01", 2);
   Check_Invalid ("-01", 3);
   Check_Invalid ("--1", 2);
   Check_Invalid ("1..0", 3);
   Check_Invalid ("1e.0", 3);
   Check_Invalid ("1e+-2", 4);
   Check_Invalid ("1a", 2);
   Check_Invalid ("NaN", 1);
   Check_Invalid ("Infinity", 1);

   Check_Reset;

   if Failures /= 0 then
      raise Program_Error with Natural'Image (Failures) & " number DFA test failures";
   end if;
end Flyology_JSON.Number_DFA_Tests;
