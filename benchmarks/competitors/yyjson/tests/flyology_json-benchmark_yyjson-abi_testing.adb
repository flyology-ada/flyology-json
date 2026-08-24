--  Copyright (c) 2026 Yurii Rashkovskii
--  SPDX-License-Identifier: MIT OR Apache-2.0

with Interfaces.C;
with System;

package body Flyology_JSON.Benchmark_YYJSON.ABI_Testing is

   use type Interfaces.C.size_t;

   function C_Sizeof_Document return C_Size
   with Import,
        Convention    => C,
        External_Name => "flyology_bench_yyjson_sizeof_document";

   function C_Sizeof_Read_Error return C_Size
   with Import,
        Convention    => C,
        External_Name => "flyology_bench_yyjson_sizeof_read_error";

   function C_Sizeof_Read_Code return C_Size
   with Import,
        Convention    => C,
        External_Name => "flyology_bench_yyjson_sizeof_read_code";

   function C_Offsetof_Data_Read return C_Size
   with Import,
        Convention    => C,
        External_Name => "flyology_bench_yyjson_offsetof_data_read";

   function C_Offsetof_Root return C_Size
   with Import,
        Convention    => C,
        External_Name => "flyology_bench_yyjson_offsetof_root";

   function C_Offsetof_Allocator_Context return C_Size
   with Import,
        Convention    => C,
        External_Name => "flyology_bench_yyjson_offsetof_allocator_context";

   function C_Offsetof_Values_Read return C_Size
   with Import,
        Convention    => C,
        External_Name => "flyology_bench_yyjson_offsetof_values_read";

   function C_Offsetof_Error_Position return C_Size
   with Import,
        Convention    => C,
        External_Name => "flyology_bench_yyjson_offsetof_error_position";

   function C_Offsetof_String_Pool return C_Size
   with Import,
        Convention    => C,
        External_Name => "flyology_bench_yyjson_offsetof_string_pool";

   function C_Offsetof_Error_Code return C_Size
   with Import,
        Convention    => C,
        External_Name => "flyology_bench_yyjson_offsetof_error_code";

   function C_Offsetof_Error_Message return C_Size
   with Import,
        Convention    => C,
        External_Name => "flyology_bench_yyjson_offsetof_error_message";

   function Compatible return Boolean is
      Doc : constant Document :=
        (Root              => System.Null_Address,
         Allocator_Malloc  => System.Null_Address,
         Allocator_Realloc => System.Null_Address,
         Allocator_Free    => System.Null_Address,
         Allocator_Context => System.Null_Address,
         Data_Read         => 0,
         Values_Read       => 0,
         String_Pool       => System.Null_Address);
      Err : constant Read_Error :=
        (Code => 0, Message => System.Null_Address, Position => 0);
   begin
      return
        C_Sizeof_Document = C_Size (Document'Size / System.Storage_Unit)
        and then C_Sizeof_Read_Error = C_Size (Read_Error'Size / System.Storage_Unit)
        and then C_Sizeof_Read_Code =
          C_Size (Interfaces.C.unsigned'Size / System.Storage_Unit)
        and then C_Offsetof_Root = C_Size (Doc.Root'Position)
        and then C_Offsetof_Allocator_Context = C_Size (Doc.Allocator_Context'Position)
        and then C_Offsetof_Data_Read = C_Size (Doc.Data_Read'Position)
        and then C_Offsetof_Values_Read = C_Size (Doc.Values_Read'Position)
        and then C_Offsetof_String_Pool = C_Size (Doc.String_Pool'Position)
        and then C_Offsetof_Error_Code = C_Size (Err.Code'Position)
        and then C_Offsetof_Error_Message = C_Size (Err.Message'Position)
        and then C_Offsetof_Error_Position = C_Size (Err.Position'Position);
   end Compatible;

end Flyology_JSON.Benchmark_YYJSON.ABI_Testing;
