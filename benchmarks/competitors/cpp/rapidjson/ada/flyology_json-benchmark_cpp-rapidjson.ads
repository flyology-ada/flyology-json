--  Copyright (c) 2026 Yurii Rashkovskii
--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Streams;
with Interfaces;
with System;

package Flyology_JSON.Benchmark_CPP.Rapidjson is

   procedure Parse_DOM
     (Data        : Ada.Streams.Stream_Element_Array;
      Observation : out Parse_Observation);

   procedure Parse_Events
     (Data        : Ada.Streams.Stream_Element_Array;
      Observation : out Parse_Observation);

   type Write_Status is
     (Write_Succeeded,
      Write_Invalid_Argument,
      Write_Rejected,
      Write_Allocation_Failure,
      Write_Internal_Error);

   type Write_Observation is record
      Status        : Write_Status := Write_Invalid_Argument;
      Output_Octets : Interfaces.Unsigned_64 := 0;
      Checksum      : Interfaces.Unsigned_64 := 0;
   end record;

   type Prepared_Document is limited private;

   procedure Prepare_Write
     (Data    : Ada.Streams.Stream_Element_Array;
      Context : in out Prepared_Document;
      Status  : out Parse_Status);

   procedure Write
     (Context     : Prepared_Document;
      Observation : out Write_Observation);

   procedure Check_Write_Output
     (Context     : Prepared_Document;
      Expected    : Ada.Streams.Stream_Element_Array;
      Observation : out Write_Observation;
      Matches     : out Boolean);

   procedure Release (Context : in out Prepared_Document);

   function Is_Prepared (Context : Prepared_Document) return Boolean;

private
   type C_Write_Observation is record
      Output_Octets : Interfaces.Unsigned_64;
      Checksum      : Interfaces.Unsigned_64;
   end record
   with Convention => C;

   type Prepared_Document is limited record
      Value : System.Address := System.Null_Address;
   end record;

end Flyology_JSON.Benchmark_CPP.Rapidjson;
