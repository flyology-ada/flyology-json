--  Copyright (c) 2026 Yurii Rashkovskii
--  SPDX-License-Identifier: MIT OR Apache-2.0

with Interfaces.C;

package body Flyology_JSON.Benchmark_Rust is

   use type Interfaces.C.size_t;
   use type Interfaces.C.int;
   use type System.Address;

   subtype C_Status is Interfaces.C.int;
   subtype C_Size is Interfaces.C.size_t;
   subtype U64 is Interfaces.Unsigned_64;

   pragma Compile_Time_Error
     (System.Storage_Unit /= 8, "Rust benchmark ABI requires 8-bit storage units");
   pragma Compile_Time_Error
     (Ada.Streams.Stream_Element'Size /= 8,
      "Rust benchmark ABI requires 8-bit stream elements");
   pragma Compile_Time_Error
     (C_Status'Size /= 32, "Rust benchmark ABI requires a 32-bit C int");
   pragma Compile_Time_Error
     (U64'Size /= 64, "Rust benchmark ABI requires a 64-bit unsigned integer");
   pragma Compile_Time_Error
     (C_Size'Size /= System.Address'Size,
      "Rust benchmark ABI requires pointer-sized C size_t");
   pragma Compile_Time_Error
     (C_Size'Size < Ada.Streams.Stream_Element_Count'Size,
      "Rust benchmark ABI size_t cannot represent Ada array lengths");

   function Serde_JSON_Traverse
     (Input    : System.Address;
      Length   : C_Size;
      Checksum : access U64;
      Items    : access C_Size) return C_Status
   with Import,
        Convention    => C,
        External_Name => "flyology_json_bench_serde_json_traverse";

   function Sonic_RS_Traverse
     (Input    : System.Address;
      Length   : C_Size;
      Checksum : access U64;
      Items    : access C_Size) return C_Status
   with Import,
        Convention    => C,
        External_Name => "flyology_json_bench_sonic_rs_traverse";

   function SIMD_JSON_Traverse
     (Input    : System.Address;
      Length   : C_Size;
      Checksum : access U64;
      Items    : access C_Size) return C_Status
   with Import,
        Convention    => C,
        External_Name => "flyology_json_bench_simd_json_traverse";

   function Serde_JSON_Prepare_Write
     (Input : System.Address; Length : C_Size; Context : access System.Address) return C_Status
   with Import, Convention => C,
        External_Name => "flyology_json_bench_serde_json_prepare_write";
   function Sonic_RS_Prepare_Write
     (Input : System.Address; Length : C_Size; Context : access System.Address) return C_Status
   with Import, Convention => C,
        External_Name => "flyology_json_bench_sonic_rs_prepare_write";

   function Serde_JSON_Write
     (Context : System.Address; Checksum : access U64; Length : access C_Size) return C_Status
   with Import, Convention => C, External_Name => "flyology_json_bench_serde_json_write";
   function Sonic_RS_Write
     (Context : System.Address; Checksum : access U64; Length : access C_Size) return C_Status
   with Import, Convention => C, External_Name => "flyology_json_bench_sonic_rs_write";

   function Serde_JSON_Check_Write
     (Context : System.Address; Expected : System.Address; Expected_Length : C_Size;
      Checksum : access U64; Length : access C_Size; Matches : access C_Status) return C_Status
   with Import, Convention => C,
        External_Name => "flyology_json_bench_serde_json_check_write";
   function Sonic_RS_Check_Write
     (Context : System.Address; Expected : System.Address; Expected_Length : C_Size;
      Checksum : access U64; Length : access C_Size; Matches : access C_Status) return C_Status
   with Import, Convention => C,
        External_Name => "flyology_json_bench_sonic_rs_check_write";

   function Serde_JSON_Release_Write (Context : System.Address) return C_Status
   with Import, Convention => C,
        External_Name => "flyology_json_bench_serde_json_release_write";
   function Sonic_RS_Release_Write (Context : System.Address) return C_Status
   with Import, Convention => C,
        External_Name => "flyology_json_bench_sonic_rs_release_write";

   function To_Status (Value : C_Status) return Parse_Status is
     (case Value is
         when 0      => Success,
         when 1      => Invalid_Argument,
         when 2      => Parse_Error,
         when 3      => Foreign_Panic,
         when others => Unknown_Foreign_Status);

   procedure Parse
     (Using  : Implementation;
      Data   : Ada.Streams.Stream_Element_Array;
      Result : out Observation) is
      Foreign_Checksum : aliased U64 := 0;
      Foreign_Items    : aliased C_Size := 0;
      Foreign_Status   : C_Status;
   begin
      case Using is
         when Serde_JSON =>
            Foreign_Status :=
              Serde_JSON_Traverse
                (Data'Address,
                 C_Size (Data'Length),
                 Foreign_Checksum'Access,
                 Foreign_Items'Access);
         when Sonic_RS =>
            Foreign_Status :=
              Sonic_RS_Traverse
                (Data'Address,
                 C_Size (Data'Length),
                 Foreign_Checksum'Access,
                 Foreign_Items'Access);
         when SIMD_JSON =>
            Foreign_Status :=
              SIMD_JSON_Traverse
                (Data'Address,
                 C_Size (Data'Length),
                 Foreign_Checksum'Access,
                 Foreign_Items'Access);
      end case;

      if Foreign_Items > C_Size (Ada.Streams.Stream_Element_Count'Last) then
         Result :=
           (Status   => Unknown_Foreign_Status,
            Checksum => 0,
            Items    => 0);
      else
         Result :=
           (Status   => To_Status (Foreign_Status),
            Checksum => Foreign_Checksum,
            Items    => Ada.Streams.Stream_Element_Count (Foreign_Items));
      end if;
   end Parse;

   function Is_Prepared (Context : Prepared_Document) return Boolean is
     (Context.Handle /= System.Null_Address);

   function To_Write_Status (Value : C_Status) return Write_Status is
     (case Value is
         when 0      => Write_Succeeded,
         when 1      => Write_Invalid_Argument,
         when 2      => Write_Parse_Error,
         when 3      => Write_Foreign_Panic,
         when 4      => Write_Error,
         when others => Write_Unknown_Foreign_Status);

   procedure Set_Write_Result
     (Status : C_Status; Checksum : U64; Length : C_Size; Result : out Write_Observation) is
   begin
      if Length > C_Size (Ada.Streams.Stream_Element_Count'Last) then
         Result := (Status => Write_Unknown_Foreign_Status, Checksum => 0, Output_Octets => 0);
      else
         Result :=
           (Status        => To_Write_Status (Status),
            Checksum      => Checksum,
            Output_Octets => Ada.Streams.Stream_Element_Count (Length));
      end if;
   end Set_Write_Result;

   procedure Release (Context : in out Prepared_Document) is
      Handle : constant System.Address := Context.Handle;
      Ignored : C_Status;
   begin
      if Handle /= System.Null_Address then
         Context.Handle := System.Null_Address;
         case Context.Using is
            when Serde_JSON => Ignored := Serde_JSON_Release_Write (Handle);
            when Sonic_RS   => Ignored := Sonic_RS_Release_Write (Handle);
            when SIMD_JSON  => null;
         end case;
      end if;
   end Release;

   procedure Prepare_Write
     (Using  : Implementation;
      Data   : Ada.Streams.Stream_Element_Array;
      Context : in out Prepared_Document;
      Result : out Write_Observation)
   is
      Status : C_Status;
      Handle : aliased System.Address := System.Null_Address;
      Data_Address : constant System.Address :=
        (if Data'Length = 0 then System.Null_Address else Data (Data'First)'Address);
   begin
      Release (Context);
      if Using = SIMD_JSON then
         Result := (Status => Write_Unsupported, Checksum => 0, Output_Octets => 0);
         return;
      end if;
      Status :=
        (case Using is
            when Serde_JSON =>
              Serde_JSON_Prepare_Write (Data_Address, C_Size (Data'Length), Handle'Access),
            when Sonic_RS =>
              Sonic_RS_Prepare_Write (Data_Address, C_Size (Data'Length), Handle'Access),
            when SIMD_JSON => 1);
      Set_Write_Result (Status, 0, 0, Result);
      if Status = 0 and then Handle = System.Null_Address then
         Result := (Status => Write_Unknown_Foreign_Status, Checksum => 0, Output_Octets => 0);
      elsif Status = 0 then
         Context.Using := Using;
         Context.Handle := Handle;
      end if;
   end Prepare_Write;

   procedure Write
     (Context : Prepared_Document;
      Result  : out Write_Observation)
   is
      Checksum : aliased U64 := 0;
      Length   : aliased C_Size := 0;
      Status   : C_Status;
   begin
      if not Is_Prepared (Context) then
         Result := (Status => Write_Invalid_Argument, Checksum => 0, Output_Octets => 0);
         return;
      end if;
      Status :=
        (case Context.Using is
            when Serde_JSON => Serde_JSON_Write (Context.Handle, Checksum'Access, Length'Access),
            when Sonic_RS => Sonic_RS_Write (Context.Handle, Checksum'Access, Length'Access),
            when SIMD_JSON => 1);
      Set_Write_Result (Status, Checksum, Length, Result);
   end Write;

   procedure Check_Write_Output
     (Context  : Prepared_Document;
      Expected : Ada.Streams.Stream_Element_Array;
      Result   : out Write_Observation;
      Matches  : out Boolean)
   is
      Checksum : aliased U64 := 0;
      Length   : aliased C_Size := 0;
      Match    : aliased C_Status := 0;
      Status   : C_Status;
      Expected_Address : constant System.Address :=
        (if Expected'Length = 0 then System.Null_Address else Expected (Expected'First)'Address);
   begin
      if not Is_Prepared (Context) then
         Result := (Status => Write_Invalid_Argument, Checksum => 0, Output_Octets => 0);
         Matches := False;
         return;
      end if;
      Status :=
        (case Context.Using is
            when Serde_JSON =>
              Serde_JSON_Check_Write
                (Context.Handle, Expected_Address, C_Size (Expected'Length),
                 Checksum'Access, Length'Access, Match'Access),
            when Sonic_RS =>
              Sonic_RS_Check_Write
                (Context.Handle, Expected_Address, C_Size (Expected'Length),
                 Checksum'Access, Length'Access, Match'Access),
            when SIMD_JSON => 1);
      Set_Write_Result (Status, Checksum, Length, Result);
      Matches := Status = 0 and then Match = 1;
   end Check_Write_Output;

end Flyology_JSON.Benchmark_Rust;
