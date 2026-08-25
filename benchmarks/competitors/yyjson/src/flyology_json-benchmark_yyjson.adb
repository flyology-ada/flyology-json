--  Copyright (c) 2026 Yurii Rashkovskii
--  SPDX-License-Identifier: MIT OR Apache-2.0

with System.Address_To_Access_Conversions;
with System.Storage_Elements;

package body Flyology_JSON.Benchmark_YYJSON is

   use type Interfaces.C.unsigned;
   use type Interfaces.C.size_t;
   use type Interfaces.Unsigned_64;
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Offset;
   use type System.Address;
   use type System.Storage_Elements.Storage_Offset;

   subtype U32 is Interfaces.Unsigned_32;
   subtype U64 is Interfaces.Unsigned_64;

   package Unsigned_Char_Conversions is new
     System.Address_To_Access_Conversions (Interfaces.C.unsigned_char);

   function Is_Prepared (Context : Prepared_Document) return Boolean
   is (Context.Value /= null);

   procedure Release (Context : in out Prepared_Document) is
      Value : constant Document_Access := Context.Value;
   begin
      if Value /= null then
         --  Relinquish the Ada-side ownership claim before entering C.  If an
         --  abnormal transfer reaches this benchmark-only boundary, a later
         --  idempotent Release cannot double-free the same document.
         Context.Value := null;
         Free_Document (Value);
      end if;
   end Release;

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

   procedure Prepare_Write
     (Data        : Ada.Streams.Stream_Element_Array;
      Context     : in out Prepared_Document;
      Observation : out Parse_Observation)
   is
      Error        : aliased Read_Error :=
        (Code => 0, Message => System.Null_Address, Position => 0);
      Data_Address : constant System.Address :=
        (if Data'Length = 0 then System.Null_Address else Data (Data'First)'Address);
   begin
      Release (Context);
      Observation :=
        (Status      => Rejected,
         Error_Code  => 0,
         Error_Byte  => 0,
         Read_Octets => 0,
         Value_Count => 0,
         Checksum    => 0);

      Context.Value :=
        Read_Options
          (Data      => Data_Address,
           Length    => C_Size (Data'Length),
           Flags     => 0,
           Allocator => System.Null_Address,
           Error     => Error'Access);

      if Context.Value = null then
         Observation.Status :=
           (if Error.Code = Memory_Allocation_Error then Allocation_Failed else Rejected);
         Observation.Error_Code := U32 (Error.Code);
         Observation.Error_Byte := U64 (Error.Position);
         Observation.Checksum :=
           U64 (Error.Code) * 16#9E37_79B1# xor U64 (Error.Position);
         return;
      end if;

      Observation.Status := Accepted;
      Observation.Read_Octets := U64 (Context.Value.Data_Read);
      Observation.Value_Count := U64 (Context.Value.Values_Read);
      Observation.Checksum :=
        (Observation.Read_Octets * 16#9E37_79B1#)
        xor (Observation.Value_Count * 16#85EB_CA77#)
        xor U64 (Data'Length);
   end Prepare_Write;

   procedure Write_Internal
     (Context     : Prepared_Document;
      Expected    : Ada.Streams.Stream_Element_Array;
      Compare     : Boolean;
      Observation : out Write_Observation;
      Matches     : out Boolean)
   is
      Error         : aliased Write_Error :=
        (Code => 0, Message => System.Null_Address);
      Output_Length : aliased C_Size := 0;
      Output        : System.Address;
   begin
      Observation :=
        (Status        => Write_Rejected,
         Error_Code    => 0,
         Output_Octets => 0,
         Checksum      => 0);
      Matches := False;

      if Context.Value = null then
         Observation.Error_Code := 1;
         return;
      end if;

      Output :=
        Write_Options
          (Value     => Context.Value,
           Flags     => 0,
           Allocator => System.Null_Address,
           Length    => Output_Length'Access,
           Error     => Error'Access);

      if Output = System.Null_Address then
         Observation.Status :=
           (if Error.Code = Memory_Allocation_Error
            then Write_Allocation_Failed
            else Write_Rejected);
         Observation.Error_Code := U32 (Error.Code);
         Observation.Checksum := U64 (Error.Code) * 16#9E37_79B1#;
         return;
      end if;

      begin
         Observation.Status := Write_Succeeded;
         Observation.Output_Octets := U64 (Output_Length);
         Observation.Checksum := 16#CBF2_9CE4_8422_2325#;
         Matches := not Compare or else U64 (Expected'Length) = U64 (Output_Length);

         if Output_Length > 0 then
            for Position in C_Size range 0 .. Output_Length - 1 loop
               declare
                  Byte : constant Interfaces.C.unsigned_char :=
                    Unsigned_Char_Conversions.To_Pointer
                      (Output + System.Storage_Elements.Storage_Offset (Position)).all;
               begin
                  Observation.Checksum :=
                    (Observation.Checksum xor U64 (Byte)) * 16#0000_0100_0000_01B3#;
                  if Compare
                    and then
                      (U64 (Position) >= U64 (Expected'Length)
                       or else
                         Expected
                           (Expected'First
                            + Ada.Streams.Stream_Element_Offset (Position)) /=
                         Ada.Streams.Stream_Element (Byte))
                  then
                     Matches := False;
                  end if;
               end;
            end loop;
         end if;
      exception
         when others =>
            Free_Output (Output);
            raise;
      end;

      Free_Output (Output);
   end Write_Internal;

   procedure Write
     (Context     : Prepared_Document;
      Observation : out Write_Observation)
   is
      Empty   : Ada.Streams.Stream_Element_Array (1 .. 0);
      Ignored : Boolean;
   begin
      Write_Internal (Context, Empty, Compare => False, Observation => Observation, Matches => Ignored);
   end Write;

   procedure Check_Write_Output
     (Context     : Prepared_Document;
      Expected    : Ada.Streams.Stream_Element_Array;
      Observation : out Write_Observation;
      Matches     : out Boolean) is
   begin
      Write_Internal
        (Context,
         Expected,
         Compare     => True,
         Observation => Observation,
         Matches     => Matches);
   end Check_Write_Output;

end Flyology_JSON.Benchmark_YYJSON;
