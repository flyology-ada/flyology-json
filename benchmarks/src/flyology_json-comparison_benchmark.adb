--  Copyright (c) 2026 Yurii Rashkovskii
--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Environment_Variables;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology_Bench;
with Flyology_Bench.Reporters;
with Flyology_JSON.Benchmark_CPP;
with Flyology_JSON.Benchmark_CPP.Rapidjson;
with Flyology_JSON.Benchmark_CPP.Simdjson;
with Flyology_JSON.Benchmark_Rust;
with Flyology_JSON.Benchmark_YYJSON;
with Flyology_JSON.Parser_Core;
with Interfaces;

procedure Flyology_JSON.Comparison_Benchmark is
   package CPP renames Flyology_JSON.Benchmark_CPP;
   package Rapidjson renames Flyology_JSON.Benchmark_CPP.Rapidjson;
   package Simdjson renames Flyology_JSON.Benchmark_CPP.Simdjson;
   package Rust renames Flyology_JSON.Benchmark_Rust;
   package YYJSON renames Flyology_JSON.Benchmark_YYJSON;
   package Core renames Flyology_JSON.Parser_Core;
   package Unbounded renames Ada.Strings.Unbounded;

   use type Ada.Streams.Stream_Element_Count;
   use type Core.Drain_Stop;
   use type Core.Event_Kind;
   use type Core.Parser_State;
   use type CPP.Parse_Status;
   use type Flyology_Bench.Iteration_Count;
   use type Interfaces.Unsigned_64;
   use type Rust.Parse_Status;
   use type YYJSON.Parse_Status;

   subtype Count is Ada.Streams.Stream_Element_Count;
   subtype Offset is Ada.Streams.Stream_Element_Offset;
   subtype U64 is Interfaces.Unsigned_64;

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

   type Implementation is
     (Flyology_Events,
      Rapidjson_Events,
      YYJSON_Validate,
      Simdjson_DOM,
      Rapidjson_DOM,
      Serde_JSON_DOM,
      Sonic_RS_DOM,
      SIMD_JSON_DOM);

   type Fixture is record
      Name                : Unbounded.Unbounded_String;
      Data                : Octet_Array_Access;
      Simdjson_Storage    : Octet_Array_Access;
      Maximum_Depth       : Positive;
      Name_Octet_Capacity : Natural;
      Name_Capacity       : Natural;
      Flyology_Events     : U64;
      Logical_Events      : U64;
      Scalars             : U64;
      Member_Names        : U64;
      YYJSON_Values       : U64;
   end record;

   type Fixture_Array is array (Fixture_Kind) of Fixture;

   function Trimmed_Image (Value : Natural) return String
   is (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   function To_Octets (Text : String) return Octet_Array_Access is
      First  : constant Offset := 13;
      Result : constant Octet_Array_Access :=
        new Ada.Streams.Stream_Element_Array (First .. First + Offset (Text'Length) - 1);
   begin
      for Index in Text'Range loop
         Result (First + Offset (Index - Text'First)) := Character'Pos (Text (Index));
      end loop;
      return Result;
   end To_Octets;

   function Make_Fixture
     (Name            : String;
      Text            : Unbounded.Unbounded_String;
      Maximum_Depth   : Positive;
      Name_Octets     : Natural;
      Names           : Natural;
      Flyology_Events : U64;
      Logical_Events  : U64;
      Scalars         : U64;
      Member_Names    : U64;
      YYJSON_Values   : U64) return Fixture
   is
      Data       : constant Octet_Array_Access := To_Octets (Unbounded.To_String (Text));
      Padding    : constant Offset := Offset (Simdjson.Required_Padding);
      SIMD_Input : constant Octet_Array_Access :=
        new Ada.Streams.Stream_Element_Array (Data'First .. Data'Last + Padding);
   begin
      SIMD_Input.all := (others => 0);
      SIMD_Input (Data'Range) := Data.all;
      return
        (Name                => Unbounded.To_Unbounded_String (Name),
         Data                => Data,
         Simdjson_Storage    => SIMD_Input,
         Maximum_Depth       => Maximum_Depth,
         Name_Octet_Capacity => Name_Octets,
         Name_Capacity       => Names,
         Flyology_Events     => Flyology_Events,
         Logical_Events      => Logical_Events,
         Scalars             => Scalars,
         Member_Names        => Member_Names,
         YYJSON_Values       => YYJSON_Values);
   end Make_Fixture;

   function Make_Small return Fixture is
   begin
      return
        Make_Fixture
          ("small_mixed",
           Unbounded.To_Unbounded_String ("{""name"":""fly"",""ok"":true,""n"":-12.5e+2}"),
           Maximum_Depth   => 1,
           Name_Octets     => 7,
           Names           => 3,
           Flyology_Events => 20,
           Logical_Events  => 8,
           Scalars         => 3,
           Member_Names    => 3,
           YYJSON_Values   => 7);
   end Make_Small;

   function Make_Large_Mixed return Fixture is
      Text : Unbounded.Unbounded_String := Unbounded.To_Unbounded_String ("[");
   begin
      for Index in 0 .. 8_191 loop
         if Index > 0 then
            Unbounded.Append (Text, ',');
         end if;
         Unbounded.Append
           (Text,
            "{""id"":"
            & Trimmed_Image (Index)
            & ",""name"":""abcdefghijklmnop"",""active"":true,""values"":[0,1,2]}");
      end loop;
      Unbounded.Append (Text, ']');
      return
        Make_Fixture
          ("large_mixed",
           Text,
           Maximum_Depth   => 3,
           Name_Octets     => 18,
           Names           => 4,
           Flyology_Events => 262_148,
           Logical_Events  => 114_690,
           Scalars         => 49_152,
           Member_Names    => 32_768,
           YYJSON_Values   => 98_305);
   end Make_Large_Mixed;

   function Make_String_Heavy return Fixture is
      Text        : Unbounded.Unbounded_String := Unbounded.To_Unbounded_String ("{""text"":""");
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
      return
        Make_Fixture
          ("string_heavy",
           Text,
           Maximum_Depth   => 1,
           Name_Octets     => 4,
           Names           => 1,
           Flyology_Events => 16_394,
           Logical_Events  => 4,
           Scalars         => 1,
           Member_Names    => 1,
           YYJSON_Values   => 3);
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
      return
        Make_Fixture
          ("number_heavy",
           Text,
           Maximum_Depth   => 1,
           Name_Octets     => 0,
           Names           => 0,
           Flyology_Events => 147_460,
           Logical_Events  => 49_154,
           Scalars         => 49_152,
           Member_Names    => 0,
           YYJSON_Values   => 49_153);
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
      return
        Make_Fixture
          ("long_mantissa_numbers",
           Text,
           Maximum_Depth   => 1,
           Name_Octets     => 0,
           Names           => 0,
           Flyology_Events => 98_308,
           Logical_Events  => 32_770,
           Scalars         => 32_768,
           Member_Names    => 0,
           YYJSON_Values   => 32_769);
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
      return
        Make_Fixture
          ("deep_nesting",
           Text,
           Maximum_Depth   => 256,
           Name_Octets     => 0,
           Names           => 0,
           Flyology_Events => 517,
           Logical_Events  => 513,
           Scalars         => 1,
           Member_Names    => 0,
           YYJSON_Values   => 257);
   end Make_Deep_Nesting;

   function Make_Large_Array return Fixture is
      Text : Unbounded.Unbounded_String := Unbounded.To_Unbounded_String ("[");
   begin
      for Index in 0 .. 65_535 loop
         if Index > 0 then
            Unbounded.Append (Text, ',');
         end if;
         case Index mod 4 is
            when 0      =>
               Unbounded.Append (Text, "null");

            when 1      =>
               Unbounded.Append (Text, "true");

            when 2      =>
               Unbounded.Append (Text, "false");

            when others =>
               Unbounded.Append (Text, '0');
         end case;
      end loop;
      Unbounded.Append (Text, ']');
      return
        Make_Fixture
          ("large_array",
           Text,
           Maximum_Depth   => 1,
           Name_Octets     => 0,
           Names           => 0,
           Flyology_Events => 98_308,
           Logical_Events  => 65_538,
           Scalars         => 65_536,
           Member_Names    => 0,
           YYJSON_Values   => 65_537);
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
      return
        Make_Fixture
          ("large_object",
           Text,
           Maximum_Depth   => 1,
           Name_Octets     => Name_Octets,
           Names           => 16_384,
           Flyology_Events => 65_540,
           Logical_Events  => 32_770,
           Scalars         => 16_384,
           Member_Names    => 16_384,
           YYJSON_Values   => 32_769);
   end Make_Large_Object;

   Fixtures : constant Fixture_Array :=
     [Small_Mixed           => Make_Small,
      Large_Mixed           => Make_Large_Mixed,
      String_Heavy          => Make_String_Heavy,
      Number_Heavy          => Make_Number_Heavy,
      Long_Mantissa_Numbers => Make_Long_Mantissa_Numbers,
      Deep_Nesting          => Make_Deep_Nesting,
      Large_Array           => Make_Large_Array,
      Large_Object          => Make_Large_Object];

   type Parser_Access is access all Core.Parser;

   Small_Parser         :
     aliased Core.Parser
               (Maximum_Depth => Fixtures (Small_Mixed).Maximum_Depth,
                Name_Octet_Capacity => Fixtures (Small_Mixed).Name_Octet_Capacity,
                Name_Capacity => Fixtures (Small_Mixed).Name_Capacity,
                Duplicate_Handling => Core.Reject_Duplicates);
   Large_Mixed_Parser   :
     aliased Core.Parser
               (Maximum_Depth => Fixtures (Large_Mixed).Maximum_Depth,
                Name_Octet_Capacity => Fixtures (Large_Mixed).Name_Octet_Capacity,
                Name_Capacity => Fixtures (Large_Mixed).Name_Capacity,
                Duplicate_Handling => Core.Reject_Duplicates);
   String_Heavy_Parser  :
     aliased Core.Parser
               (Maximum_Depth => Fixtures (String_Heavy).Maximum_Depth,
                Name_Octet_Capacity => Fixtures (String_Heavy).Name_Octet_Capacity,
                Name_Capacity => Fixtures (String_Heavy).Name_Capacity,
                Duplicate_Handling => Core.Reject_Duplicates);
   Number_Heavy_Parser  :
     aliased Core.Parser
               (Maximum_Depth => Fixtures (Number_Heavy).Maximum_Depth,
                Name_Octet_Capacity => Fixtures (Number_Heavy).Name_Octet_Capacity,
                Name_Capacity => Fixtures (Number_Heavy).Name_Capacity,
                Duplicate_Handling => Core.Reject_Duplicates);
   Long_Mantissa_Parser :
     aliased Core.Parser
               (Maximum_Depth => Fixtures (Long_Mantissa_Numbers).Maximum_Depth,
                Name_Octet_Capacity => Fixtures (Long_Mantissa_Numbers).Name_Octet_Capacity,
                Name_Capacity => Fixtures (Long_Mantissa_Numbers).Name_Capacity,
                Duplicate_Handling => Core.Reject_Duplicates);
   Deep_Nesting_Parser  :
     aliased Core.Parser
               (Maximum_Depth => Fixtures (Deep_Nesting).Maximum_Depth,
                Name_Octet_Capacity => Fixtures (Deep_Nesting).Name_Octet_Capacity,
                Name_Capacity => Fixtures (Deep_Nesting).Name_Capacity,
                Duplicate_Handling => Core.Reject_Duplicates);
   Large_Array_Parser   :
     aliased Core.Parser
               (Maximum_Depth => Fixtures (Large_Array).Maximum_Depth,
                Name_Octet_Capacity => Fixtures (Large_Array).Name_Octet_Capacity,
                Name_Capacity => Fixtures (Large_Array).Name_Capacity,
                Duplicate_Handling => Core.Reject_Duplicates);
   Large_Object_Parser  :
     aliased Core.Parser
               (Maximum_Depth => Fixtures (Large_Object).Maximum_Depth,
                Name_Octet_Capacity => Fixtures (Large_Object).Name_Octet_Capacity,
                Name_Capacity => Fixtures (Large_Object).Name_Capacity,
                Duplicate_Handling => Core.Reject_Duplicates);

   --  Retain caller-backed parser storage per fixture across operations just
   --  as the foreign event adapter retains its reader.  Untimed preflight
   --  initializes both mechanisms before samples; Reset is constant-time.
   Reusable_Flyology_Parsers : constant array (Fixture_Kind) of Parser_Access :=
     [Small_Mixed           => Small_Parser'Access,
      Large_Mixed           => Large_Mixed_Parser'Access,
      String_Heavy          => String_Heavy_Parser'Access,
      Number_Heavy          => Number_Heavy_Parser'Access,
      Long_Mantissa_Numbers => Long_Mantissa_Parser'Access,
      Deep_Nesting          => Deep_Nesting_Parser'Access,
      Large_Array           => Large_Array_Parser'Access,
      Large_Object          => Large_Object_Parser'Access];

   type Signature_Array is array (Fixture_Kind, Implementation) of U64;

   --  Regression signatures are tied to the exact fixture constructors and
   --  pinned adapter revisions.  Each signature incorporates the recursive
   --  checksum, every declared observation count, and the exact input size.
   Expected_Signature : constant Signature_Array :=
     [Small_Mixed           =>
        [Flyology_Events  => 916,
         Rapidjson_Events => 10_129_509_339_183_934_209,
         YYJSON_Validate  => 92_198_542_963,
         Simdjson_DOM     => 17_902_844_267_157_696_766,
         Rapidjson_DOM    => 17_902_844_267_157_696_766,
         Serde_JSON_DOM   => 14_707_519_380_160_794,
         Sonic_RS_DOM     => 14_106_766_096_649_873_928,
         SIMD_JSON_DOM    => 14_707_519_380_160_794],
      Large_Mixed           =>
        [Flyology_Events  => 73_813_906_086,
         Rapidjson_Events => 5_331_589_371_509_200_676,
         YYJSON_Validate  => 1_575_682_413_467_069,
         Simdjson_DOM     => 1_991_095_664_864_380_578,
         Rapidjson_DOM    => 1_991_095_664_864_380_578,
         Serde_JSON_DOM   => 1_253_508_055_003_964_072,
         Sonic_RS_DOM     => 1_253_508_055_003_964_072,
         SIMD_JSON_DOM    => 14_861_348_690_481_554_088],
      String_Heavy          =>
        [Flyology_Events  => 8_873_246_944,
         Rapidjson_Events => 3_011_324_490_366_836_340,
         YYJSON_Validate  => 2_870_394_108_044_677,
         Simdjson_DOM     => 2_020_601_278_710_818_328,
         Rapidjson_DOM    => 2_020_601_278_710_818_328,
         Serde_JSON_DOM   => 9_716_321_875_595_114_438,
         Sonic_RS_DOM     => 9_716_321_875_595_114_438,
         SIMD_JSON_DOM    => 9_716_321_875_595_114_438],
      Number_Heavy          =>
        [Flyology_Events  => 21_140_430_870,
         Rapidjson_Events => 15_988_613_297_870_433_626,
         YYJSON_Validate  => 791_932_098_761_679,
         Simdjson_DOM     => 5_059_056_587_818_847_578,
         Rapidjson_DOM    => 5_059_056_587_818_847_578,
         Serde_JSON_DOM   => 9_946_422_969_789_469_434,
         Sonic_RS_DOM     => 17_204_778_127_147_700_986,
         SIMD_JSON_DOM    => 7_526_971_250_673_423_098],
      Long_Mantissa_Numbers =>
        [Flyology_Events  => 43_497_406_486,
         Rapidjson_Events => 8_838_501_720_411_704_666,
         YYJSON_Validate  => 2_275_009_325_380_559,
         Simdjson_DOM     => 15_480_560_908_401_970_522,
         Rapidjson_DOM    => 15_480_560_908_401_970_522,
         Serde_JSON_DOM   => 17_204_778_127_158_113_018,
         Sonic_RS_DOM     => 8_435_840_929_912_484_602,
         SIMD_JSON_DOM    => 17_204_778_127_158_113_018],
      Deep_Nesting          =>
        [Flyology_Events  => 131_633,
         Rapidjson_Events => 12_436_566_234_458_118_276,
         YYJSON_Validate  => 1_904_761_146_831,
         Simdjson_DOM     => 8_618_953_658_589_723_787,
         Rapidjson_DOM    => 8_618_953_658_589_723_787,
         Serde_JSON_DOM   => 0,
         Sonic_RS_DOM     => 2_878_557_359_257_563_924,
         SIMD_JSON_DOM    => 14_279_272_144_332_258_731],
      Large_Array           =>
        [Flyology_Events  => 14_497_054_742,
         Rapidjson_Events => 17_886_235_169_332_514_138,
         YYJSON_Validate  => 635_612_504_208_335,
         Simdjson_DOM     => 12_315_279_721_192_951_130,
         Rapidjson_DOM    => 12_315_279_721_192_951_130,
         Serde_JSON_DOM   => 3_596_937_491_678_589_690,
         Sonic_RS_DOM     => 3_596_937_491_678_589_690,
         SIMD_JSON_DOM    => 1_177_485_772_562_838_266],
      Large_Object          =>
        [Flyology_Events  => 9_136_583_142,
         Rapidjson_Events => 3_035_274_609_342_381_669,
         YYJSON_Validate  => 826_633_250_799_213,
         Simdjson_DOM     => 16_579_500_030_859_027_471,
         Rapidjson_DOM    => 16_579_500_030_859_027_471,
         Serde_JSON_DOM   => 8_610_043_289_655_677_981,
         Sonic_RS_DOM     => 8_610_043_289_655_677_981,
         SIMD_JSON_DOM    => 8_610_043_289_655_677_981]];

   procedure Write_Fixtures (Directory : String) is
      package Stream_IO renames Ada.Streams.Stream_IO;
   begin
      for Kind in Fixture_Kind loop
         declare
            File : Stream_IO.File_Type;
         begin
            Stream_IO.Create
              (File,
               Stream_IO.Out_File,
               Directory & "/" & Unbounded.To_String (Fixtures (Kind).Name) & ".json");
            Stream_IO.Write (File, Fixtures (Kind).Data.all);
            Stream_IO.Close (File);
         exception
            when others =>
               if Stream_IO.Is_Open (File) then
                  Stream_IO.Close (File);
               end if;
               raise;
         end;
      end loop;
   end Write_Fixtures;

   function Supported (Using : Implementation; Kind : Fixture_Kind) return Boolean
   is (not (Using = Serde_JSON_DOM and then Kind = Deep_Nesting));

   function Lane_Name (Using : Implementation) return String
   is (case Using is
         when Flyology_Events | Rapidjson_Events => "parse_events",
         when YYJSON_Validate                    => "parse_validate",
         when others                             => "parse_dom");

   function Implementation_Name (Using : Implementation) return String
   is (case Using is
         when Flyology_Events  => "flyology_json",
         when Rapidjson_Events => "rapidjson-sax",
         when YYJSON_Validate  => "yyjson",
         when Simdjson_DOM     => "simdjson",
         when Rapidjson_DOM    => "rapidjson",
         when Serde_JSON_DOM   => "serde_json",
         when Sonic_RS_DOM     => "sonic-rs",
         when SIMD_JSON_DOM    => "simd-json");

   procedure Parse_Flyology
     (Kind              : Fixture_Kind;
      Value             : out U64;
      Event_Count       : out U64;
      Scalar_Count      : out U64;
      Member_Name_Count : out U64)
   is
      Item         : Fixture renames Fixtures (Kind);
      Parser       : Core.Parser renames Reusable_Flyology_Parsers (Kind).all;
      --  Benchmark-only caller storage.  This is an explicit experiment size,
      --  not a parser capacity or public API default.
      Event_Buffer : Core.Buffered_Event_Array (1 .. 256);
      Used         : Count := 0;
      Events       : U64 := 0;
      Scalars      : U64 := 0;
      Member_Names : U64 := 0;
   begin
      Value := 0;
      Event_Count := 0;
      Scalar_Count := 0;
      Member_Name_Count := 0;
      if Core.State (Parser) = Core.Uninitialized then
         Core.Initialize (Parser);
      elsif Core.State (Parser) = Core.Completed then
         Core.Reset (Parser);
      else
         raise Program_Error with "reusable Flyology parser is not terminal";
      end if;
      loop
         declare
            Result : Core.Buffered_Drain_Result;
         begin
            if Used < Item.Data'Length then
               Core.Buffered_Drain
                 (Parser,
                  Item.Data (Item.Data'First + Offset (Used) .. Item.Data'Last),
                  End_Of_Input => True,
                  Events       => Event_Buffer,
                  Result       => Result);
            else
               declare
                  Empty : Ada.Streams.Stream_Element_Array (1 .. 0);
               begin
                  Core.Buffered_Drain
                    (Parser, Empty, End_Of_Input => True, Events => Event_Buffer, Result => Result);
               end;
            end if;
            if Result.Consumed > Item.Data'Length - Used then
               raise Program_Error with "Flyology consumed beyond the fixture";
            end if;
            Used := Used + Result.Consumed;
            if Result.Produced > 0 then
               for Position in Count range 0 .. Result.Produced - 1 loop
                  declare
                     Event         : Core.Buffered_Event renames
                       Event_Buffer (Event_Buffer'First + Offset (Position));
                     Observed_Kind : constant Core.Event_Kind := Core.Buffered_Kind (Event);
                  begin
                     Events := Events + 1;
                     Value := Value + U64 (Core.Event_Kind'Pos (Observed_Kind) + 1);
                     Value := Value + U64 (Core.Buffered_Source (Event).First);
                     Value := Value + U64 (Core.Buffered_Source (Event).Octet_Length);
                     if Observed_Kind in Core.Number_End | Core.Null_Value | Core.Boolean_Value then
                        Scalars := Scalars + 1;
                     elsif Observed_Kind = Core.String_End then
                        Scalars := Scalars + 1;
                     elsif Observed_Kind = Core.Name_End then
                        Member_Names := Member_Names + 1;
                     end if;
                  end;
               end loop;
            end if;
            case Result.Stop is
               when Core.Drain_Buffer_Full                                                     =>
                  null;

               when Core.Drain_Document_Complete                                               =>
                  if Used /= Item.Data'Length then
                     raise Program_Error with "Flyology completed before the fixture end";
                  end if;
                  Value :=
                    Value xor Events * 3 xor Scalars * 5 xor Member_Names * 7 xor U64 (Item.Data'Length) * 11;
                  Event_Count := Events;
                  Scalar_Count := Scalars;
                  Member_Name_Count := Member_Names;
                  return;

               when Core.Drain_Need_Input | Core.Drain_Parse_Failed | Core.Drain_Call_Rejected =>
                  raise Program_Error with "Flyology rejected a valid comparison fixture";
            end case;
         end;
      end loop;
   end Parse_Flyology;

   procedure Run_Once (Using : Implementation; Kind : Fixture_Kind; Value : out U64) is
      Item : Fixture renames Fixtures (Kind);
   begin
      case Using is
         when Flyology_Events                               =>
            declare
               Ignored_Events       : U64;
               Ignored_Scalars      : U64;
               Ignored_Member_Names : U64;
            begin
               Parse_Flyology (Kind, Value, Ignored_Events, Ignored_Scalars, Ignored_Member_Names);
            end;

         when Rapidjson_Events                              =>
            declare
               Result : CPP.Parse_Observation;
            begin
               Rapidjson.Parse_Events (Item.Data.all, Result);
               if Result.Status /= CPP.Accepted or else Result.Input_Bytes /= U64 (Item.Data'Length) then
                  raise Program_Error with "RapidJSON SAX rejected a valid comparison fixture";
               end if;
               Value :=
                 Result.Checksum
                 xor Result.Event_Count * 3
                 xor Result.Scalar_Count * 5
                 xor Result.Member_Name_Count * 7
                 xor Result.Input_Bytes * 11;
            end;

         when YYJSON_Validate                               =>
            declare
               Result : YYJSON.Parse_Observation;
            begin
               YYJSON.Parse (Item.Data.all, Result);
               if Result.Status /= YYJSON.Accepted or else Result.Read_Octets /= U64 (Item.Data'Length) then
                  raise Program_Error
                    with
                      "yyjson observation changed for "
                      & Unbounded.To_String (Item.Name)
                      & ": values="
                      & Ada.Strings.Fixed.Trim (U64'Image (Result.Value_Count), Ada.Strings.Both);
               end if;
               Value := Result.Checksum xor Result.Value_Count * 3 xor Result.Read_Octets * 11;
            end;

         when Simdjson_DOM | Rapidjson_DOM                  =>
            declare
               Result : CPP.Parse_Observation;
            begin
               if Using = Simdjson_DOM then
                  Simdjson.Parse_DOM (Item.Simdjson_Storage.all, U64 (Item.Data'Length), Result);
               else
                  Rapidjson.Parse_DOM (Item.Data.all, Result);
               end if;
               if Result.Status /= CPP.Accepted or else Result.Input_Bytes /= U64 (Item.Data'Length) then
                  raise Program_Error with "C++ parser rejected a valid comparison fixture";
               end if;
               Value :=
                 Result.Checksum
                 xor Result.Event_Count * 3
                 xor Result.Scalar_Count * 5
                 xor Result.Member_Name_Count * 7
                 xor Result.Input_Bytes * 11;
            end;

         when Serde_JSON_DOM | Sonic_RS_DOM | SIMD_JSON_DOM =>
            declare
               Which  : constant Rust.Implementation :=
                 (case Using is
                    when Serde_JSON_DOM => Rust.Serde_JSON,
                    when Sonic_RS_DOM   => Rust.Sonic_RS,
                    when SIMD_JSON_DOM  => Rust.SIMD_JSON,
                    when others         => raise Program_Error);
               Result : Rust.Observation;
            begin
               Rust.Parse (Which, Item.Data.all, Result);
               if Result.Status /= Rust.Success then
                  raise Program_Error with "Rust parser rejected a valid comparison fixture";
               end if;
               Value := Result.Checksum xor U64 (Result.Items) * 3 xor U64 (Item.Data'Length) * 11;
            end;
      end case;
   end Run_Once;

   procedure Preflight_Counts (Using : Implementation; Kind : Fixture_Kind) is
      Item : Fixture renames Fixtures (Kind);
   begin
      case Using is
         when Flyology_Events                                 =>
            declare
               Value        : U64;
               Events       : U64;
               Scalars      : U64;
               Member_Names : U64;
            begin
               Parse_Flyology (Kind, Value, Events, Scalars, Member_Names);
               if Events /= Item.Flyology_Events
                 or else Scalars /= Item.Scalars
                 or else Member_Names /= Item.Member_Names
               then
                  raise Program_Error with "Flyology preflight observation changed";
               end if;
            end;

         when Rapidjson_Events | Simdjson_DOM | Rapidjson_DOM =>
            declare
               Result : CPP.Parse_Observation;
            begin
               if Using = Rapidjson_Events then
                  Rapidjson.Parse_Events (Item.Data.all, Result);
               elsif Using = Simdjson_DOM then
                  Simdjson.Parse_DOM (Item.Simdjson_Storage.all, U64 (Item.Data'Length), Result);
               else
                  Rapidjson.Parse_DOM (Item.Data.all, Result);
               end if;
               if Result.Status /= CPP.Accepted
                 or else Result.Event_Count /= Item.Logical_Events
                 or else Result.Scalar_Count /= Item.Scalars
                 or else Result.Member_Name_Count /= Item.Member_Names
                 or else Result.Input_Bytes /= U64 (Item.Data'Length)
               then
                  raise Program_Error with "C++ preflight observation changed";
               end if;
            end;

         when YYJSON_Validate                                 =>
            declare
               Result : YYJSON.Parse_Observation;
            begin
               YYJSON.Parse (Item.Data.all, Result);
               if Result.Status /= YYJSON.Accepted
                 or else Result.Value_Count /= Item.YYJSON_Values
                 or else Result.Read_Octets /= U64 (Item.Data'Length)
               then
                  raise Program_Error with "yyjson preflight observation changed";
               end if;
            end;

         when Serde_JSON_DOM | Sonic_RS_DOM | SIMD_JSON_DOM   =>
            declare
               Which  : constant Rust.Implementation :=
                 (case Using is
                    when Serde_JSON_DOM => Rust.Serde_JSON,
                    when Sonic_RS_DOM   => Rust.Sonic_RS,
                    when SIMD_JSON_DOM  => Rust.SIMD_JSON,
                    when others         => raise Program_Error);
               Result : Rust.Observation;
            begin
               Rust.Parse (Which, Item.Data.all, Result);
               if Result.Status /= Rust.Success or else U64 (Result.Items) /= Item.Logical_Events then
                  raise Program_Error with "Rust preflight observation changed";
               end if;
            end;
      end case;
   end Preflight_Counts;

   procedure Preflight (Using : Implementation; Kind : Fixture_Kind) is
      Value : U64;
   begin
      Preflight_Counts (Using, Kind);
      Run_Once (Using, Kind, Value);
      if Value /= Expected_Signature (Kind, Using) then
         raise Program_Error
           with
             "preflight signature changed for "
             & Implementation_Name (Using)
             & "/"
             & Unbounded.To_String (Fixtures (Kind).Name);
      end if;
   end Preflight;

   Current_Implementation : Implementation := Implementation'First;
   Current_Fixture        : Fixture_Kind := Fixture_Kind'First;

   procedure Run_Batch (Iterations : Flyology_Bench.Iteration_Count; Value : out U64) is
      One : U64;
   begin
      Value := 0;
      for Iteration in Flyology_Bench.Iteration_Count range 1 .. Iterations loop
         Run_Once (Current_Implementation, Current_Fixture, One);
         Value := Value + One;
      end loop;
   end Run_Batch;

   procedure Measure_Implementation is new
     Flyology_Bench.Measure_Result_Batched (Element => U64, Batch => Run_Batch);

   Base_Config : constant Flyology_Bench.Configuration :=
     (Warmup_Time               => 0.100,
      Measurement_Time          => 0.500,
      Maximum_Sampling_Time     => 0.0,
      Samples                   => 50,
      Minimum_Sample_Time       => 0.000_100,
      Maximum_Iterations        => Flyology_Bench.Positive_Iteration_Count'Last,
      Subtract_Timer_Cost       => False,
      Metrics                   => Flyology_Bench.Process_Resource_Metrics,
      Collect_Process_Telemetry => True,
      others                    => <>);

   Output_Mode             : constant String :=
     Ada.Environment_Variables.Value ("FLYOLOGY_JSON_BENCH_OUTPUT", Default => "terminal");
   Dump_Preflight          : constant Boolean :=
     Ada.Environment_Variables.Value ("FLYOLOGY_JSON_BENCH_PREFLIGHT_ONLY", Default => "false") = "true";
   Fixture_Directory       : constant String :=
     Ada.Environment_Variables.Value ("FLYOLOGY_JSON_BENCH_FIXTURE_DIRECTORY", Default => "");
   Selected_Implementation : constant String :=
     Ada.Environment_Variables.Value ("FLYOLOGY_JSON_BENCH_IMPLEMENTATION", Default => "");
   Selected_Fixture        : constant String :=
     Ada.Environment_Variables.Value ("FLYOLOGY_JSON_BENCH_FIXTURE", Default => "");

   function Is_Selected (Using : Implementation) return Boolean
   is (Selected_Implementation'Length = 0 or else Selected_Implementation = Implementation_Name (Using));

   function Is_Selected (Kind : Fixture_Kind) return Boolean
   is (Selected_Fixture'Length = 0 or else Selected_Fixture = Unbounded.To_String (Fixtures (Kind).Name));

   function Known_Implementation return Boolean is
   begin
      if Selected_Implementation'Length = 0 then
         return True;
      end if;
      for Using in Implementation loop
         if Selected_Implementation = Implementation_Name (Using) then
            return True;
         end if;
      end loop;
      return False;
   end Known_Implementation;

   function Known_Fixture return Boolean is
   begin
      if Selected_Fixture'Length = 0 then
         return True;
      end if;
      for Kind in Fixture_Kind loop
         if Selected_Fixture = Unbounded.To_String (Fixtures (Kind).Name) then
            return True;
         end if;
      end loop;
      return False;
   end Known_Fixture;

   function Has_Selected_Supported_Population return Boolean is
   begin
      for Kind in Fixture_Kind loop
         for Using in Implementation loop
            if Is_Selected (Kind) and then Is_Selected (Using) and then Supported (Using, Kind) then
               return True;
            end if;
         end loop;
      end loop;
      return False;
   end Has_Selected_Supported_Population;

begin
   if Output_Mode not in "terminal" | "csv" | "metrics_csv" | "json" then
      raise Constraint_Error with "FLYOLOGY_JSON_BENCH_OUTPUT must be terminal, csv, metrics_csv, or json";
   end if;

   if not Known_Implementation then
      raise Constraint_Error with "unknown FLYOLOGY_JSON_BENCH_IMPLEMENTATION";
   end if;

   if not Known_Fixture then
      raise Constraint_Error with "unknown FLYOLOGY_JSON_BENCH_FIXTURE";
   end if;

   if not Has_Selected_Supported_Population then
      raise Constraint_Error with "selected comparison population is unsupported";
   end if;

   if Fixture_Directory'Length > 0 then
      Write_Fixtures (Fixture_Directory);
   end if;

   if Dump_Preflight then
      for Kind in Fixture_Kind loop
         for Using in Implementation loop
            if Is_Selected (Kind) and then Is_Selected (Using) then
               if Supported (Using, Kind) then
                  declare
                     Value : U64;
                  begin
                     Preflight (Using, Kind);
                     Run_Once (Using, Kind, Value);
                     Ada.Text_IO.Put_Line
                       ("implementation="
                        & Implementation_Name (Using)
                        & " fixture="
                        & Unbounded.To_String (Fixtures (Kind).Name)
                        & " value="
                        & Ada.Strings.Fixed.Trim (U64'Image (Value), Ada.Strings.Both));
                  end;
               end if;
            end if;
         end loop;
      end loop;
      return;
   end if;

   if Output_Mode = "csv" then
      Flyology_Bench.Reporters.Put_CSV_Header;
   elsif Output_Mode = "metrics_csv" then
      Flyology_Bench.Reporters.Put_Metrics_CSV_Header;
   end if;

   for Kind in Fixture_Kind loop
      for Using in Implementation loop
         if Is_Selected (Kind) and then Is_Selected (Using) then
            if Supported (Using, Kind) then
               declare
                  Item   : Fixture renames Fixtures (Kind);
                  Result : Flyology_Bench.Measurement;
                  Name   : constant String :=
                    "comparison/lane="
                    & Lane_Name (Using)
                    & "/implementation="
                    & Implementation_Name (Using)
                    & "/fixture="
                    & Unbounded.To_String (Item.Name)
                    & "/bytes="
                    & Trimmed_Image (Natural (Item.Data'Length));
                  Config : constant Flyology_Bench.Configuration :=
                    (if Output_Mode = "terminal"
                     then Flyology_Bench.Reporters.Terminal_Mode (Base_Config, Name)
                     else Base_Config);
               begin
                  Preflight (Using, Kind);
                  Current_Implementation := Using;
                  Current_Fixture := Kind;
                  Measure_Implementation (Config => Config, Result => Result);
                  if Output_Mode = "terminal" then
                     Flyology_Bench.Reporters.Put_Console (Name, Result);
                     Ada.Text_IO.Put_Line
                       ("  median throughput:"
                        & Long_Float'Image
                            (Long_Float (Item.Data'Length)
                             * 1_000_000_000.0
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
            else
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "skip lane="
                  & Lane_Name (Using)
                  & " implementation="
                  & Implementation_Name (Using)
                  & " fixture="
                  & Unbounded.To_String (Fixtures (Kind).Name)
                  & " reason=declared_depth_limit");
            end if;
         end if;
      end loop;
   end loop;
end Flyology_JSON.Comparison_Benchmark;
