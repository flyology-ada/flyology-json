--  Copyright (c) 2026 Yurii Rashkovskii
--  SPDX-License-Identifier: MIT OR Apache-2.0

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

   function C_Prepare_Write
     (Input    : System.Address;
      Length   : Interfaces.Unsigned_64;
      Prepared : access System.Address) return Interfaces.Integer_32
   with Import,
        Convention    => C,
        External_Name => "flyology_json_bench_rapidjson_prepare_write";

   function C_Write
     (Prepared    : System.Address;
      Observation : access C_Write_Observation) return Interfaces.Integer_32
   with Import,
        Convention    => C,
        External_Name => "flyology_json_bench_rapidjson_write_dom";

   function C_Check_Write
     (Prepared        : System.Address;
      Expected        : System.Address;
      Expected_Length : Interfaces.Unsigned_64;
      Observation     : access C_Write_Observation;
      Matches         : access Interfaces.Integer_32) return Interfaces.Integer_32
   with Import,
        Convention    => C,
        External_Name => "flyology_json_bench_rapidjson_check_write";

   procedure C_Release_Write (Prepared : System.Address)
   with Import,
        Convention    => C,
        External_Name => "flyology_json_bench_rapidjson_release_write";

   use type Interfaces.Integer_32;
   use type System.Address;

   function Write_Status_From_C (Value : Interfaces.Integer_32) return Write_Status is
   begin
      case Value is
         when 0 =>
            return Write_Succeeded;
         when 1 =>
            return Write_Invalid_Argument;
         when 2 =>
            return Write_Rejected;
         when 3 =>
            return Write_Allocation_Failure;
         when others =>
            return Write_Internal_Error;
      end case;
   end Write_Status_From_C;

   procedure Publish_Write
     (Status      : Write_Status;
      C_Result    : C_Write_Observation;
      Observation : out Write_Observation) is
   begin
      if Status = Write_Succeeded then
         Observation :=
           (Status        => Status,
            Output_Octets => C_Result.Output_Octets,
            Checksum      => C_Result.Checksum);
      else
         Observation := (Status => Status, others => 0);
      end if;
   end Publish_Write;

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

   function Is_Prepared (Context : Prepared_Document) return Boolean
   is (Context.Value /= System.Null_Address);

   procedure Release (Context : in out Prepared_Document) is
      Value : constant System.Address := Context.Value;
   begin
      if Value /= System.Null_Address then
         Context.Value := System.Null_Address;
         C_Release_Write (Value);
      end if;
   end Release;

   procedure Prepare_Write
     (Data    : Ada.Streams.Stream_Element_Array;
      Context : in out Prepared_Document;
      Status  : out Parse_Status)
   is
      Dummy   : aliased Ada.Streams.Stream_Element := 0;
      Address : constant System.Address :=
        (if Data'Length = 0 then Dummy'Address else Data (Data'First)'Address);
      Value   : aliased System.Address := System.Null_Address;
   begin
      Release (Context);
      Status :=
        Status_From_C
          (C_Prepare_Write
             (Input    => Address,
              Length   => Interfaces.Unsigned_64 (Data'Length),
              Prepared => Value'Access));
      if Status = Accepted then
         Context.Value := Value;
      end if;
   end Prepare_Write;

   procedure Write
     (Context     : Prepared_Document;
      Observation : out Write_Observation)
   is
      C_Result : aliased C_Write_Observation := (others => 0);
      Status   : Write_Status;
   begin
      Status := Write_Status_From_C (C_Write (Context.Value, C_Result'Access));
      Publish_Write (Status, C_Result, Observation);
   end Write;

   procedure Check_Write_Output
     (Context     : Prepared_Document;
      Expected    : Ada.Streams.Stream_Element_Array;
      Observation : out Write_Observation;
      Matches     : out Boolean)
   is
      Dummy     : aliased Ada.Streams.Stream_Element := 0;
      Address   : constant System.Address :=
        (if Expected'Length = 0 then Dummy'Address else Expected (Expected'First)'Address);
      C_Result  : aliased C_Write_Observation := (others => 0);
      C_Matches : aliased Interfaces.Integer_32 := 0;
      Status    : Write_Status;
   begin
      Status :=
        Write_Status_From_C
          (C_Check_Write
             (Prepared        => Context.Value,
              Expected        => Address,
              Expected_Length => Interfaces.Unsigned_64 (Expected'Length),
              Observation     => C_Result'Access,
              Matches         => C_Matches'Access));
      Publish_Write (Status, C_Result, Observation);
      Matches := Status = Write_Succeeded and then C_Matches = 1;
   end Check_Write_Output;

end Flyology_JSON.Benchmark_CPP.Rapidjson;
