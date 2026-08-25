with Ada.Environment_Variables;
with Ada.Streams;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology_Bench;
with Flyology_Bench.Reporters;
with Flyology_JSON.Benchmark_Rust;
with Interfaces;

procedure Flyology_JSON.Benchmark_Rust_Writer_Benchmark is
   package Rust renames Flyology_JSON.Benchmark_Rust;
   package Unbounded renames Ada.Strings.Unbounded;
   use type Ada.Streams.Stream_Element_Count;
   use type Flyology_Bench.Iteration_Count;
   use type Interfaces.Unsigned_64;
   use type Rust.Write_Status;

   subtype Count is Ada.Streams.Stream_Element_Count;
   subtype Offset is Ada.Streams.Stream_Element_Offset;
   subtype U64 is Interfaces.Unsigned_64;
   subtype Writer_Implementation is Rust.Implementation range Rust.Serde_JSON .. Rust.Sonic_RS;
   type Octet_Array_Access is access all Ada.Streams.Stream_Element_Array;
   type Context_Access is access all Rust.Prepared_Document;
   type Fixture_Kind is (Large_Raw_String, Nested_Structures);
   type Fixture is record
      Name : Unbounded.Unbounded_String;
      Expected : Octet_Array_Access;
      Logical_Octets : Count;
   end record;

   Large_Raw_Length : constant Count := 1_048_576;
   Structure_Repeats : constant Positive := 4_096;

   function To_Octets (Text : String) return Octet_Array_Access is
      First : constant Offset := -73;
      Value : constant Octet_Array_Access :=
        new Ada.Streams.Stream_Element_Array (First .. First + Offset (Text'Length) - 1);
   begin
      for Index in Text'Range loop
         Value (First + Offset (Index - Text'First)) := Character'Pos (Text (Index));
      end loop;
      return Value;
   end To_Octets;

   function Make_Large return Fixture is
      Data : constant Octet_Array_Access :=
        new Ada.Streams.Stream_Element_Array (19 .. 19 + Offset (Large_Raw_Length) + 1);
   begin
      Data (Data'First) := Character'Pos ('"');
      for Position in Count range 0 .. Large_Raw_Length - 1 loop
         Data (Data'First + 1 + Position) :=
           Ada.Streams.Stream_Element (Character'Pos ('a') + Natural (Position mod 26));
      end loop;
      Data (Data'Last) := Character'Pos ('"');
      return (Unbounded.To_Unbounded_String ("large_raw_string"), Data, Large_Raw_Length);
   end Make_Large;

   function Make_Nested return Fixture is
      Text : Unbounded.Unbounded_String := Unbounded.To_Unbounded_String ("[");
   begin
      for Repetition in 1 .. Structure_Repeats loop
         if Repetition > 1 then Unbounded.Append (Text, ','); end if;
         Unbounded.Append (Text, "{""id"":123456789,""values"":[true,null]}");
      end loop;
      Unbounded.Append (Text, ']');
      return
        (Unbounded.To_Unbounded_String ("nested_structures"),
         To_Octets (Unbounded.To_String (Text)), Count (Structure_Repeats * 25));
   end Make_Nested;

   Fixtures : constant array (Fixture_Kind) of Fixture :=
     [Large_Raw_String => Make_Large, Nested_Structures => Make_Nested];
   Serde_Large, Serde_Nested, Sonic_Large, Sonic_Nested : aliased Rust.Prepared_Document;

   function Context (Using : Writer_Implementation; Kind : Fixture_Kind) return Context_Access is
     (case Using is
         when Rust.Serde_JSON =>
           (case Kind is when Large_Raw_String => Serde_Large'Access,
                         when Nested_Structures => Serde_Nested'Access),
         when Rust.Sonic_RS =>
           (case Kind is when Large_Raw_String => Sonic_Large'Access,
                         when Nested_Structures => Sonic_Nested'Access));
   function Name (Kind : Fixture_Kind) return String is
     (Unbounded.To_String (Fixtures (Kind).Name));
   function Implementation_Name (Using : Writer_Implementation) return String is
     (case Using is when Rust.Serde_JSON => "serde_json", when Rust.Sonic_RS => "sonic-rs");
   function Image (Value : Count) return String is
     (Ada.Strings.Fixed.Trim (Count'Image (Value), Ada.Strings.Both));

   Current_Implementation : Writer_Implementation := Writer_Implementation'First;
   Current_Fixture : Fixture_Kind := Fixture_Kind'First;

   procedure Write_Batch (Iterations : Flyology_Bench.Iteration_Count; Value : out U64) is
      Observation : Rust.Write_Observation;
   begin
      Value := 0;
      for Iteration in Flyology_Bench.Iteration_Count range 1 .. Iterations loop
         Rust.Write (Context (Current_Implementation, Current_Fixture).all, Observation);
         if Observation.Status /= Rust.Write_Succeeded then raise Program_Error; end if;
         Value := Value xor Observation.Checksum xor U64 (Observation.Output_Octets);
      end loop;
   end Write_Batch;
   procedure Measure is new Flyology_Bench.Measure_Result_Batched (Element => U64, Batch => Write_Batch);
   Base_Config : constant Flyology_Bench.Configuration :=
     (Warmup_Time => 0.100, Measurement_Time => 0.500, Maximum_Sampling_Time => 0.0,
      Samples => 50, Minimum_Sample_Time => 0.000_100, Maximum_Iterations => 65_536,
      Subtract_Timer_Cost => False, Metrics => Flyology_Bench.Process_Resource_Metrics,
      Collect_Process_Telemetry => True, others => <>);
   Output_Mode : constant String :=
     Ada.Environment_Variables.Value ("FLYOLOGY_JSON_BENCH_OUTPUT", "terminal");
   Fixture_Selector : constant String :=
     Ada.Environment_Variables.Value ("FLYOLOGY_JSON_BENCH_FIXTURE", "");
   Implementation_Selector : constant String :=
     Ada.Environment_Variables.Value ("FLYOLOGY_JSON_BENCH_IMPLEMENTATION", "");
   Preflight_Only : constant Boolean :=
     Ada.Environment_Variables.Value ("FLYOLOGY_JSON_BENCH_PREFLIGHT_ONLY", "false") = "true";

   procedure Run (Using : Writer_Implementation; Kind : Fixture_Kind) is
      Prepared, Observation : Rust.Write_Observation;
      Matches : Boolean;
      Result : Flyology_Bench.Measurement;
   begin
      Rust.Prepare_Write (Using, Fixtures (Kind).Expected.all, Context (Using, Kind).all, Prepared);
      if Prepared.Status /= Rust.Write_Succeeded then raise Program_Error; end if;
      Rust.Check_Write_Output
        (Context (Using, Kind).all, Fixtures (Kind).Expected.all, Observation, Matches);
      if Observation.Status /= Rust.Write_Succeeded or else not Matches then raise Program_Error; end if;
      Current_Implementation := Using;
      Current_Fixture := Kind;
      declare
         Benchmark_Name : constant String :=
           "comparison/lane=write_dom/implementation=" & Implementation_Name (Using)
           & "/fixture=" & Name (Kind)
           & "/logical_octets=" & Image (Fixtures (Kind).Logical_Octets)
           & "/output_octets=" & Image (Observation.Output_Octets)
           & "/output_checksum=fnv1a64-timed/output_allocation=per_operation"
           & "/dom_preparation=outside_timing";
         Config : constant Flyology_Bench.Configuration :=
           (if Output_Mode = "terminal"
            then Flyology_Bench.Reporters.Terminal_Mode (Base_Config, Benchmark_Name)
            else Base_Config);
      begin
         if not Preflight_Only then
            Measure (Config, Result);
            if Output_Mode = "terminal" then
               Flyology_Bench.Reporters.Put_Console (Benchmark_Name, Result);
               Ada.Text_IO.Put_Line
                 ("  median output throughput:"
                  & Long_Float'Image
                      (Long_Float (Observation.Output_Octets) * 1_000_000_000.0
                       / Flyology_Bench.Median_Nanoseconds (Result) / 1_048_576.0)
                  & " MiB/s");
            elsif Output_Mode = "csv" then Flyology_Bench.Reporters.Put_CSV (Benchmark_Name, Result);
            elsif Output_Mode = "metrics_csv" then
               Flyology_Bench.Reporters.Put_Metrics_CSV (Benchmark_Name, Result);
            else Flyology_Bench.Reporters.Put_JSON (Benchmark_Name, Result);
            end if;
         end if;
      end;
      Rust.Release (Context (Using, Kind).all);
   exception
      when others => Rust.Release (Context (Using, Kind).all); raise;
   end Run;
begin
   if Output_Mode not in "terminal" | "csv" | "metrics_csv" | "json" then raise Constraint_Error; end if;
   if Output_Mode = "csv" then Flyology_Bench.Reporters.Put_CSV_Header;
   elsif Output_Mode = "metrics_csv" then Flyology_Bench.Reporters.Put_Metrics_CSV_Header; end if;
   for Using in Writer_Implementation loop
      for Kind in Fixture_Kind loop
         if (Implementation_Selector = "" or else Implementation_Selector = Implementation_Name (Using))
           and then (Fixture_Selector = "" or else Fixture_Selector = Name (Kind))
         then Run (Using, Kind); end if;
      end loop;
   end loop;
end Flyology_JSON.Benchmark_Rust_Writer_Benchmark;
