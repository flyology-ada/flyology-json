--  Copyright (c) 2026 Yurii Rashkovskii
--  SPDX-License-Identifier: MIT OR Apache-2.0

with Interfaces;
with System;

package body Flyology_JSON.Benchmark_CPP.Rapidjson is

   function C_Parse_DOM
     (Input       : System.Address;
      Length      : Interfaces.Unsigned_64;
      Observation : access C_Observation) return Interfaces.Integer_32
   with Import,
        Convention    => C,
        External_Name => "flyology_json_bench_rapidjson_dom";

   function C_Parse_Events
     (Input       : System.Address;
      Length      : Interfaces.Unsigned_64;
      Observation : access C_Observation) return Interfaces.Integer_32
   with Import,
        Convention    => C,
        External_Name => "flyology_json_bench_rapidjson_events";

   procedure Parse_DOM
     (Data        : Ada.Streams.Stream_Element_Array;
      Observation : out Parse_Observation) is
      Dummy    : aliased Ada.Streams.Stream_Element := 0;
      Address  : constant System.Address :=
        (if Data'Length = 0 then Dummy'Address else Data (Data'First)'Address);
      C_Result : aliased C_Observation := (others => 0);
      Status   : Parse_Status;
   begin
      Status :=
        Status_From_C
          (C_Parse_DOM
             (Input       => Address,
              Length      => Interfaces.Unsigned_64 (Data'Length),
              Observation => C_Result'Access));
      Publish (Status, C_Result, Observation);
   end Parse_DOM;

   procedure Parse_Events
     (Data        : Ada.Streams.Stream_Element_Array;
      Observation : out Parse_Observation) is
      Dummy    : aliased Ada.Streams.Stream_Element := 0;
      Address  : constant System.Address :=
        (if Data'Length = 0 then Dummy'Address else Data (Data'First)'Address);
      C_Result : aliased C_Observation := (others => 0);
      Status   : Parse_Status;
   begin
      Status :=
        Status_From_C
          (C_Parse_Events
             (Input       => Address,
              Length      => Interfaces.Unsigned_64 (Data'Length),
              Observation => C_Result'Access));
      Publish (Status, C_Result, Observation);
   end Parse_Events;

end Flyology_JSON.Benchmark_CPP.Rapidjson;
