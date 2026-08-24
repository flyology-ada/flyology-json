--  Copyright (c) 2026 Yurii Rashkovskii
--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Streams;
with Flyology_JSON.Benchmark_Rust;
with Interfaces;

procedure Flyology_JSON.Benchmark_Rust_Tests is
   package Adapter renames Flyology_JSON.Benchmark_Rust;

   use type Ada.Streams.Stream_Element_Count;
   use type Ada.Streams.Stream_Element_Array;
   use type Adapter.Parse_Status;
   use type Adapter.Implementation;
   use type Interfaces.Unsigned_64;

   function Octets
     (Text  : String;
      First : Ada.Streams.Stream_Element_Offset)
      return Ada.Streams.Stream_Element_Array is
      Result : Ada.Streams.Stream_Element_Array
        (First .. First + Ada.Streams.Stream_Element_Offset (Text'Length) - 1);
   begin
      for Index in Text'Range loop
         Result
           (First + Ada.Streams.Stream_Element_Offset (Index - Text'First)) :=
             Character'Pos (Text (Index));
      end loop;
      return Result;
   end Octets;

   Valid_Text : constant String := "{""a"":[null,true,-1,1.5,""x""]}";

begin
   for Kind in Adapter.Implementation loop
      declare
         Data   : constant Ada.Streams.Stream_Element_Array := Octets (Valid_Text, -17);
         Before : constant Ada.Streams.Stream_Element_Array := Data;
         Expected_Checksum : constant Interfaces.Unsigned_64 :=
           (if Kind = Adapter.Sonic_RS
            then 5_624_672_763_124_767_306
            else 9_979_358_259_564_605_272);
         Result : Adapter.Observation;
      begin
         Adapter.Parse (Kind, Data, Result);
         if Result.Status /= Adapter.Success
           or else Result.Checksum /= Expected_Checksum
           or else Result.Items /= 10
           or else Data /= Before
         then
            raise Program_Error with "Rust adapter rejected the valid arbitrary-bound fixture";
         end if;
      end;

      declare
         Data   : constant Ada.Streams.Stream_Element_Array := Octets (Valid_Text, 0);
         Result : Adapter.Observation;
      begin
         Adapter.Parse (Kind, Data, Result);
         if Result.Status /= Adapter.Success
           or else Result.Items /= 10
         then
            raise Program_Error with "Rust adapter rejected the valid zero-bound fixture";
         end if;
      end;

      declare
         Data   : constant Ada.Streams.Stream_Element_Array := Octets ("[", 23);
         Result : Adapter.Observation;
      begin
         Adapter.Parse (Kind, Data, Result);
         if Result.Status /= Adapter.Parse_Error then
            raise Program_Error with "Rust adapter accepted malformed JSON";
         end if;
      end;

      declare
         Data   : Ada.Streams.Stream_Element_Array (42 .. 41);
         Result : Adapter.Observation;
      begin
         Adapter.Parse (Kind, Data, Result);
         if Result.Status /= Adapter.Parse_Error then
            raise Program_Error with "Rust adapter accepted empty input";
         end if;
      end;
   end loop;
end Flyology_JSON.Benchmark_Rust_Tests;
