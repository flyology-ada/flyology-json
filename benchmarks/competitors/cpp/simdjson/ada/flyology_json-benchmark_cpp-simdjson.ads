--  Copyright (c) 2026 Yurii Rashkovskii
--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Streams;
with Interfaces;

package Flyology_JSON.Benchmark_CPP.Simdjson is

   function Required_Padding return Interfaces.Unsigned_64;

   procedure Parse_DOM
     (Storage         : Ada.Streams.Stream_Element_Array;
      Document_Length : Interfaces.Unsigned_64;
      Observation     : out Parse_Observation);

end Flyology_JSON.Benchmark_CPP.Simdjson;
