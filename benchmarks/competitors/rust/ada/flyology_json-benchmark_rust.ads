--  Copyright (c) 2026 Yurii Rashkovskii
--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Streams;
with Interfaces;
with System;

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

   type Write_Status is
     (Write_Succeeded,
      Write_Invalid_Argument,
      Write_Parse_Error,
      Write_Foreign_Panic,
      Write_Error,
      Write_Unsupported,
      Write_Unknown_Foreign_Status);

   type Write_Observation is record
      Status        : Write_Status;
      Checksum      : Interfaces.Unsigned_64;
      Output_Octets : Ada.Streams.Stream_Element_Count;
   end record;

   --  Prepared_Document owns a Rust allocation after a successful Prepare_Write.
   --  Ownership is manual: this benchmark-only type is limited but not controlled,
   --  so every prepared value must be passed to Release, including on exceptional
   --  paths. Letting a prepared value leave scope without Release leaks that
   --  allocation. Release consumes the ownership and reports cleanup status.
   type Prepared_Document is limited private;

   procedure Prepare_Write
     (Using  : Implementation;
      Data   : Ada.Streams.Stream_Element_Array;
      Context : in out Prepared_Document;
      Result : out Write_Observation);

   procedure Write
     (Context : Prepared_Document;
      Result  : out Write_Observation);

   procedure Check_Write_Output
     (Context  : Prepared_Document;
      Expected : Ada.Streams.Stream_Element_Array;
      Result   : out Write_Observation;
      Matches  : out Boolean);

   procedure Release
     (Context : in out Prepared_Document;
      Status  : out Write_Status);

   function Is_Prepared (Context : Prepared_Document) return Boolean;

private
   type Prepared_Document is limited record
      Using  : Implementation := Serde_JSON;
      Handle : System.Address := System.Null_Address;
   end record;

end Flyology_JSON.Benchmark_Rust;
