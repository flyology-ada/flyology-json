--  Copyright (c) 2026 Yurii Rashkovskii
--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Environment_Variables;
with Ada.Streams;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Flyology_Bench;
with Flyology_Bench.Reporters;
with Flyology_JSON.Destinations;
with Flyology_JSON.Errors;
with Flyology_JSON.Profiles;
with Flyology_JSON.Writing;
with Interfaces;
with System;

procedure Flyology_JSON.Writer_Benchmark is
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Streams.Stream_Element;
   use type Flyology_Bench.Iteration_Count;
   use type Flyology_JSON.Errors.Error_Code;
   use type Interfaces.Unsigned_64;

   subtype Count is Ada.Streams.Stream_Element_Count;
   subtype Offset is Ada.Streams.Stream_Element_Offset;
   subtype U64 is Interfaces.Unsigned_64;

   type Octet_Array_Access is access all Ada.Streams.Stream_Element_Array;

   type Fixture_Kind is
     (Small_Null,
      Small_Boolean,
      Small_Number,
      Small_String,
      Large_Raw_String,
      Escape_Heavy_String,
      Number_Heavy_Array,
      Nested_Structures);

   type Fragment_Kind is (Bulk, One_Octet);

   --  These are benchmark population sizes, not production capacities or
   --  defaults.  Fixture data is allocated once before the timed region.
   Large_Raw_Length : constant Count := 1_048_576;
   Escape_Length    : constant Count := 262_144;
   Number_Repeats   : constant Positive := 4_096;
   Structure_Repeats : constant Positive := 4_096;
   Output_Capacity  : constant Count := 2_000_000;

   function To_Octets (Text : String) return Octet_Array_Access is
      First  : constant Offset := 37;
      Result : constant Octet_Array_Access :=
        new Ada.Streams.Stream_Element_Array
          (First .. First + Offset (Text'Length) - 1);
   begin
      for Index in Text'Range loop
         Result (First + Offset (Index - Text'First)) := Character'Pos (Text (Index));
      end loop;
      return Result;
   end To_Octets;

   Small_Number_Data : constant Octet_Array_Access := To_Octets ("-1234567890.125e+42");
   Small_String_Data : constant Octet_Array_Access := To_Octets ("flyology");
   Name_Id           : constant Octet_Array_Access := To_Octets ("id");
   Name_Values       : constant Octet_Array_Access := To_Octets ("values");
   Nested_Number     : constant Octet_Array_Access := To_Octets ("123456789");
   Number_Zero       : constant Octet_Array_Access := To_Octets ("0");
   Number_Negative   : constant Octet_Array_Access := To_Octets ("-1");
   Number_Integer    : constant Octet_Array_Access := To_Octets ("123456789");
   Number_Fraction   : constant Octet_Array_Access := To_Octets ("1.5");
   Number_Exponent   : constant Octet_Array_Access := To_Octets ("6.022e23");
   Number_Small      : constant Octet_Array_Access := To_Octets ("-0.001");

   Large_Raw_Data : constant Octet_Array_Access :=
     new Ada.Streams.Stream_Element_Array
       (101 .. 101 + Offset (Large_Raw_Length) - 1);
   Escape_Data : constant Octet_Array_Access :=
     new Ada.Streams.Stream_Element_Array
       (211 .. 211 + Offset (Escape_Length) - 1);

   type Benchmark_Destination is limited record
      Buffer           : Ada.Streams.Stream_Element_Array
        (1 .. Offset (Output_Capacity));
      Staged_Length    : Count := 0;
      Published_Length : Count := 0;
      Write_Calls      : Natural := 0;
      Active           : Boolean := False;
      Published        : Boolean := False;
   end record;

   Destination : aliased Benchmark_Destination;

   procedure Destination_Begin
     (Target : in out Benchmark_Destination;
      Status : out Flyology_JSON.Destinations.Begin_Status) is
   begin
      if Target.Active then
         Status := Flyology_JSON.Destinations.Begin_Failed;
      else
         Target.Staged_Length := 0;
         Target.Published_Length := 0;
         Target.Write_Calls := 0;
         Target.Published := False;
         Target.Active := True;
         Status := Flyology_JSON.Destinations.Begin_Succeeded;
      end if;
   end Destination_Begin;

   procedure Destination_Write
     (Target  : in out Benchmark_Destination;
      Data    : Ada.Streams.Stream_Element_Array;
      Written : out Count;
      Status  : out Flyology_JSON.Destinations.Write_Status)
   is
      First : Offset;
      Last  : Offset;
   begin
      Target.Write_Calls := Target.Write_Calls + 1;
      if not Target.Active then
         Written := 0;
         Status := Flyology_JSON.Destinations.Write_Failed;
      elsif Data'Length > Output_Capacity - Target.Staged_Length then
         Written := Output_Capacity - Target.Staged_Length;
         if Written > 0 then
            First := Target.Buffer'First + Offset (Target.Staged_Length);
            Last := First + Offset (Written - 1);
            Target.Buffer (First .. Last) :=
              Data (Data'First .. Data'First + Offset (Written - 1));
            Target.Staged_Length := Output_Capacity;
         end if;
         Status := Flyology_JSON.Destinations.Write_Exhausted;
      elsif Data'Length = 0 then
         Written := 0;
         Status := Flyology_JSON.Destinations.Write_Succeeded;
      else
         First := Target.Buffer'First + Offset (Target.Staged_Length);
         Last := First + Offset (Data'Length) - 1;
         Target.Buffer (First .. Last) := Data;
         Target.Staged_Length := Target.Staged_Length + Data'Length;
         Written := Data'Length;
         Status := Flyology_JSON.Destinations.Write_Succeeded;
      end if;
   end Destination_Write;
   pragma No_Inline (Destination_Write);

   procedure Destination_Commit
     (Target : in out Benchmark_Destination;
      Status : out Flyology_JSON.Destinations.Commit_Status) is
   begin
      if Target.Active then
         Target.Active := False;
         Target.Published := True;
         Target.Published_Length := Target.Staged_Length;
         Status := Flyology_JSON.Destinations.Commit_Succeeded;
      else
         Status := Flyology_JSON.Destinations.Commit_Failed;
      end if;
   end Destination_Commit;

   procedure Destination_Abort
     (Target : in out Benchmark_Destination;
      Status : out Flyology_JSON.Destinations.Abort_Status) is
   begin
      Target.Active := False;
      Target.Published := False;
      Target.Published_Length := 0;
      Status := Flyology_JSON.Destinations.Abort_Succeeded;
   end Destination_Abort;

   package Writers is new Flyology_JSON.Writing
     (Destination_Type   => Benchmark_Destination,
      Destination_Begin  => Destination_Begin,
      Destination_Write  => Destination_Write,
      Destination_Commit => Destination_Commit,
      Destination_Abort  => Destination_Abort);

   use type Writers.Writer_State;

   Writer_Profile : constant Flyology_JSON.Profiles.Writer_Profile :=
     (Syntax     => (Family => Flyology_JSON.Profiles.RFC_8259, Version => 1),
      Unicode    => (Family => Flyology_JSON.Profiles.Unicode_Scalars, Version => 1),
      Formatting => (Policy => Flyology_JSON.Profiles.Ordinary_Compact, Version => 1));

   type Write_Observation is record
      Result_Checksum    : U64 := 0;
      Output_Octets      : Count := 0;
      Writer_Calls       : Natural := 0;
      Destination_Calls  : Natural := 0;
   end record;

   function Maximum_Depth (Kind : Fixture_Kind) return Natural is
     (if Kind = Nested_Structures then 3
      elsif Kind = Number_Heavy_Array then 1
      else 0);

   function Fragment_Eligible (Kind : Fixture_Kind) return Boolean is
     (Kind in Small_Number | Small_String | Large_Raw_String |
        Escape_Heavy_String | Number_Heavy_Array);

   procedure Check
     (Diagnostic : Flyology_JSON.Errors.Diagnostic;
      Calls      : in out Natural) is
   begin
      Calls := Calls + 1;
      if Diagnostic.Code /= Flyology_JSON.Errors.No_Error then
         raise Program_Error with
           "writer benchmark failed with" & Flyology_JSON.Errors.Error_Code'Image (Diagnostic.Code);
      end if;
   end Check;

   type Fragment_Target is (Name_Text, String_Text, Number_Text);

   procedure Put_Fragments
     (Self       : in out Writers.Writer;
      Data       : Ada.Streams.Stream_Element_Array;
      Schedule   : Fragment_Kind;
      Target     : Fragment_Target;
      Calls      : in out Natural)
   is
      Diagnostic : Flyology_JSON.Errors.Diagnostic;

      procedure Put (Value : Ada.Streams.Stream_Element_Array) is
      begin
         case Target is
            when Name_Text =>
               Writers.Put_Name_Fragment (Self, Value, Diagnostic);
            when String_Text =>
               Writers.Put_String_Fragment (Self, Value, Diagnostic);
            when Number_Text =>
               Writers.Put_Number_Fragment (Self, Value, Diagnostic);
         end case;
         Check (Diagnostic, Calls);
      end Put;
   begin
      if Schedule = Bulk then
         Put (Data);
      else
         for Index in Data'Range loop
            Put (Data (Index .. Index));
         end loop;
      end if;
   end Put_Fragments;

   procedure Write_String_Value
     (Self     : in out Writers.Writer;
      Data     : Ada.Streams.Stream_Element_Array;
      Schedule : Fragment_Kind;
      Calls    : in out Natural)
   is
      Diagnostic : Flyology_JSON.Errors.Diagnostic;
   begin
      Writers.Begin_String (Self, Diagnostic);
      Check (Diagnostic, Calls);
      Put_Fragments (Self, Data, Schedule, String_Text, Calls);
      Writers.End_String (Self, Diagnostic);
      Check (Diagnostic, Calls);
   end Write_String_Value;

   procedure Write_Number_Value
     (Self     : in out Writers.Writer;
      Data     : Ada.Streams.Stream_Element_Array;
      Schedule : Fragment_Kind;
      Calls    : in out Natural)
   is
      Diagnostic : Flyology_JSON.Errors.Diagnostic;
   begin
      Writers.Begin_Number (Self, Diagnostic);
      Check (Diagnostic, Calls);
      Put_Fragments (Self, Data, Schedule, Number_Text, Calls);
      Writers.End_Number (Self, Diagnostic);
      Check (Diagnostic, Calls);
   end Write_Number_Value;

   procedure Write_Name
     (Self  : in out Writers.Writer;
      Data  : Ada.Streams.Stream_Element_Array;
      Calls : in out Natural)
   is
      Diagnostic : Flyology_JSON.Errors.Diagnostic;
   begin
      Writers.Begin_Name (Self, Diagnostic);
      Check (Diagnostic, Calls);
      Put_Fragments (Self, Data, Bulk, Name_Text, Calls);
      Writers.End_Name (Self, Diagnostic);
      Check (Diagnostic, Calls);
   end Write_Name;

   procedure Write_Once
     (Kind        : Fixture_Kind;
      Schedule    : Fragment_Kind;
      Observation : out Write_Observation)
   is
      Self       : Writers.Writer (Destination'Access, Maximum_Depth (Kind));
      Diagnostic : Flyology_JSON.Errors.Diagnostic;
      Calls      : Natural := 0;
   begin
      Writers.Initialize (Self, Writer_Profile, Diagnostic);
      Check (Diagnostic, Calls);
      Writers.Begin_Document (Self, Diagnostic);
      Check (Diagnostic, Calls);

      case Kind is
         when Small_Null =>
            Writers.Put_Null (Self, Diagnostic);
            Check (Diagnostic, Calls);

         when Small_Boolean =>
            Writers.Put_Boolean (Self, True, Diagnostic);
            Check (Diagnostic, Calls);

         when Small_Number =>
            Write_Number_Value (Self, Small_Number_Data.all, Schedule, Calls);

         when Small_String =>
            Write_String_Value (Self, Small_String_Data.all, Schedule, Calls);

         when Large_Raw_String =>
            Write_String_Value (Self, Large_Raw_Data.all, Schedule, Calls);

         when Escape_Heavy_String =>
            Write_String_Value (Self, Escape_Data.all, Schedule, Calls);

         when Number_Heavy_Array =>
            Writers.Begin_Array (Self, Diagnostic);
            Check (Diagnostic, Calls);
            for Repetition in 1 .. Number_Repeats loop
               Write_Number_Value (Self, Number_Zero.all, Schedule, Calls);
               Write_Number_Value (Self, Number_Negative.all, Schedule, Calls);
               Write_Number_Value (Self, Number_Integer.all, Schedule, Calls);
               Write_Number_Value (Self, Number_Fraction.all, Schedule, Calls);
               Write_Number_Value (Self, Number_Exponent.all, Schedule, Calls);
               Write_Number_Value (Self, Number_Small.all, Schedule, Calls);
            end loop;
            Writers.End_Array (Self, Diagnostic);
            Check (Diagnostic, Calls);

         when Nested_Structures =>
            Writers.Begin_Array (Self, Diagnostic);
            Check (Diagnostic, Calls);
            for Repetition in 1 .. Structure_Repeats loop
               Writers.Begin_Object (Self, Diagnostic);
               Check (Diagnostic, Calls);
               Write_Name (Self, Name_Id.all, Calls);
               Write_Number_Value (Self, Nested_Number.all, Bulk, Calls);
               Write_Name (Self, Name_Values.all, Calls);
               Writers.Begin_Array (Self, Diagnostic);
               Check (Diagnostic, Calls);
               Writers.Put_Boolean (Self, True, Diagnostic);
               Check (Diagnostic, Calls);
               Writers.Put_Null (Self, Diagnostic);
               Check (Diagnostic, Calls);
               Writers.End_Array (Self, Diagnostic);
               Check (Diagnostic, Calls);
               Writers.End_Object (Self, Diagnostic);
               Check (Diagnostic, Calls);
            end loop;
            Writers.End_Array (Self, Diagnostic);
            Check (Diagnostic, Calls);
      end case;

      Writers.Finish_Document (Self, Diagnostic);
      Check (Diagnostic, Calls);
      if not Destination.Published or else Writers.State (Self) /= Writers.Completed then
         raise Program_Error with "writer benchmark did not commit";
      end if;

      Observation.Output_Octets := Destination.Published_Length;
      Observation.Writer_Calls := Calls;
      Observation.Destination_Calls := Destination.Write_Calls;
      Observation.Result_Checksum :=
        U64 (Destination.Published_Length) + U64 (Destination.Write_Calls) + U64 (Calls);
      if Destination.Published_Length > 0 then
         Observation.Result_Checksum :=
           Observation.Result_Checksum
           + U64 (Destination.Buffer (Destination.Buffer'First))
           + U64
               (Destination.Buffer
                  (Destination.Buffer'First + Offset (Destination.Published_Length) - 1));
      end if;
   end Write_Once;

   function Hash_Output return U64 is
      Hash : U64 := 16#CBF29CE484222325#;
   begin
      for Position in Count range 0 .. Destination.Published_Length - 1 loop
         Hash :=
           (Hash xor U64 (Destination.Buffer (Destination.Buffer'First + Offset (Position))))
           * 16#00000100000001B3#;
      end loop;
      return Hash;
   end Hash_Output;

   procedure Validate_Output (Kind : Fixture_Kind) is
      Position : Count := 0;

      procedure Expect_Octet (Value : Ada.Streams.Stream_Element) is
      begin
         if Position >= Destination.Published_Length
           or else Destination.Buffer (Destination.Buffer'First + Offset (Position)) /= Value
         then
            raise Program_Error with "writer benchmark output mismatch";
         end if;
         Position := Position + 1;
      end Expect_Octet;

      procedure Expect (Text : String) is
      begin
         for Value of Text loop
            Expect_Octet (Character'Pos (Value));
         end loop;
      end Expect;

      procedure Expect_Data (Data : Ada.Streams.Stream_Element_Array) is
      begin
         for Value of Data loop
            Expect_Octet (Value);
         end loop;
      end Expect_Data;
   begin
      case Kind is
         when Small_Null =>
            Expect ("null");
         when Small_Boolean =>
            Expect ("true");
         when Small_Number =>
            Expect_Data (Small_Number_Data.all);
         when Small_String =>
            Expect ("""");
            Expect_Data (Small_String_Data.all);
            Expect ("""");
         when Large_Raw_String =>
            Expect ("""");
            Expect_Data (Large_Raw_Data.all);
            Expect ("""");
         when Escape_Heavy_String =>
            Expect ("""");
            for Value of Escape_Data.all loop
               case Value is
                  when 0 =>
                     Expect ("\u0000");
                  when Character'Pos ('"') =>
                     Expect ("\""");
                  when Character'Pos ('\') =>
                     Expect ("\\");
                  when 10 =>
                     Expect ("\n");
                  when 9 =>
                     Expect ("\t");
                  when others =>
                     Expect_Octet (Value);
               end case;
            end loop;
            Expect ("""");
         when Number_Heavy_Array =>
            Expect ("[");
            for Repetition in 1 .. Number_Repeats loop
               if Repetition > 1 then
                  Expect (",");
               end if;
               Expect ("0,-1,123456789,1.5,6.022e23,-0.001");
            end loop;
            Expect ("]");
         when Nested_Structures =>
            Expect ("[");
            for Repetition in 1 .. Structure_Repeats loop
               if Repetition > 1 then
                  Expect (",");
               end if;
               Expect ("{""id"":123456789,""values"":[true,null]}");
            end loop;
            Expect ("]");
      end case;

      if Position /= Destination.Published_Length then
         raise Program_Error with "writer benchmark output has unexpected suffix";
      end if;
   end Validate_Output;

   function Fixture_Name (Kind : Fixture_Kind) return String is
     (case Kind is
         when Small_Null          => "small_null",
         when Small_Boolean       => "small_boolean",
         when Small_Number        => "small_number",
         when Small_String        => "small_string",
         when Large_Raw_String    => "large_raw_string",
         when Escape_Heavy_String => "escape_heavy_string",
         when Number_Heavy_Array  => "number_heavy_array",
         when Nested_Structures   => "nested_structures");

   function Fragment_Name (Kind : Fragment_Kind) return String is
     (case Kind is when Bulk => "bulk", when One_Octet => "1");

   function Logical_Octets (Kind : Fixture_Kind) return Count is
     (case Kind is
         when Small_Null          => 4,
         when Small_Boolean       => 4,
         when Small_Number        => Small_Number_Data'Length,
         when Small_String        => Small_String_Data'Length,
         when Large_Raw_String    => Large_Raw_Data'Length,
         when Escape_Heavy_String => Escape_Data'Length,
         when Number_Heavy_Array  => Count (Number_Repeats * 29),
         when Nested_Structures   => Count (Structure_Repeats * 25));

   function Trimmed_Image (Value : Count) return String is
     (Ada.Strings.Fixed.Trim (Count'Image (Value), Ada.Strings.Both));

   function Trimmed_Image (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   function Hex_Image (Value : U64) return String is
      Hex_Alphabet : constant String := "0123456789abcdef";
      Result : String (1 .. 16);
      Work   : U64 := Value;
   begin
      for Index in reverse Result'Range loop
         Result (Index) := Hex_Alphabet (Natural (Work and 16#F#) + 1);
         Work := Interfaces.Shift_Right (Work, 4);
      end loop;
      return Result;
   end Hex_Image;

   function Writer_Bytes (Kind : Fixture_Kind) return Natural is
      Self : Writers.Writer (Destination'Access, Maximum_Depth (Kind));
   begin
      return (Self'Size + System.Storage_Unit - 1) / System.Storage_Unit;
   end Writer_Bytes;

   Current_Fixture : Fixture_Kind := Fixture_Kind'First;
   Current_Fragment : Fragment_Kind := Fragment_Kind'First;

   procedure Write_Batch
     (Iterations : Flyology_Bench.Iteration_Count;
      Value      : out U64) is
      Observation : Write_Observation;
   begin
      Value := 0;
      for Iteration in Flyology_Bench.Iteration_Count range 1 .. Iterations loop
         Write_Once (Current_Fixture, Current_Fragment, Observation);
         Value := Value + Observation.Result_Checksum;
      end loop;
   end Write_Batch;

   procedure Measure_Writer is new Flyology_Bench.Measure_Result_Batched
     (Element => U64, Batch => Write_Batch);

   Base_Config : constant Flyology_Bench.Configuration :=
     (Warmup_Time                  => 0.100,
      Measurement_Time             => 0.500,
      Maximum_Sampling_Time        => 0.0,
      Samples                      => 50,
      Minimum_Sample_Time          => 0.000_100,
      Maximum_Iterations           => 65_536,
      Subtract_Timer_Cost          => False,
      Metrics                      => Flyology_Bench.Process_Resource_Metrics,
      Collect_Process_Telemetry    => True,
      others                       => <>);

   Output_Mode : constant String :=
     Ada.Environment_Variables.Value
       ("FLYOLOGY_JSON_BENCH_OUTPUT", Default => "terminal");
   Fixture_Selector : constant String :=
     Ada.Environment_Variables.Value
       ("FLYOLOGY_JSON_BENCH_FIXTURE", Default => "");
   Fragment_Selector : constant String :=
     Ada.Environment_Variables.Value
       ("FLYOLOGY_JSON_BENCH_FRAGMENT", Default => "");

   function Fixture_Selected (Kind : Fixture_Kind) return Boolean is
     (Fixture_Selector = "" or else Fixture_Selector = Fixture_Name (Kind));

   function Fragment_Selected (Kind : Fragment_Kind) return Boolean is
     (Fragment_Selector = "" or else Fragment_Selector = Fragment_Name (Kind));

   function Known_Fixture return Boolean is
   begin
      if Fixture_Selector = "" then
         return True;
      end if;
      for Kind in Fixture_Kind loop
         if Fixture_Selector = Fixture_Name (Kind) then
            return True;
         end if;
      end loop;
      return False;
   end Known_Fixture;

   procedure Run_Benchmark (Kind : Fixture_Kind; Fragment : Fragment_Kind) is
      Observation : Write_Observation;
      Result      : Flyology_Bench.Measurement;
      Preflight_Hash : U64;
   begin
      Write_Once (Kind, Fragment, Observation);
      Validate_Output (Kind);
      Preflight_Hash := Hash_Output;
      Current_Fixture := Kind;
      Current_Fragment := Fragment;

      declare
         Name : constant String :=
           "writer/api=public_writing/fixture=" & Fixture_Name (Kind)
           & "/fragment=" & Fragment_Name (Fragment)
           & "/logical_octets=" & Trimmed_Image (Logical_Octets (Kind))
           & "/output_octets=" & Trimmed_Image (Observation.Output_Octets)
           & "/writer_calls=" & Trimmed_Image (Observation.Writer_Calls)
           & "/destination_calls=" & Trimmed_Image (Observation.Destination_Calls)
           & "/maximum_depth=" & Trimmed_Image (Maximum_Depth (Kind))
           & "/writer_bytes=" & Trimmed_Image (Writer_Bytes (Kind))
           & "/allocations_per_operation=0-contract"
           & "/output_fnv1a64=" & Hex_Image (Preflight_Hash);
         Config : constant Flyology_Bench.Configuration :=
           (if Output_Mode = "terminal"
            then Flyology_Bench.Reporters.Terminal_Mode (Base_Config, Name)
            else Base_Config);
      begin
         Measure_Writer (Config => Config, Result => Result);
         if Output_Mode = "terminal" then
            Flyology_Bench.Reporters.Put_Console (Name, Result);
            Ada.Text_IO.Put_Line
              ("  median output throughput:"
               & Long_Float'Image
                   (Long_Float (Observation.Output_Octets) * 1_000_000_000.0
                    / Flyology_Bench.Median_Nanoseconds (Result)
                    / 1_048_576.0)
               & " MiB/s");
         elsif Output_Mode = "csv" then
            Flyology_Bench.Reporters.Put_CSV (Name, Result);
         elsif Output_Mode = "metrics_csv" then
            Flyology_Bench.Reporters.Put_Metrics_CSV (Name, Result);
         else
            Flyology_Bench.Reporters.Put_JSON (Name, Result);
         end if;
      end;
   end Run_Benchmark;

begin
   for Position in Count range 0 .. Large_Raw_Length - 1 loop
      Large_Raw_Data (Large_Raw_Data'First + Position) :=
        Ada.Streams.Stream_Element
          (Character'Pos ('a') + Natural (Position mod 26));
   end loop;
   for Position in Count range 0 .. Escape_Length - 1 loop
      Escape_Data (Escape_Data'First + Position) :=
        (case Position mod 6 is
            when 0 => 0,
            when 1 => Character'Pos ('"'),
            when 2 => Character'Pos ('\'),
            when 3 => 10,
            when 4 => 9,
            when others => Character'Pos ('a'));
   end loop;

   if Output_Mode not in "terminal" | "csv" | "metrics_csv" | "json" then
      raise Constraint_Error with
        "FLYOLOGY_JSON_BENCH_OUTPUT must be terminal, csv, metrics_csv, or json";
   end if;
   if not Known_Fixture then
      raise Constraint_Error with "unknown FLYOLOGY_JSON_BENCH_FIXTURE selector";
   end if;
   if Fragment_Selector not in "" | "bulk" | "1" then
      raise Constraint_Error with "FLYOLOGY_JSON_BENCH_FRAGMENT must be bulk or 1";
   end if;
   if Fragment_Selector = "1" and then Fixture_Selector /= "" then
      for Kind in Fixture_Kind loop
         if Fixture_Selector = Fixture_Name (Kind) and then not Fragment_Eligible (Kind) then
            raise Constraint_Error with "the selected fixture has no fragment-bearing value";
         end if;
      end loop;
   end if;

   if Output_Mode = "csv" then
      Flyology_Bench.Reporters.Put_CSV_Header;
   elsif Output_Mode = "metrics_csv" then
      Flyology_Bench.Reporters.Put_Metrics_CSV_Header;
   end if;

   for Kind in Fixture_Kind loop
      for Fragment in Fragment_Kind loop
         if Fixture_Selected (Kind)
           and then Fragment_Selected (Fragment)
           and then (Fragment = Bulk or else Fragment_Eligible (Kind))
         then
            Run_Benchmark (Kind, Fragment);
         end if;
      end loop;
   end loop;
end Flyology_JSON.Writer_Benchmark;
