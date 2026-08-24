--  Copyright (c) 2026 Yurii Rashkovskii
--  SPDX-License-Identifier: MIT OR Apache-2.0

with System;

package body Flyology_JSON.Benchmark_CPP.Simdjson is

   function C_Padding return Interfaces.Unsigned_64
   with Import,
        Convention    => C,
        External_Name => "flyology_json_bench_simdjson_padding";

   function C_Parse_DOM
     (Input       : System.Address;
      Length      : Interfaces.Unsigned_64;
      Capacity    : Interfaces.Unsigned_64;
      Observation : access C_Observation) return Interfaces.Integer_32
   with Import,
        Convention    => C,
        External_Name => "flyology_json_bench_simdjson_dom";

   function Required_Padding return Interfaces.Unsigned_64 is (C_Padding);

   procedure Parse_DOM
     (Storage         : Ada.Streams.Stream_Element_Array;
      Document_Length : Interfaces.Unsigned_64;
      Observation     : out Parse_Observation) is
      use type Interfaces.Unsigned_64;

      Capacity : constant Interfaces.Unsigned_64 :=
        Interfaces.Unsigned_64 (Storage'Length);
      Padding  : constant Interfaces.Unsigned_64 := Required_Padding;
      C_Result : aliased C_Observation := (others => 0);
      Raw      : Interfaces.Integer_32;
      Status   : Parse_Status;
   begin
      if Storage'Length = 0
        or else Document_Length > Capacity
        or else Capacity - Document_Length < Padding
      then
         Publish (Invalid_Argument, C_Result, Observation);
         return;
      end if;

      Raw :=
        C_Parse_DOM
          (Input       => Storage (Storage'First)'Address,
           Length      => Document_Length,
           Capacity    => Capacity,
           Observation => C_Result'Access);
      Status := Status_From_C (Raw);
      Publish (Status, C_Result, Observation);
   end Parse_DOM;

end Flyology_JSON.Benchmark_CPP.Simdjson;
