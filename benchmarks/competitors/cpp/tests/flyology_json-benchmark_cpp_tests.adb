--  Copyright (c) 2026 Yurii Rashkovskii
--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Streams;
with Ada.Text_IO;
with Flyology_JSON.Benchmark_CPP.Rapidjson;
with Flyology_JSON.Benchmark_CPP.Simdjson;
with Interfaces;

procedure Flyology_JSON.Benchmark_CPP_Tests is
   use Flyology_JSON.Benchmark_CPP;
   use type Ada.Streams.Stream_Element_Array;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Unsigned_64;

   package Rapid renames Flyology_JSON.Benchmark_CPP.Rapidjson;
   package Simd renames Flyology_JSON.Benchmark_CPP.Simdjson;

   subtype Offset is Ada.Streams.Stream_Element_Offset;

   procedure Check (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Check;

   function Octets
     (Text  : String;
      First : Offset) return Ada.Streams.Stream_Element_Array is
      Result : Ada.Streams.Stream_Element_Array
        (First .. First + Offset (Text'Length) - 1);
   begin
      for Index in Text'Range loop
         Result (First + Offset (Index - Text'First)) := Character'Pos (Text (Index));
      end loop;
      return Result;
   end Octets;

   function Padded_Octets
     (Text  : String;
      First : Offset) return Ada.Streams.Stream_Element_Array is
      Padding : constant Offset := Offset (Simd.Required_Padding);
      Result  : Ada.Streams.Stream_Element_Array
        (First .. First + Offset (Text'Length) + Padding - 1) := [others => 0];
   begin
      for Index in Text'Range loop
         Result (First + Offset (Index - Text'First)) := Character'Pos (Text (Index));
      end loop;
      return Result;
   end Padded_Octets;

   procedure Check_Valid (Text : String; First : Offset) is
      Rapid_Data : constant Ada.Streams.Stream_Element_Array := Octets (Text, First);
      Simd_Data  : constant Ada.Streams.Stream_Element_Array := Padded_Octets (Text, First - 37);
      Rapid_Copy : constant Ada.Streams.Stream_Element_Array := Rapid_Data;
      Simd_Copy  : constant Ada.Streams.Stream_Element_Array := Simd_Data;
      Rapid_Result : Parse_Observation;
      Event_Result : Parse_Observation;
      Simd_Result  : Parse_Observation;
   begin
      Rapid.Parse_DOM (Rapid_Data, Rapid_Result);
      Rapid.Parse_Events (Rapid_Data, Event_Result);
      Simd.Parse_DOM (Simd_Data, Interfaces.Unsigned_64 (Text'Length), Simd_Result);

      Check (Rapid_Result.Status = Accepted, "RapidJSON rejected valid JSON");
      Check (Simd_Result.Status = Accepted, "simdjson rejected valid JSON");
      Check (Event_Result.Status = Accepted, "RapidJSON SAX rejected valid JSON");
      Check (Rapid_Result.Checksum = Simd_Result.Checksum, "competitor checksums disagree");
      Check (Rapid_Result.Event_Count = Simd_Result.Event_Count, "event counts disagree");
      Check (Rapid_Result.Scalar_Count = Simd_Result.Scalar_Count, "scalar counts disagree");
      Check
        (Rapid_Result.Member_Name_Count = Simd_Result.Member_Name_Count,
         "member-name counts disagree");
      Check
        (Rapid_Result.Input_Bytes = Interfaces.Unsigned_64 (Text'Length),
         "RapidJSON input count changed");
      Check
        (Simd_Result.Input_Bytes = Interfaces.Unsigned_64 (Text'Length),
         "simdjson input count changed");
      Check
        (Event_Result.Event_Count = Rapid_Result.Event_Count
         and then Event_Result.Scalar_Count = Rapid_Result.Scalar_Count
         and then Event_Result.Member_Name_Count = Rapid_Result.Member_Name_Count
         and then Event_Result.Input_Bytes = Interfaces.Unsigned_64 (Text'Length),
         "RapidJSON SAX observation counts disagree with its DOM");
      Check (Rapid_Data = Rapid_Copy, "RapidJSON mutated borrowed input");
      Check (Simd_Data = Simd_Copy, "simdjson mutated borrowed input or padding");
   end Check_Valid;

   procedure Check_Rejected (Text : String; First : Offset) is
      Rapid_Result : Parse_Observation;
      Event_Result : Parse_Observation;
      Simd_Result  : Parse_Observation;
   begin
      Rapid.Parse_DOM (Octets (Text, First), Rapid_Result);
      Rapid.Parse_Events (Octets (Text, First), Event_Result);
      Simd.Parse_DOM
        (Padded_Octets (Text, First - 13),
         Interfaces.Unsigned_64 (Text'Length),
         Simd_Result);
      Check (Rapid_Result.Status = Parse_Error, "RapidJSON accepted disabled syntax: " & Text);
      Check (Simd_Result.Status = Parse_Error, "simdjson accepted disabled syntax: " & Text);
      Check (Event_Result.Status = Parse_Error, "RapidJSON SAX accepted disabled syntax: " & Text);
      Check (Rapid_Result.Checksum = 0, "RapidJSON published failure counters");
      Check (Simd_Result.Checksum = 0, "simdjson published failure counters");
      Check (Event_Result.Checksum = 0, "RapidJSON SAX published failure counters");
   end Check_Rejected;

   function Nested_Array (Depth : Positive) return String is
      Result : String (1 .. Depth * 2 + 4);
   begin
      Result (1 .. Depth) := [others => '['];
      Result (Depth + 1 .. Depth + 4) := "null";
      Result (Depth + 5 .. Result'Last) := [others => ']'];
      return Result;
   end Nested_Array;

begin
   Check (Simd.Required_Padding = 64, "pinned simdjson padding changed");

   Check_Valid ("null", 17);
   Check_Valid ("{""a"":[null,true,-1,1.5,""x""]}", -23);
   Check_Valid ("{""a"":1,""\u0061"":2}", 81);
   Check_Valid
     ("{""euro"":""" & Character'Val (16#E2#) & Character'Val (16#82#)
      & Character'Val (16#AC#) & """}",
      103);

   declare
      Text         : constant String := "{""a"":1,""\u0061"":2}";
      Rapid_Result : Parse_Observation;
      Simd_Result  : Parse_Observation;
   begin
      Rapid.Parse_DOM (Octets (Text, -11), Rapid_Result);
      Simd.Parse_DOM
        (Padded_Octets (Text, 41), Interfaces.Unsigned_64 (Text'Length), Simd_Result);
      Check (Rapid_Result.Member_Name_Count = 2, "RapidJSON collapsed duplicate names");
      Check (Simd_Result.Member_Name_Count = 2, "simdjson collapsed duplicate names");
   end;

   Check_Rejected ("[", 9);
   Check_Rejected ("[0,]", -7);
   Check_Rejected ("/* x */null", 50);
   Check_Rejected ("+1", 3);
   Check_Rejected ("01", 4);
   Check_Rejected ("NaN", 5);
   Check_Rejected ("""\uD800""", 6);

   declare
      Empty  : Ada.Streams.Stream_Element_Array (4 .. 3);
      Result : Parse_Observation;
   begin
      Rapid.Parse_DOM (Empty, Result);
      Check (Result.Status = Parse_Error, "RapidJSON empty input status changed");
   end;

   declare
      Too_Short : constant Ada.Streams.Stream_Element_Array := Octets ("null", -40);
      Result    : Parse_Observation;
   begin
      Simd.Parse_DOM (Too_Short, 4, Result);
      Check (Result.Status = Invalid_Argument, "simdjson accepted missing padding");
      Check (Result.Checksum = 0, "simdjson padding failure published output");
   end;

   declare
      At_Limit     : constant String := Nested_Array (1_023);
      Beyond       : constant String := Nested_Array (1_024);
      Simd_Result  : Parse_Observation;
      Rapid_Result : Parse_Observation;
   begin
      Simd.Parse_DOM
        (Padded_Octets (At_Limit, -5),
         Interfaces.Unsigned_64 (At_Limit'Length),
         Simd_Result);
      Check (Simd_Result.Status = Accepted, "simdjson rejected its documented depth limit");
      Simd.Parse_DOM
        (Padded_Octets (Beyond, 5), Interfaces.Unsigned_64 (Beyond'Length), Simd_Result);
      Check (Simd_Result.Status = Parse_Error, "simdjson accepted beyond its depth limit");
      Rapid.Parse_DOM (Octets (Beyond, -15), Rapid_Result);
      Check (Rapid_Result.Status = Accepted, "RapidJSON exposed an undocumented depth cap");
   end;

   declare
      BOM : constant String :=
        Character'Val (16#EF#) & Character'Val (16#BB#) & Character'Val (16#BF#) & "null";
      Bad_UTF8 : constant String :=
        '"' & Character'Val (16#C0#) & Character'Val (16#AF#) & '"';
      Rapid_Result : Parse_Observation;
      Event_Result : Parse_Observation;
      Simd_Result  : Parse_Observation;
   begin
      Rapid.Parse_DOM (Octets (BOM, 19), Rapid_Result);
      Rapid.Parse_Events (Octets (BOM, -9), Event_Result);
      Simd.Parse_DOM (Padded_Octets (BOM, -19), Interfaces.Unsigned_64 (BOM'Length), Simd_Result);
      Check (Rapid_Result.Status = Accepted, "RapidJSON stopped accepting an initial BOM");
      Check (Event_Result.Status = Parse_Error, "RapidJSON SAX stopped rejecting an initial BOM");
      Check (Simd_Result.Status = Accepted, "simdjson stopped accepting an initial BOM");
      Check_Rejected (Bad_UTF8, -19);
      Check_Rejected ('"' & ASCII.LF & '"', 27);
   end;

   for Iteration in 1 .. 1_000 loop
      Check_Valid ("{""owned"":true}", Offset (Iteration mod 31 - 15));
   end loop;

   Ada.Text_IO.Put_Line ("C++ competitor adapter tests passed");
end Flyology_JSON.Benchmark_CPP_Tests;
