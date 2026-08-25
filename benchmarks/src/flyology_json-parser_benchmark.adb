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
with Flyology_JSON.Errors;
with Flyology_JSON.Parsing;
with Flyology_JSON.Profiles;
with Interfaces;
with System;

procedure Flyology_JSON.Parser_Benchmark is
   package Profiles renames Flyology_JSON.Profiles;
   package Strict_Parsing is new Flyology_JSON.Parsing (Profiles.Reject_Duplicates);
   package Preserve_Parsing is new Flyology_JSON.Parsing (Profiles.Preserve_Unchecked);
   package Unbounded renames Ada.Strings.Unbounded;

   use type Ada.Streams.Stream_Element_Offset;
   use type Flyology_Bench.Iteration_Count;
   use type Flyology_JSON.Errors.Error_Code;
   use type Interfaces.Unsigned_64;
   use type Profiles.Duplicate_Policy;

   subtype Count is Ada.Streams.Stream_Element_Count;
   subtype Offset is Ada.Streams.Stream_Element_Offset;
   subtype U64 is Interfaces.Unsigned_64;

   --  This caller-selected publication batch is part of the benchmark
   --  population identity.  It is not a parser capacity or public default.
   Drain_Event_Capacity : constant Positive := 256;

   type Octet_Array_Access is access all Ada.Streams.Stream_Element_Array;

   type Fixture_Kind is
     (Small_Mixed,
      Large_Mixed,
      String_Heavy,
      Number_Heavy,
      Long_Mantissa_Numbers,
      Deep_Nesting,
      Large_Array,
      Large_Object);

   --  The maintained benchmark matrix requires these exact transport sizes.
   --  They are schedule identities, never parser defaults.
   type Chunk_Kind is
     (Monolith, One_Octet, Sixteen_Octets, Two_Fifty_Six_Octets,
      Four_Thousand_Ninety_Six_Octets);

   type Fixture is record
      Name                : Unbounded.Unbounded_String;
      Data                : Octet_Array_Access;
      Maximum_Depth       : Positive;
      Name_Octet_Capacity : Natural;
      Name_Capacity       : Natural;
   end record;

   type Fixture_Array is array (Fixture_Kind) of Fixture;

   type Parse_Observation is record
      Checksum : U64 := 0;
      Events   : Natural := 0;
      Calls    : Natural := 0;
   end record;

   function Trimmed_Image (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   function To_Octets (Text : String) return Octet_Array_Access is
      --  A non-one lower bound keeps this lane honest about count-based input.
      --  It is fixture shape, not a parser policy or operational default.
      First  : constant Offset := 13;
      Result : constant Octet_Array_Access :=
        new Ada.Streams.Stream_Element_Array
          (First .. First + Offset (Text'Length) - 1);
   begin
      for Index in Text'Range loop
         Result (First + Offset (Index - Text'First)) := Character'Pos (Text (Index));
      end loop;
      return Result;
   end To_Octets;

   function Make_Fixture
     (Name          : String;
      Text          : Unbounded.Unbounded_String;
      Maximum_Depth : Positive;
      Name_Octets   : Natural;
      Names         : Natural) return Fixture is
   begin
      return
        (Name                => Unbounded.To_Unbounded_String (Name),
         Data                => To_Octets (Unbounded.To_String (Text)),
         Maximum_Depth       => Maximum_Depth,
         Name_Octet_Capacity => Name_Octets,
         Name_Capacity       => Names);
   end Make_Fixture;

   function Make_Small return Fixture is
   begin
      return Make_Fixture
        ("small_mixed",
         Unbounded.To_Unbounded_String
           ("{""name"":""fly"",""ok"":true,""n"":-12.5e+2}"),
         Maximum_Depth => 1,
         Name_Octets   => 7,
         Names         => 3);
   end Make_Small;

   --  Synthetic fixture counts target roughly 0.25--1 MiB for bulk lanes and
   --  an exact 256-level transition stressor.  They define this benchmark
   --  methodology only; changing one starts a new, non-comparable baseline.
   function Make_Large_Mixed return Fixture is
      Text : Unbounded.Unbounded_String := Unbounded.To_Unbounded_String ("[");
   begin
      for Index in 0 .. 8_191 loop
         if Index > 0 then
            Unbounded.Append (Text, ',');
         end if;
         Unbounded.Append
           (Text,
            "{""id"":" & Trimmed_Image (Index)
            & ",""name"":""abcdefghijklmnop"",""active"":true,""values"":[0,1,2]}");
      end loop;
      Unbounded.Append (Text, ']');
      return Make_Fixture
        ("large_mixed",
         Text,
         Maximum_Depth => 3,
         Name_Octets   => 18,
         Names         => 4);
   end Make_Large_Mixed;

   function Make_String_Heavy return Fixture is
      Text : Unbounded.Unbounded_String := Unbounded.To_Unbounded_String ("{""text"":""");
      ASCII_Block : constant String :=
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        & "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
   begin
      for Block in 1 .. 8_192 loop
         Unbounded.Append (Text, ASCII_Block);
         Unbounded.Append (Text, "\u20AC");
         Unbounded.Append (Text, Character'Val (16#C3#));
         Unbounded.Append (Text, Character'Val (16#A9#));
      end loop;
      Unbounded.Append (Text, """}");
      return Make_Fixture
        ("string_heavy",
         Text,
         Maximum_Depth => 1,
         Name_Octets   => 4,
         Names         => 1);
   end Make_String_Heavy;

   function Make_Number_Heavy return Fixture is
      Text : Unbounded.Unbounded_String := Unbounded.To_Unbounded_String ("[");
   begin
      for Index in 0 .. 8_191 loop
         if Index > 0 then
            Unbounded.Append (Text, ',');
         end if;
         Unbounded.Append (Text, "0,-1,123456789,1.5,6.022e23,-0.001");
      end loop;
      Unbounded.Append (Text, ']');
      return Make_Fixture
        ("number_heavy", Text, Maximum_Depth => 1, Name_Octets => 0, Names => 0);
   end Make_Number_Heavy;

   function Make_Long_Mantissa_Numbers return Fixture is
      Text : Unbounded.Unbounded_String := Unbounded.To_Unbounded_String ("[");
   begin
      for Index in 0 .. 32_767 loop
         if Index > 0 then
            Unbounded.Append (Text, ',');
         end if;
         Unbounded.Append (Text, "-1234567890.123456789e+123");
      end loop;
      Unbounded.Append (Text, ']');
      return Make_Fixture
        ("long_mantissa_numbers",
         Text,
         Maximum_Depth => 1,
         Name_Octets   => 0,
         Names         => 0);
   end Make_Long_Mantissa_Numbers;

   function Make_Deep_Nesting return Fixture is
      Text : Unbounded.Unbounded_String;
   begin
      for Level in 1 .. 256 loop
         Unbounded.Append (Text, '[');
      end loop;
      Unbounded.Append (Text, '0');
      for Level in 1 .. 256 loop
         Unbounded.Append (Text, ']');
      end loop;
      return Make_Fixture
        ("deep_nesting", Text, Maximum_Depth => 256, Name_Octets => 0, Names => 0);
   end Make_Deep_Nesting;

   function Make_Large_Array return Fixture is
      Text : Unbounded.Unbounded_String := Unbounded.To_Unbounded_String ("[");
   begin
      for Index in 0 .. 65_535 loop
         if Index > 0 then
            Unbounded.Append (Text, ',');
         end if;
         case Index mod 4 is
            when 0 =>
               Unbounded.Append (Text, "null");
            when 1 =>
               Unbounded.Append (Text, "true");
            when 2 =>
               Unbounded.Append (Text, "false");
            when others =>
               Unbounded.Append (Text, '0');
         end case;
      end loop;
      Unbounded.Append (Text, ']');
      return Make_Fixture
        ("large_array", Text, Maximum_Depth => 1, Name_Octets => 0, Names => 0);
   end Make_Large_Array;

   function Make_Large_Object return Fixture is
      Text        : Unbounded.Unbounded_String := Unbounded.To_Unbounded_String ("{");
      Name_Octets : Natural := 0;
   begin
      for Index in 0 .. 16_383 loop
         if Index > 0 then
            Unbounded.Append (Text, ',');
         end if;
         declare
            Key : constant String := "key_" & Trimmed_Image (Index);
         begin
            Unbounded.Append (Text, '"' & Key & """:false");
            Name_Octets := Name_Octets + Key'Length;
         end;
      end loop;
      Unbounded.Append (Text, '}');
      return Make_Fixture
        ("large_object",
         Text,
         Maximum_Depth => 1,
         Name_Octets   => Name_Octets,
         Names         => 16_384);
   end Make_Large_Object;

   Fixtures : constant Fixture_Array :=
     [Small_Mixed   => Make_Small,
      Large_Mixed   => Make_Large_Mixed,
      String_Heavy  => Make_String_Heavy,
      Number_Heavy  => Make_Number_Heavy,
      Long_Mantissa_Numbers => Make_Long_Mantissa_Numbers,
      Deep_Nesting  => Make_Deep_Nesting,
      Large_Array   => Make_Large_Array,
      Large_Object  => Make_Large_Object];

   function Chunk_Octets (Kind : Chunk_Kind; Length : Count) return Count is
     (case Kind is
         when Monolith                        => Length,
         when One_Octet                       => 1,
         when Sixteen_Octets                  => 16,
         when Two_Fifty_Six_Octets            => 256,
         when Four_Thousand_Ninety_Six_Octets => 4_096);

   function Chunk_Name (Kind : Chunk_Kind) return String is
     (case Kind is
         when Monolith                        => "monolith",
         when One_Octet                       => "1",
         when Sixteen_Octets                  => "16",
         when Two_Fifty_Six_Octets            => "256",
         when Four_Thousand_Ninety_Six_Octets => "4096");

   generic
      Duplicate_Handling : Profiles.Duplicate_Policy;
      with package Parser_API is new Flyology_JSON.Parsing (Duplicate_Handling);
   procedure Parse_Mode_Once
     (Item        : Fixture;
      Chunk       : Chunk_Kind;
      Observation : out Parse_Observation);

   procedure Parse_Mode_Once
     (Item        : Fixture;
      Chunk       : Chunk_Kind;
      Observation : out Parse_Observation)
   is
      Effective_Name_Octets : constant Natural :=
        (if Duplicate_Handling = Profiles.Preserve_Unchecked
         then 0
         else Item.Name_Octet_Capacity);
      Effective_Names : constant Natural :=
        (if Duplicate_Handling = Profiles.Preserve_Unchecked then 0 else Item.Name_Capacity);
      Parser         : Parser_API.Parser
        (Maximum_Depth       => Item.Maximum_Depth,
         Name_Octet_Capacity => Effective_Name_Octets,
         Name_Capacity       => Effective_Names);
      --  This benchmark-owned buffer is an explicit publication batch, not a
      --  parser capacity or public API default.
      Events         : Parser_API.Event_Array (1 .. Offset (Drain_Event_Capacity));
      Position       : Count := 0;
      Effective_Size : constant Count := Chunk_Octets (Chunk, Item.Data'Length);
      Diagnostic     : Flyology_JSON.Errors.Diagnostic;
      Profile        : constant Profiles.Parser_Profile :=
        (Syntax        => (Family => Profiles.RFC_8259, Version => 1),
         Unicode       => (Family => Profiles.Unicode_Scalars, Version => 1),
         Compatibility => (Family => Profiles.No_Extensions, Version => 1),
         BOM           => Profiles.Reject_BOM,
         Duplicates    => Duplicate_Handling,
         Top_Level     => Profiles.Accept_Any_Value);
   begin
      Observation := (others => <>);
      Parser_API.Initialize (Parser, Profile, Diagnostic);
      if Diagnostic.Code /= Flyology_JSON.Errors.No_Error then
         raise Program_Error with "benchmark parser initialization failed";
      end if;

      loop
         declare
            Remaining    : constant Count := Item.Data'Length - Position;
            Current_Size : constant Count := Count'Min (Effective_Size, Remaining);
            Used         : Count := 0;
            Final_Chunk  : constant Boolean := Current_Size = Remaining;
            Result       : Parser_API.Drain_Result;
         begin
            loop
               Observation.Calls := Observation.Calls + 1;

               if Used < Current_Size then
                  declare
                     First : constant Offset := Item.Data'First + Offset (Position + Used);
                     Last  : constant Offset :=
                       Item.Data'First + Offset (Position + Current_Size) - 1;
                  begin
                     Parser_API.Drain
                       (Parser,
                        Item.Data (First .. Last),
                        End_Of_Input => Final_Chunk,
                        Events       => Events,
                        Result       => Result);
                  end;
               else
                  declare
                     Empty : Ada.Streams.Stream_Element_Array (1 .. 0);
                  begin
                     Parser_API.Drain
                       (Parser,
                        Empty,
                        End_Of_Input => Final_Chunk,
                        Events       => Events,
                        Result       => Result);
                  end;
               end if;

               if Result.Consumed > Current_Size - Used then
                  raise Program_Error with "parser consumed beyond the supplied chunk";
               end if;
               Used := Used + Result.Consumed;

               if Result.Produced > 0 then
                  for Published in Count range 0 .. Result.Produced - 1 loop
                     declare
                        Value  : Parser_API.Event renames
                          Events (Events'First + Offset (Published));
                        Source : constant Parser_API.Source_Range := Parser_API.Source (Value);
                     begin
                        Observation.Events := Observation.Events + 1;
                        --  Keep event results observable with minimal consumer
                        --  work after direct publication into caller storage.
                        Observation.Checksum :=
                          Observation.Checksum
                          + U64 (Parser_API.Event_Kind'Pos (Parser_API.Kind (Value)) + 1)
                          + U64 (Source.First)
                          + U64 (Source.Octet_Length);
                     end;
                  end loop;
               end if;

               case Result.Stop is
                  when Parser_API.Output_Full =>
                     null;

                  when Parser_API.Drain_Need_Input =>
                     if Used /= Current_Size or else Final_Chunk then
                        raise Program_Error with "parser requested input at an invalid boundary";
                     end if;
                     Position := Position + Current_Size;
                     exit;

                  when Parser_API.Drain_Document_Complete =>
                     if not Final_Chunk
                       or else Position + Used /= Item.Data'Length
                     then
                        raise Program_Error with "parser completed before consuming the document";
                     end if;
                     return;

                  when Parser_API.Drain_Failed =>
                     raise Program_Error with
                       "valid benchmark fixture failed at offset"
                       & Flyology_JSON.Errors.Byte_Offset'Image (Result.Diagnostic.Offset);

                  when Parser_API.Drain_Rejected =>
                     raise Program_Error with "parser rejected a valid benchmark call";
               end case;
            end loop;
         end;
      end loop;
   end Parse_Mode_Once;

   procedure Parse_Once is new Parse_Mode_Once
     (Duplicate_Handling => Profiles.Reject_Duplicates,
      Parser_API         => Strict_Parsing);

   procedure Parse_Preserve_Once is new Parse_Mode_Once
     (Duplicate_Handling => Profiles.Preserve_Unchecked,
      Parser_API         => Preserve_Parsing);

   Current_Fixture : Fixture_Kind := Fixture_Kind'First;
   Current_Chunk   : Chunk_Kind := Chunk_Kind'First;

   procedure Parse_Batch
     (Iterations : Flyology_Bench.Iteration_Count;
      Value      : out U64) is
      Observation : Parse_Observation;
   begin
      Value := 0;
      for Iteration in Flyology_Bench.Iteration_Count range 1 .. Iterations loop
         Parse_Once (Fixtures (Current_Fixture), Current_Chunk, Observation);
         Value := Value + Observation.Checksum;
      end loop;
   end Parse_Batch;

   procedure Measure_Parser is new Flyology_Bench.Measure_Result_Batched
     (Element => U64, Batch => Parse_Batch);

   procedure Parse_Preserve_Batch
     (Iterations : Flyology_Bench.Iteration_Count;
      Value      : out U64)
   is
      Observation : Parse_Observation;
   begin
      Value := 0;
      for Iteration in Flyology_Bench.Iteration_Count range 1 .. Iterations loop
         Parse_Preserve_Once (Fixtures (Current_Fixture), Current_Chunk, Observation);
         Value := Value + Observation.Checksum;
      end loop;
   end Parse_Preserve_Batch;

   procedure Measure_Preserve_Parser is new Flyology_Bench.Measure_Result_Batched
     (Element => U64, Batch => Parse_Preserve_Batch);

   --  Fixed statistical policy for comparable retained baselines.  The zero
   --  sampling cap means disabled, so all 50 requested samples are retained.
   Base_Config : constant Flyology_Bench.Configuration :=
     (Warmup_Time                  => 0.100,
      Measurement_Time             => 0.500,
      Maximum_Sampling_Time        => 0.0,
      Samples                      => 50,
      Minimum_Sample_Time          => 0.000_100,
      Maximum_Iterations           => Flyology_Bench.Positive_Iteration_Count'Last,
      Subtract_Timer_Cost          => False,
      Metrics                      => Flyology_Bench.Process_Resource_Metrics,
      Collect_Process_Telemetry    => True,
      others                        => <>);

   Output_Mode : constant String :=
     Ada.Environment_Variables.Value
       ("FLYOLOGY_JSON_BENCH_OUTPUT", Default => "terminal");
   Dump_Preflight : constant Boolean :=
     Ada.Environment_Variables.Value
       ("FLYOLOGY_JSON_BENCH_PREFLIGHT_ONLY", Default => "false") = "true";
   Fixture_Selector : constant String :=
     Ada.Environment_Variables.Value
       ("FLYOLOGY_JSON_BENCH_FIXTURE", Default => "");
   Chunk_Selector : constant String :=
     Ada.Environment_Variables.Value
       ("FLYOLOGY_JSON_BENCH_CHUNK", Default => "");
   Duplicate_Selector : constant String :=
     Ada.Environment_Variables.Value
       ("FLYOLOGY_JSON_BENCH_DUPLICATES", Default => "");

   function Fixture_Name (Kind : Fixture_Kind) return String
   is (Unbounded.To_String (Fixtures (Kind).Name));

   function Fixture_Selected (Kind : Fixture_Kind) return Boolean
   is (Fixture_Selector = "" or else Fixture_Selector = Fixture_Name (Kind));

   function Chunk_Selected (Kind : Chunk_Kind) return Boolean
   is (Chunk_Selector = "" or else Chunk_Selector = Chunk_Name (Kind));

   function Duplicate_Selected (Preserve : Boolean) return Boolean
   is (Duplicate_Selector = ""
       or else Duplicate_Selector = (if Preserve then "preserve" else "reject"));

   function Known_Fixture_Selector return Boolean is
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
   end Known_Fixture_Selector;

   function Known_Chunk_Selector return Boolean is
   begin
      if Chunk_Selector = "" then
         return True;
      end if;
      for Kind in Chunk_Kind loop
         if Chunk_Selector = Chunk_Name (Kind) then
            return True;
         end if;
      end loop;
      return False;
   end Known_Chunk_Selector;

   function Parser_Storage_Bytes (Item : Fixture) return Natural is
      Parser : Strict_Parsing.Parser
        (Maximum_Depth       => Item.Maximum_Depth,
         Name_Octet_Capacity => Item.Name_Octet_Capacity,
         Name_Capacity       => Item.Name_Capacity);
   begin
      return (Parser'Size + System.Storage_Unit - 1) / System.Storage_Unit;
   end Parser_Storage_Bytes;

   function Preserve_Parser_Storage_Bytes (Item : Fixture) return Natural is
      Parser : Preserve_Parsing.Parser
        (Maximum_Depth       => Item.Maximum_Depth,
         Name_Octet_Capacity => 0,
         Name_Capacity       => 0);
   begin
      return (Parser'Size + System.Storage_Unit - 1) / System.Storage_Unit;
   end Preserve_Parser_Storage_Bytes;

   function Strict_Caller_Event_Bytes return Natural
   is
     ((Drain_Event_Capacity * Strict_Parsing.Event_Array'Component_Size
       + System.Storage_Unit - 1)
      / System.Storage_Unit);

   function Preserve_Caller_Event_Bytes return Natural
   is
     ((Drain_Event_Capacity * Preserve_Parsing.Event_Array'Component_Size
       + System.Storage_Unit - 1)
      / System.Storage_Unit);

   function Benchmark_Name
     (Item        : Fixture;
      Chunk       : Chunk_Kind;
      Observation : Parse_Observation;
      Preserve    : Boolean) return String is
   begin
      return
        "parser_validation/api=public_drain/" & Unbounded.To_String (Item.Name)
        & "/duplicates=" & (if Preserve then "preserve" else "reject")
        & "/chunk=" & Chunk_Name (Chunk)
        & "/bytes=" & Trimmed_Image (Natural (Item.Data'Length))
        & "/depth=" & Trimmed_Image (Item.Maximum_Depth)
        & "/events=" & Trimmed_Image (Observation.Events)
        & "/calls=" & Trimmed_Image (Observation.Calls)
        & "/drain_event_capacity=" & Trimmed_Image (Drain_Event_Capacity)
        & "/caller_event_bytes="
        & Trimmed_Image
            ((if Preserve then Preserve_Caller_Event_Bytes else Strict_Caller_Event_Bytes))
        & "/parser_bytes="
        & Trimmed_Image
            ((if Preserve then Preserve_Parser_Storage_Bytes (Item) else Parser_Storage_Bytes (Item)))
        & "/name_octets=" & Trimmed_Image ((if Preserve then 0 else Item.Name_Octet_Capacity))
        & "/names=" & Trimmed_Image ((if Preserve then 0 else Item.Name_Capacity));
   end Benchmark_Name;

   procedure Run_Benchmark
     (Kind     : Fixture_Kind;
      Chunk    : Chunk_Kind;
      Preserve : Boolean)
   is
      Item        : Fixture renames Fixtures (Kind);
      Observation : Parse_Observation;
      Result      : Flyology_Bench.Measurement;
   begin
      if Preserve then
         Parse_Preserve_Once (Item, Chunk, Observation);
      else
         Parse_Once (Item, Chunk, Observation);
      end if;
      Current_Fixture := Kind;
      Current_Chunk := Chunk;

      declare
         Name   : constant String := Benchmark_Name (Item, Chunk, Observation, Preserve);
         Config : constant Flyology_Bench.Configuration :=
           (if Output_Mode = "terminal"
            then Flyology_Bench.Reporters.Terminal_Mode (Base_Config, Name)
            else Base_Config);
      begin
         if Dump_Preflight then
            Ada.Text_IO.Put_Line (Name);
         else
            if Preserve then
               Measure_Preserve_Parser (Config => Config, Result => Result);
            else
               Measure_Parser (Config => Config, Result => Result);
            end if;
            if Output_Mode = "terminal" then
               Flyology_Bench.Reporters.Put_Console (Name, Result);
               Ada.Text_IO.Put_Line
                 ("  median throughput:"
                  & Long_Float'Image
                      (Long_Float (Item.Data'Length) * 1_000_000_000.0
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
         end if;
      end;
   end Run_Benchmark;

begin
   if Output_Mode not in "terminal" | "csv" | "metrics_csv" | "json" then
      raise Constraint_Error with
        "FLYOLOGY_JSON_BENCH_OUTPUT must be terminal, csv, metrics_csv, or json";
   end if;
   if not Known_Fixture_Selector then
      raise Constraint_Error with "unknown FLYOLOGY_JSON_BENCH_FIXTURE selector";
   end if;
   if not Known_Chunk_Selector then
      raise Constraint_Error with "unknown FLYOLOGY_JSON_BENCH_CHUNK selector";
   end if;
   if Duplicate_Selector not in "" | "reject" | "preserve" then
      raise Constraint_Error with
        "FLYOLOGY_JSON_BENCH_DUPLICATES must be reject or preserve";
   end if;
   if Duplicate_Selector = "preserve"
     and then Fixture_Selector /= ""
     and then Fixture_Selector /= "large_object"
   then
      raise Constraint_Error with
        "the maintained preserve lane is available only for large_object";
   end if;

   if not Dump_Preflight and then Output_Mode = "csv" then
      Flyology_Bench.Reporters.Put_CSV_Header;
   elsif not Dump_Preflight and then Output_Mode = "metrics_csv" then
      Flyology_Bench.Reporters.Put_Metrics_CSV_Header;
   end if;

   for Kind in Fixture_Kind loop
      for Chunk in Chunk_Kind loop
         if Fixture_Selected (Kind)
           and then Chunk_Selected (Chunk)
           and then Duplicate_Selected (Preserve => False)
         then
            Run_Benchmark (Kind, Chunk, Preserve => False);
         end if;
      end loop;
   end loop;

   --  Preserve_Unchecked is a distinct static parser shape.  The name-heavy
   --  object lane proves its zero-capacity path without doubling every fixture.
   for Chunk in Chunk_Kind loop
      if Fixture_Selected (Large_Object)
        and then Chunk_Selected (Chunk)
        and then Duplicate_Selected (Preserve => True)
      then
         Run_Benchmark (Large_Object, Chunk, Preserve => True);
      end if;
   end loop;
end Flyology_JSON.Parser_Benchmark;
