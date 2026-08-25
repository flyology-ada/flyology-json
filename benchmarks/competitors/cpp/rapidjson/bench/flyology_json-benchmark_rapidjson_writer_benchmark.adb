--  Copyright (c) 2026 Yurii Rashkovskii
--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Environment_Variables;
with Ada.Streams;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology_Bench;
with Flyology_Bench.Reporters;
with Flyology_JSON.Benchmark_CPP;
with Flyology_JSON.Benchmark_CPP.Rapidjson;
with Interfaces;

procedure Flyology_JSON.Benchmark_RapidJSON_Writer_Benchmark is
   package RapidJSON renames Flyology_JSON.Benchmark_CPP.Rapidjson;
   package Unbounded renames Ada.Strings.Unbounded;

   use type Ada.Streams.Stream_Element_Count;
   use type Flyology_Bench.Iteration_Count;
   use type Interfaces.Unsigned_64;
   use type Flyology_JSON.Benchmark_CPP.Parse_Status;
   use type RapidJSON.Write_Status;

   subtype Count is Ada.Streams.Stream_Element_Count;
   subtype Offset is Ada.Streams.Stream_Element_Offset;
   subtype U64 is Interfaces.Unsigned_64;

   type Octet_Array_Access is access all Ada.Streams.Stream_Element_Array;
   type Prepared_Access is access all RapidJSON.Prepared_Document;

   type Fixture_Kind is (Large_Raw_String, Nested_Structures);

   type Fixture is record
      Name            : Unbounded.Unbounded_String;
      Expected_Output : Octet_Array_Access;
      Logical_Octets  : Count;
   end record;

   type Fixture_Array is array (Fixture_Kind) of Fixture;

   --  These reproduce the public writer's reviewed benchmark populations;
   --  they are benchmark fixture sizes, not production defaults or limits.
   Large_Raw_Length  : constant Count := 1_048_576;
   Structure_Repeats : constant Positive := 4_096;

   function To_Octets (Text : String) return Octet_Array_Access is
      First  : constant Offset := -73;
      Result : constant Octet_Array_Access :=
        new Ada.Streams.Stream_Element_Array
          (First .. First + Offset (Text'Length) - 1);
   begin
      for Index in Text'Range loop
         Result (First + Offset (Index - Text'First)) := Character'Pos (Text (Index));
      end loop;
      return Result;
   end To_Octets;

   function Make_Large_Raw_String return Fixture is
      Data : constant Octet_Array_Access :=
        new Ada.Streams.Stream_Element_Array
          (19 .. 19 + Offset (Large_Raw_Length) + 1);
   begin
      Data (Data'First) := Character'Pos ('"');
      for Position in Count range 0 .. Large_Raw_Length - 1 loop
         Data (Data'First + 1 + Position) :=
           Ada.Streams.Stream_Element
             (Character'Pos ('a') + Natural (Position mod 26));
      end loop;
      Data (Data'Last) := Character'Pos ('"');
      return
        (Name            => Unbounded.To_Unbounded_String ("large_raw_string"),
         Expected_Output => Data,
         Logical_Octets  => Large_Raw_Length);
   end Make_Large_Raw_String;

   function Make_Nested_Structures return Fixture is
      Text : Unbounded.Unbounded_String := Unbounded.To_Unbounded_String ("[");
   begin
      for Repetition in 1 .. Structure_Repeats loop
         if Repetition > 1 then
            Unbounded.Append (Text, ',');
         end if;
         Unbounded.Append (Text, "{""id"":123456789,""values"":[true,null]}");
      end loop;
      Unbounded.Append (Text, ']');
      return
        (Name            => Unbounded.To_Unbounded_String ("nested_structures"),
         Expected_Output => To_Octets (Unbounded.To_String (Text)),
         Logical_Octets  => Count (Structure_Repeats * 25));
   end Make_Nested_Structures;

   Fixtures : constant Fixture_Array :=
     [Large_Raw_String  => Make_Large_Raw_String,
      Nested_Structures => Make_Nested_Structures];

   Large_Raw_Context : aliased RapidJSON.Prepared_Document;
   Nested_Context    : aliased RapidJSON.Prepared_Document;

   Contexts : constant array (Fixture_Kind) of Prepared_Access :=
     [Large_Raw_String  => Large_Raw_Context'Access,
      Nested_Structures => Nested_Context'Access];

   Current_Fixture : Fixture_Kind := Fixture_Kind'First;

   function Name (Kind : Fixture_Kind) return String
   is (Unbounded.To_String (Fixtures (Kind).Name));

   function Trimmed_Image (Value : Count) return String
   is (Ada.Strings.Fixed.Trim (Count'Image (Value), Ada.Strings.Both));

   procedure Write_Batch
     (Iterations : Flyology_Bench.Iteration_Count;
      Value      : out U64)
   is
      Observation : RapidJSON.Write_Observation;
   begin
      Value := 0;
      for Iteration in Flyology_Bench.Iteration_Count range 1 .. Iterations loop
         RapidJSON.Write (Contexts (Current_Fixture).all, Observation);
         if Observation.Status /= RapidJSON.Write_Succeeded then
            raise Program_Error with "RapidJSON writer rejected its prepared DOM";
         end if;
         Value := Value xor Observation.Checksum xor Observation.Output_Octets;
      end loop;
   end Write_Batch;

   procedure Measure_Writer is new Flyology_Bench.Measure_Result_Batched
     (Element => U64, Batch => Write_Batch);

   Base_Config : constant Flyology_Bench.Configuration :=
     (Warmup_Time               => 0.100,
      Measurement_Time          => 0.500,
      Maximum_Sampling_Time     => 0.0,
      Samples                   => 50,
      Minimum_Sample_Time       => 0.000_100,
      Maximum_Iterations        => 65_536,
      Subtract_Timer_Cost       => False,
      Metrics                   => Flyology_Bench.Process_Resource_Metrics,
      Collect_Process_Telemetry => True,
      others                    => <>);

   Output_Mode : constant String :=
     Ada.Environment_Variables.Value
       ("FLYOLOGY_JSON_BENCH_OUTPUT", Default => "terminal");
   Fixture_Selector : constant String :=
     Ada.Environment_Variables.Value
       ("FLYOLOGY_JSON_BENCH_FIXTURE", Default => "");
   Preflight_Only : constant Boolean :=
     Ada.Environment_Variables.Value
       ("FLYOLOGY_JSON_BENCH_PREFLIGHT_ONLY", Default => "false") = "true";

   function Selected (Kind : Fixture_Kind) return Boolean
   is (Fixture_Selector = "" or else Fixture_Selector = Name (Kind));

   function Known_Fixture return Boolean is
   begin
      if Fixture_Selector = "" then
         return True;
      end if;
      for Kind in Fixture_Kind loop
         if Fixture_Selector = Name (Kind) then
            return True;
         end if;
      end loop;
      return False;
   end Known_Fixture;

   procedure Prepare (Kind : Fixture_Kind) is
      Parse_Result : Flyology_JSON.Benchmark_CPP.Parse_Status;
      Write_Result : RapidJSON.Write_Observation;
      Matches      : Boolean;
   begin
      RapidJSON.Prepare_Write
        (Fixtures (Kind).Expected_Output.all,
         Contexts (Kind).all,
         Parse_Result);
      if Parse_Result /= Flyology_JSON.Benchmark_CPP.Accepted then
         raise Program_Error with "RapidJSON rejected a writer comparison fixture";
      end if;
      RapidJSON.Check_Write_Output
        (Contexts (Kind).all,
         Fixtures (Kind).Expected_Output.all,
         Write_Result,
         Matches);
      if Write_Result.Status /= RapidJSON.Write_Succeeded or else not Matches then
         raise Program_Error with "RapidJSON output policy differs from the comparison fixture";
      end if;
   end Prepare;

   procedure Run (Kind : Fixture_Kind) is
      Observation : RapidJSON.Write_Observation;
      Result      : Flyology_Bench.Measurement;
   begin
      RapidJSON.Write (Contexts (Kind).all, Observation);
      Current_Fixture := Kind;
      declare
         Benchmark_Name : constant String :=
           "comparison/lane=write_dom/implementation=rapidjson/fixture=" & Name (Kind)
           & "/logical_octets=" & Trimmed_Image (Fixtures (Kind).Logical_Octets)
           & "/output_octets=" & Trimmed_Image (Count (Observation.Output_Octets))
           & "/output_checksum=fnv1a64-timed"
           & "/output_allocation=per_operation"
           & "/dom_preparation=outside_timing";
         Config : constant Flyology_Bench.Configuration :=
           (if Output_Mode = "terminal"
            then Flyology_Bench.Reporters.Terminal_Mode (Base_Config, Benchmark_Name)
            else Base_Config);
      begin
         Measure_Writer (Config => Config, Result => Result);
         if Output_Mode = "terminal" then
            Flyology_Bench.Reporters.Put_Console (Benchmark_Name, Result);
            Ada.Text_IO.Put_Line
              ("  median output throughput:"
               & Long_Float'Image
                   (Long_Float (Observation.Output_Octets) * 1_000_000_000.0
                    / Flyology_Bench.Median_Nanoseconds (Result)
                    / 1_048_576.0)
               & " MiB/s");
         elsif Output_Mode = "csv" then
            Flyology_Bench.Reporters.Put_CSV (Benchmark_Name, Result);
         elsif Output_Mode = "metrics_csv" then
            Flyology_Bench.Reporters.Put_Metrics_CSV (Benchmark_Name, Result);
         else
            Flyology_Bench.Reporters.Put_JSON (Benchmark_Name, Result);
         end if;
      end;
   end Run;

begin
   if Output_Mode not in "terminal" | "csv" | "metrics_csv" | "json" then
      raise Constraint_Error with
        "FLYOLOGY_JSON_BENCH_OUTPUT must be terminal, csv, metrics_csv, or json";
   end if;
   if not Known_Fixture then
      raise Constraint_Error with "unknown FLYOLOGY_JSON_BENCH_FIXTURE selector";
   end if;

   if Output_Mode = "csv" then
      Flyology_Bench.Reporters.Put_CSV_Header;
   elsif Output_Mode = "metrics_csv" then
      Flyology_Bench.Reporters.Put_Metrics_CSV_Header;
   end if;

   for Kind in Fixture_Kind loop
      if Selected (Kind) then
         begin
            Prepare (Kind);
            if not Preflight_Only then
               Run (Kind);
            end if;
            RapidJSON.Release (Contexts (Kind).all);
         exception
            when others =>
               RapidJSON.Release (Contexts (Kind).all);
               raise;
         end;
      end if;
   end loop;
end Flyology_JSON.Benchmark_RapidJSON_Writer_Benchmark;
