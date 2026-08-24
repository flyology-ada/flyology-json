--  Copyright (c) 2026 Yurii Rashkovskii
--  SPDX-License-Identifier: MIT OR Apache-2.0

with Interfaces.C;
with System;

package body Flyology_JSON.Benchmark_Rust is

   use type Interfaces.C.size_t;

   subtype C_Status is Interfaces.C.int;
   subtype C_Size is Interfaces.C.size_t;
   subtype U64 is Interfaces.Unsigned_64;

   pragma Compile_Time_Error
     (System.Storage_Unit /= 8, "Rust benchmark ABI requires 8-bit storage units");
   pragma Compile_Time_Error
     (Ada.Streams.Stream_Element'Size /= 8,
      "Rust benchmark ABI requires 8-bit stream elements");
   pragma Compile_Time_Error
     (C_Status'Size /= 32, "Rust benchmark ABI requires a 32-bit C int");
   pragma Compile_Time_Error
     (U64'Size /= 64, "Rust benchmark ABI requires a 64-bit unsigned integer");
   pragma Compile_Time_Error
     (C_Size'Size /= System.Address'Size,
      "Rust benchmark ABI requires pointer-sized C size_t");
   pragma Compile_Time_Error
     (C_Size'Size < Ada.Streams.Stream_Element_Count'Size,
      "Rust benchmark ABI size_t cannot represent Ada array lengths");

   function Serde_JSON_Traverse
     (Input    : System.Address;
      Length   : C_Size;
      Checksum : access U64;
      Items    : access C_Size) return C_Status
   with Import,
        Convention    => C,
        External_Name => "flyology_json_bench_serde_json_traverse";

   function Sonic_RS_Traverse
     (Input    : System.Address;
      Length   : C_Size;
      Checksum : access U64;
      Items    : access C_Size) return C_Status
   with Import,
        Convention    => C,
        External_Name => "flyology_json_bench_sonic_rs_traverse";

   function SIMD_JSON_Traverse
     (Input    : System.Address;
      Length   : C_Size;
      Checksum : access U64;
      Items    : access C_Size) return C_Status
   with Import,
        Convention    => C,
        External_Name => "flyology_json_bench_simd_json_traverse";

   function To_Status (Value : C_Status) return Parse_Status is
     (case Value is
         when 0      => Success,
         when 1      => Invalid_Argument,
         when 2      => Parse_Error,
         when 3      => Foreign_Panic,
         when others => Unknown_Foreign_Status);

   procedure Parse
     (Using  : Implementation;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Observation) is
      Foreign_Checksum : aliased U64 := 0;
      Foreign_Items    : aliased C_Size := 0;
      Foreign_Status   : C_Status;
   begin
      case Using is
         when Serde_JSON =>
            Foreign_Status :=
              Serde_JSON_Traverse
                (Data'Address,
                 C_Size (Data'Length),
                 Foreign_Checksum'Access,
                 Foreign_Items'Access);
         when Sonic_RS =>
            Foreign_Status :=
              Sonic_RS_Traverse
                (Data'Address,
                 C_Size (Data'Length),
                 Foreign_Checksum'Access,
                 Foreign_Items'Access);
         when SIMD_JSON =>
            Foreign_Status :=
              SIMD_JSON_Traverse
                (Data'Address,
                 C_Size (Data'Length),
                 Foreign_Checksum'Access,
                 Foreign_Items'Access);
      end case;

      if Foreign_Items > C_Size (Ada.Streams.Stream_Element_Count'Last) then
         Result :=
           (Status   => Unknown_Foreign_Status,
            Checksum => 0,
            Items    => 0);
      else
         Result :=
           (Status   => To_Status (Foreign_Status),
            Checksum => Foreign_Checksum,
            Items    => Ada.Streams.Stream_Element_Count (Foreign_Items));
      end if;
   end Parse;

end Flyology_JSON.Benchmark_Rust;
