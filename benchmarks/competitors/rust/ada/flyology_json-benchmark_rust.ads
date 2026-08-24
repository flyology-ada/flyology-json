--  Copyright (c) 2026 Yurii Rashkovskii
--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Streams;
with Interfaces;

package Flyology_JSON.Benchmark_Rust is

   type Implementation is (Serde_JSON, Sonic_RS, SIMD_JSON);

   type Parse_Status is
     (Success,
      Invalid_Argument,
      Parse_Error,
      Foreign_Panic,
      Unknown_Foreign_Status);

   type Observation is record
      Status   : Parse_Status;
      Checksum : Interfaces.Unsigned_64;
      Items    : Ada.Streams.Stream_Element_Count;
   end record;

   procedure Parse
     (Using  : Implementation;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Observation);

end Flyology_JSON.Benchmark_Rust;
