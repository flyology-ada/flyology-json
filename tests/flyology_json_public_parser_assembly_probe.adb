with Ada.Streams;
with Flyology_JSON.Errors;
with Flyology_JSON.Parsing;
with Flyology_JSON.Profiles;
with Interfaces;
with System;

procedure Flyology_JSON_Public_Parser_Assembly_Probe is
   package Profiles renames Flyology_JSON.Profiles;
   package Strict_Parsing is new Flyology_JSON.Parsing (Profiles.Reject_Duplicates);
   package Preserve_Parsing is new Flyology_JSON.Parsing (Profiles.Preserve_Unchecked);

   use type Interfaces.Unsigned_64;

   subtype U64 is Interfaces.Unsigned_64;

   generic
      Duplicate_Handling : Profiles.Duplicate_Policy;
      with package Parser_API is new Flyology_JSON.Parsing (Duplicate_Handling);
   procedure Probe_Mode (Checksum : in out U64);

   procedure Probe_Mode (Checksum : in out U64) is
      use type Ada.Streams.Stream_Element_Count;
      use type Parser_API.Decoded_Fragment_Kind;
      use type Parser_API.Drain_Stop;
      use type Parser_API.Event_Kind;
      use type Parser_API.Slice_Status;

      subtype Count is Ada.Streams.Stream_Element_Count;
      subtype Offset is Ada.Streams.Stream_Element_Offset;

      Profile : constant Profiles.Parser_Profile :=
        (Syntax        => (Family => Profiles.RFC_8259, Version => 1),
         Unicode       => (Family => Profiles.Unicode_Scalars, Version => 1),
         Compatibility => (Family => Profiles.No_Extensions, Version => 1),
         BOM           => Profiles.Reject_BOM,
         Duplicates    => Duplicate_Handling,
         Top_Level     => Profiles.Accept_Any_Value);

      Input : constant Ada.Streams.Stream_Element_Array :=
        [41 => Character'Pos ('['),
         42 => Character'Pos ('n'),
         43 => Character'Pos ('u'),
         44 => Character'Pos ('l'),
         45 => Character'Pos ('l'),
         46 => Character'Pos (','),
         47 => Character'Pos ('t'),
         48 => Character'Pos ('r'),
         49 => Character'Pos ('u'),
         50 => Character'Pos ('e'),
         51 => Character'Pos (','),
         52 => Character'Pos ('"'),
         53 => Character'Pos ('\'),
         54 => Character'Pos ('u'),
         55 => Character'Pos ('2'),
         56 => Character'Pos ('0'),
         57 => Character'Pos ('A'),
         58 => Character'Pos ('C'),
         59 => Character'Pos ('"'),
         60 => Character'Pos (','),
         61 => Character'Pos ('0'),
         62 => Character'Pos (']')];
      Parser : Parser_API.Parser
        (Maximum_Depth => 1, Name_Octet_Capacity => 0, Name_Capacity => 0);
      Events     : Parser_API.Event_Array (-7 .. 16);
      Result     : Parser_API.Drain_Result;
      Diagnostic : Flyology_JSON.Errors.Diagnostic;
      Used       : Count := 0;
   begin
      if Parser_API.Event'Size /= 24 * System.Storage_Unit
        or else Parser_API.Event_Array'Component_Size /= 24 * System.Storage_Unit
      then
         raise Program_Error with "reviewed 64-bit event footprint changed";
      end if;

      Parser_API.Initialize (Parser, Profile, Diagnostic);
      loop
         declare
            First : constant Offset := Input'First + Offset (Used);
         begin
            Parser_API.Drain
              (Parser,
               Input (First .. Input'Last),
               End_Of_Input => True,
               Events       => Events,
               Result       => Result);

            if Result.Produced > 0 then
               for Published in Count range 0 .. Result.Produced - 1 loop
                  declare
                     Item : Parser_API.Event renames Events (Events'First + Offset (Published));
                     Source : constant Parser_API.Source_Range := Parser_API.Source (Item);
                  begin
                     Checksum :=
                       Checksum
                       + U64 (Parser_API.Event_Kind'Pos (Parser_API.Kind (Item)) + 1)
                       + U64 (Source.First)
                       + U64 (Source.Octet_Length);
                     if Parser_API.Has_Raw_Slice (Item) then
                        declare
                           Slice  : Parser_API.Chunk_Range;
                           Status : Parser_API.Slice_Status;
                        begin
                           Parser_API.Resolve_Raw_Range
                             (Item, Result.Input_Origin, Input'Length - Used, Slice, Status);
                           if Status = Parser_API.Slice_Resolved then
                              Checksum := Checksum + U64 (Slice.Octet_Length);
                           end if;
                        end;
                     end if;
                     if Parser_API.Decoded_Kind (Item) /= Parser_API.No_Decoded_Fragment then
                        Checksum := Checksum + U64 (Parser_API.Decoded_Source (Item).Octet_Length);
                        if Parser_API.Decoded_Kind (Item) = Parser_API.Decoded_Inline_Scalar then
                           declare
                              Scalar : constant Parser_API.Inline_Scalar :=
                                Parser_API.Decoded_Scalar (Item);
                           begin
                              Checksum := Checksum + U64 (Scalar.Length) + U64 (Scalar.Octets (1));
                           end;
                        end if;
                     end if;
                     if Parser_API.Kind (Item) = Parser_API.Boolean_Value
                       and then Parser_API.Boolean_Data (Item)
                     then
                        Checksum := Checksum + 1;
                     end if;
                  end;
               end loop;
            end if;
            Used := Used + Result.Consumed;
         end;
         exit when Result.Stop = Parser_API.Drain_Document_Complete;
         if Result.Stop not in Parser_API.Output_Full | Parser_API.Drain_Need_Input then
            raise Program_Error with "public assembly probe parse failed";
         end if;
      end loop;

      if Used /= Input'Length then
         raise Program_Error with "public assembly probe did not consume its input";
      end if;
   end Probe_Mode;

   procedure Probe_Strict is new Probe_Mode
     (Duplicate_Handling => Profiles.Reject_Duplicates,
      Parser_API         => Strict_Parsing);
   procedure Probe_Preserve is new Probe_Mode
     (Duplicate_Handling => Profiles.Preserve_Unchecked,
      Parser_API         => Preserve_Parsing);

   pragma No_Inline (Probe_Strict);
   pragma No_Inline (Probe_Preserve);

   Checksum : U64 := 0 with Volatile;

begin
   Probe_Strict (Checksum);
   Probe_Preserve (Checksum);

   if Checksum = 0 then
      raise Program_Error with "public assembly probe result was not observed";
   end if;
end Flyology_JSON_Public_Parser_Assembly_Probe;
