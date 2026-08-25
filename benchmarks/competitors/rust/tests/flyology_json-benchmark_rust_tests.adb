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
   use type Adapter.Write_Status;
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

   for Kind in Adapter.Serde_JSON .. Adapter.Sonic_RS loop
      declare
         Data    : constant Ada.Streams.Stream_Element_Array := Octets (Valid_Text, -29);
         Context : Adapter.Prepared_Document;
         Result  : Adapter.Write_Observation;
         Matches : Boolean;
      begin
         Adapter.Prepare_Write (Kind, Data, Context, Result);
         if Result.Status /= Adapter.Write_Succeeded or else not Adapter.Is_Prepared (Context) then
            raise Program_Error with "Rust writer preparation failed";
         end if;
         Adapter.Check_Write_Output (Context, Data, Result, Matches);
         if Result.Status /= Adapter.Write_Succeeded
           or else not Matches
           or else Result.Output_Octets /= Data'Length
         then
            raise Program_Error with "Rust writer exact-output preflight failed";
         end if;
         Adapter.Write (Context, Result);
         if Result.Status /= Adapter.Write_Succeeded
           or else Result.Output_Octets /= Data'Length
           or else Result.Checksum = 0
         then
            raise Program_Error with "Rust writer observation failed";
         end if;
         Adapter.Release (Context);
         Adapter.Release (Context);
         if Adapter.Is_Prepared (Context) then
            raise Program_Error with "Rust writer release retained context";
         end if;
      exception
         when others =>
            Adapter.Release (Context);
            raise;
      end;
   end loop;

   declare
      Data    : constant Ada.Streams.Stream_Element_Array := Octets (Valid_Text, 13);
      Context : Adapter.Prepared_Document;
      Result  : Adapter.Write_Observation;
   begin
      Adapter.Prepare_Write (Adapter.SIMD_JSON, Data, Context, Result);
      if Result.Status /= Adapter.Write_Unsupported or else Adapter.Is_Prepared (Context) then
         raise Program_Error with "simd-json writer lane was not explicitly unsupported";
      end if;
   end;
end Flyology_JSON.Benchmark_Rust_Tests;
