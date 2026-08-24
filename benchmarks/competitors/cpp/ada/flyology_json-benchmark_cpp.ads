--  Copyright (c) 2026 Yurii Rashkovskii
--  SPDX-License-Identifier: MIT OR Apache-2.0

with Interfaces;

package Flyology_JSON.Benchmark_CPP is

   type Parse_Status is
     (Accepted,
      Invalid_Argument,
      Parse_Error,
      Allocation_Failure,
      Internal_Error);

   type Parse_Observation is record
      Status            : Parse_Status := Invalid_Argument;
      Checksum          : Interfaces.Unsigned_64 := 0;
      Event_Count       : Interfaces.Unsigned_64 := 0;
      Scalar_Count      : Interfaces.Unsigned_64 := 0;
      Member_Name_Count : Interfaces.Unsigned_64 := 0;
      Input_Bytes       : Interfaces.Unsigned_64 := 0;
   end record;

private
   type C_Observation is record
      Checksum          : Interfaces.Unsigned_64;
      Event_Count       : Interfaces.Unsigned_64;
      Scalar_Count      : Interfaces.Unsigned_64;
      Member_Name_Count : Interfaces.Unsigned_64;
      Input_Bytes       : Interfaces.Unsigned_64;
   end record
   with Convention => C;

   function Status_From_C (Value : Interfaces.Integer_32) return Parse_Status;

   procedure Publish
     (Status      : Parse_Status;
      C_Result    : C_Observation;
      Observation : out Parse_Observation);

end Flyology_JSON.Benchmark_CPP;
