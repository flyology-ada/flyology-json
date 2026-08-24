--  Copyright (c) 2026 Yurii Rashkovskii
--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Flyology_JSON.Benchmark_CPP is

   function Status_From_C (Value : Interfaces.Integer_32) return Parse_Status is
   begin
      case Value is
         when 0 =>
            return Accepted;
         when 1 =>
            return Invalid_Argument;
         when 2 =>
            return Parse_Error;
         when 3 =>
            return Allocation_Failure;
         when others =>
            return Internal_Error;
      end case;
   end Status_From_C;

   procedure Publish
     (Status      : Parse_Status;
      C_Result    : C_Observation;
      Observation : out Parse_Observation) is
   begin
      if Status = Accepted then
         Observation :=
           (Status            => Status,
            Checksum          => C_Result.Checksum,
            Event_Count       => C_Result.Event_Count,
            Scalar_Count      => C_Result.Scalar_Count,
            Member_Name_Count => C_Result.Member_Name_Count,
            Input_Bytes       => C_Result.Input_Bytes);
      else
         Observation := (Status => Status, others => 0);
      end if;
   end Publish;

end Flyology_JSON.Benchmark_CPP;
