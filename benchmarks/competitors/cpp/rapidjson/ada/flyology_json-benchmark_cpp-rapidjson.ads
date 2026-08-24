--  Copyright (c) 2026 Yurii Rashkovskii
--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Streams;

package Flyology_JSON.Benchmark_CPP.Rapidjson is

   procedure Parse_DOM
     (Data        : Ada.Streams.Stream_Element_Array;
      Observation : out Parse_Observation);

   procedure Parse_Events
     (Data        : Ada.Streams.Stream_Element_Array;
      Observation : out Parse_Observation);

end Flyology_JSON.Benchmark_CPP.Rapidjson;
