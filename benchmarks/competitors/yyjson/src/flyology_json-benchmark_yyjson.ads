--  Copyright (c) 2026 Yurii Rashkovskii
--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Streams;
with Interfaces;
with Interfaces.C;
with System;

package Flyology_JSON.Benchmark_YYJSON is

   type Parse_Status is (Accepted, Rejected, Allocation_Failed);

   type Parse_Observation is record
      Status      : Parse_Status;
      Error_Code  : Interfaces.Unsigned_32;
      Error_Byte  : Interfaces.Unsigned_64;
      Read_Octets : Interfaces.Unsigned_64;
      Value_Count : Interfaces.Unsigned_64;
      Checksum    : Interfaces.Unsigned_64;
   end record;

   procedure Parse
     (Data        : Ada.Streams.Stream_Element_Array;
      Observation : out Parse_Observation);

private
   subtype C_Size is Interfaces.C.size_t;

   type Read_Error is record
      Code     : Interfaces.C.unsigned;
      Message  : System.Address;
      Position : C_Size;
   end record
   with Convention => C;

   type Document is record
      Root              : System.Address;
      Allocator_Malloc  : System.Address;
      Allocator_Realloc : System.Address;
      Allocator_Free    : System.Address;
      Allocator_Context : System.Address;
      Data_Read         : C_Size;
      Values_Read       : C_Size;
      String_Pool       : System.Address;
   end record
   with Convention => C;

   type Document_Access is access all Document
   with Convention => C;

   function Read_Options
     (Data      : System.Address;
      Length    : C_Size;
      Flags     : Interfaces.C.unsigned;
      Allocator : System.Address;
      Error     : access Read_Error) return Document_Access
   with Import, Convention => C, External_Name => "yyjson_read_opts";

   procedure Free_Document (Value : Document_Access)
   with Import,
        Convention    => C,
        External_Name => "flyology_bench_yyjson_doc_free";

   --  Assigned by yyjson 0.12.0's public yyjson_read_code definition.
   Memory_Allocation_Error : constant Interfaces.C.unsigned := 2;

end Flyology_JSON.Benchmark_YYJSON;
