--  Copyright (c) 2026 Yurii Rashkovskii
--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Flyology_JSON.Benchmark_YYJSON is

   use type Interfaces.C.unsigned;
   use type Interfaces.Unsigned_64;

   subtype U32 is Interfaces.Unsigned_32;
   subtype U64 is Interfaces.Unsigned_64;

   procedure Parse
     (Data        : Ada.Streams.Stream_Element_Array;
      Observation : out Parse_Observation) is
      Error       : aliased Read_Error :=
        (Code => 0, Message => System.Null_Address, Position => 0);
      Data_Address : constant System.Address :=
        (if Data'Length = 0 then System.Null_Address else Data (Data'First)'Address);
      Value       : Document_Access;
   begin
      Observation :=
        (Status      => Rejected,
         Error_Code  => 0,
         Error_Byte  => 0,
         Read_Octets => 0,
         Value_Count => 0,
         Checksum    => 0);

      Value :=
        Read_Options
          (Data      => Data_Address,
           Length    => C_Size (Data'Length),
           Flags     => 0,
           Allocator => System.Null_Address,
           Error     => Error'Access);

      if Value = null then
         Observation.Status :=
           (if Error.Code = Memory_Allocation_Error then Allocation_Failed else Rejected);
         Observation.Error_Code := U32 (Error.Code);
         Observation.Error_Byte := U64 (Error.Position);
         Observation.Checksum :=
           U64 (Error.Code) * 16#9E37_79B1# xor U64 (Error.Position);
         return;
      end if;

      begin
         Observation.Status := Accepted;
         Observation.Read_Octets := U64 (Value.Data_Read);
         Observation.Value_Count := U64 (Value.Values_Read);
         Observation.Checksum :=
           (Observation.Read_Octets * 16#9E37_79B1#)
           xor (Observation.Value_Count * 16#85EB_CA77#)
           xor U64 (Data'Length);
      exception
         when others =>
            Free_Document (Value);
            raise;
      end;

      Free_Document (Value);
   end Parse;

end Flyology_JSON.Benchmark_YYJSON;
