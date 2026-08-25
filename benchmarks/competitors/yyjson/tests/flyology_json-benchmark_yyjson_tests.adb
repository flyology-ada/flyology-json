--  Copyright (c) 2026 Yurii Rashkovskii
--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Streams;
with Ada.Text_IO;
with Flyology_JSON.Benchmark_YYJSON;
with Flyology_JSON.Benchmark_YYJSON.ABI_Testing;
with Interfaces;

procedure Flyology_JSON.Benchmark_YYJSON_Tests is
   use Flyology_JSON.Benchmark_YYJSON;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;

   subtype Offset is Ada.Streams.Stream_Element_Offset;

   procedure Check (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Check;

   function Octets (Text : String; First : Offset) return Ada.Streams.Stream_Element_Array is
      Result : Ada.Streams.Stream_Element_Array
        (First .. First + Offset (Text'Length) - 1);
   begin
      for Index in Text'Range loop
         Result (First + Offset (Index - Text'First)) := Character'Pos (Text (Index));
      end loop;
      return Result;
   end Octets;

   procedure Check_Valid
     (Text            : String;
      First           : Offset;
      Expected_Values : Interfaces.Unsigned_64) is
      Data        : constant Ada.Streams.Stream_Element_Array := Octets (Text, First);
      Observation : Parse_Observation;
   begin
      Parse (Data, Observation);
      Check (Observation.Status = Accepted, "valid input rejected");
      Check (Observation.Error_Code = 0, "success retained an error code");
      Check
        (Observation.Read_Octets = Interfaces.Unsigned_64 (Data'Length),
         "success reported the wrong read length");
      Check (Observation.Value_Count = Expected_Values, "success reported the wrong value count");
      Check (Observation.Checksum /= 0, "success checksum was not observable");
   end Check_Valid;

   procedure Check_Invalid
     (Data            : Ada.Streams.Stream_Element_Array;
      Expected_Code   : Interfaces.Unsigned_32;
      Expected_Offset : Interfaces.Unsigned_64) is
      Observation : Parse_Observation;
   begin
      Parse (Data, Observation);
      Check (Observation.Status = Rejected, "malformed input was accepted");
      Check
        (Observation.Error_Code = Expected_Code,
         "malformed error code changed:"
         & Interfaces.Unsigned_32'Image (Observation.Error_Code));
      Check
        (Observation.Error_Byte = Expected_Offset,
         "malformed error offset changed:"
         & Interfaces.Unsigned_64'Image (Observation.Error_Byte));
      Check (Observation.Read_Octets = 0, "failure published a read length");
      Check (Observation.Value_Count = 0, "failure published a value count");
   end Check_Invalid;

   procedure Check_Rejected (Text : String; First : Offset) is
      Observation : Parse_Observation;
   begin
      Parse (Octets (Text, First), Observation);
      Check (Observation.Status = Rejected, "disabled yyjson extension was accepted");
      Check (Observation.Error_Code /= 0, "extension rejection omitted its error code");
   end Check_Rejected;

begin
   Check
     (Flyology_JSON.Benchmark_YYJSON.ABI_Testing.Compatible,
      "Ada records do not match the pinned yyjson C ABI");

   Check_Valid ("null", First => 17, Expected_Values => 1);
   Check_Valid ("{""a"":[1,true,null]}", First => -23, Expected_Values => 6);
   Check_Valid ("{""a"":1,""a"":2}", First => 8, Expected_Values => 5);
   Check_Valid
     ("{""euro"":""" & Character'Val (16#E2#) & Character'Val (16#82#)
      & Character'Val (16#AC#) & """}",
      First           => 101,
      Expected_Values => 3);

   declare
      Empty : Ada.Streams.Stream_Element_Array (4 .. 3);
   begin
      Check_Invalid (Empty, Expected_Code => 1, Expected_Offset => 0);
   end;

   Check_Invalid (Octets ("[1,]", 9), Expected_Code => 7, Expected_Offset => 2);
   Check_Rejected ("[/* comment */1]", First => -4);
   Check_Rejected ("NaN", First => 50);
   Check_Rejected ("+1", First => 2);
   Check_Rejected ("""\uD800""", First => 12);

   Check_Rejected ('"' & Character'Val (1) & '"', First => 30);

   declare
      Text : constant String :=
        "{""text"":""line\n/\u001F/euro:"
        & Character'Val (16#E2#)
        & Character'Val (16#82#)
        & Character'Val (16#AC#)
        & """,""value"":123,""ok"":true}";
      Data        : constant Ada.Streams.Stream_Element_Array := Octets (Text, -91);
      Expected    : constant Ada.Streams.Stream_Element_Array := Octets (Text, 117);
      Context     : Prepared_Document;
      Preparation : Parse_Observation;
      Observation : Write_Observation;
      Matches     : Boolean;
   begin
      Check (not Is_Prepared (Context), "new write context is unexpectedly prepared");
      Prepare_Write (Data, Context, Preparation);
      Check (Preparation.Status = Accepted, "writer DOM preparation rejected valid JSON");
      Check (Is_Prepared (Context), "successful writer DOM preparation was not retained");

      Check_Write_Output (Context, Expected, Observation, Matches);
      Check (Observation.Status = Write_Succeeded, "yyjson DOM serialization failed");
      Check (Observation.Error_Code = 0, "successful serialization retained an error code");
      Check
        (Observation.Output_Octets = Interfaces.Unsigned_64 (Expected'Length),
         "serialization reported the wrong output length");
      Check (Observation.Checksum /= 0, "serialization checksum was not observable");
      Check (Matches, "yyjson default compact output changed");

      Write (Context, Observation);
      Check (Observation.Status = Write_Succeeded, "repeated yyjson DOM serialization failed");
      Release (Context);
      Release (Context);
      Check (not Is_Prepared (Context), "writer DOM release was not idempotent");

      Write (Context, Observation);
      Check (Observation.Status = Write_Rejected, "unprepared writer context was accepted");
      Check (Observation.Output_Octets = 0, "unprepared writer published output length");
   end;

   declare
      Context     : Prepared_Document;
      Preparation : Parse_Observation;
   begin
      Prepare_Write (Octets ("[1,]", -44), Context, Preparation);
      Check (Preparation.Status = Rejected, "malformed writer DOM preparation was accepted");
      Check (not Is_Prepared (Context), "failed writer DOM preparation retained a document");
      Release (Context);
   end;

   declare
      BOM : constant Ada.Streams.Stream_Element_Array :=
        [41 => 16#EF#, 42 => 16#BB#, 43 => 16#BF#, 44 => Character'Pos ('{'),
         45 => Character'Pos ('}')];
   begin
      Check_Invalid (BOM, Expected_Code => 6, Expected_Offset => 0);
   end;

   declare
      Bad_UTF8 : constant Ada.Streams.Stream_Element_Array :=
        [7 => Character'Pos ('"'), 8 => 16#C0#, 9 => 16#AF#, 10 => Character'Pos ('"')];
   begin
      Check_Invalid (Bad_UTF8, Expected_Code => 10, Expected_Offset => 1);
   end;

   for Iteration in 1 .. 10_000 loop
      Check_Valid ("{""owned"":true}", Offset (Iteration mod 31 - 15), 3);
   end loop;

   Ada.Text_IO.Put_Line ("yyjson adapter tests passed");
end Flyology_JSON.Benchmark_YYJSON_Tests;
