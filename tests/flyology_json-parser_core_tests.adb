with Ada.Streams;
with Flyology_JSON.Parser_Core;
with Interfaces;

procedure Flyology_JSON.Parser_Core_Tests is

   package Core renames Flyology_JSON.Parser_Core;

   use type Ada.Streams.Stream_Element_Count;
   use type Core.Byte_Offset;
   use type Core.Decoded_Fragment_Kind;
   use type Core.Diagnostic;
   use type Core.Error_Code;
   use type Core.Event_Kind;
   use type Core.Next_Outcome;
   use type Core.Parser_State;
   use type Core.Source_Range;
   use type Interfaces.Unsigned_32;

   subtype Count is Ada.Streams.Stream_Element_Count;
   subtype Offset is Ada.Streams.Stream_Element_Offset;

   type Event_Counts is array (Core.Event_Kind) of Natural;

   --  Fixture/campaign storage only; this is not a parser capacity or API default.
   Test_Text_Capacity     : constant := 8_192;
   Test_Fragment_Capacity : constant := 64;
   Test_Name_Octet_Capacity : constant := Test_Text_Capacity;
   Test_Name_Capacity       : constant := 256;

   type Fragment_Observation is record
      Kind           : Core.Event_Kind := Core.String_Fragment;
      Source         : Core.Source_Range := (First => 0, Octet_Length => 0);
      Decoded_Kind   : Core.Decoded_Fragment_Kind := Core.No_Decoded_Fragment;
      Decoded_Source : Core.Source_Range := (First => 0, Octet_Length => 0);
      Decoded_Length : Natural := 0;
   end record;

   type Fragment_Observations is
     array (Positive range 1 .. Test_Fragment_Capacity) of Fragment_Observation;

   type Observation is record
      Outcome                : Core.Next_Outcome := Core.Need_Input;
      Diagnostic             : Core.Diagnostic := (Code => Core.No_Error, Offset => 0);
      Events                 : Event_Counts := [others => 0];
      Number_Fragment_Octets : Count := 0;
      Number_Text            : String (1 .. Test_Text_Capacity) := [others => ASCII.NUL];
      Number_Length          : Natural := 0;
      Raw_Prefix             : String (1 .. Test_Text_Capacity) := [others => ASCII.NUL];
      Raw_Prefix_Length      : Natural := 0;
      Name_Text              : String (1 .. Test_Text_Capacity) := [others => ASCII.NUL];
      Name_Length            : Natural := 0;
      String_Text            : String (1 .. Test_Text_Capacity) := [others => ASCII.NUL];
      String_Length          : Natural := 0;
      Fragments              : Fragment_Observations;
      Fragment_Count         : Natural := 0;
      Raw_Associations       : Natural := 0;
      Text_Open              : Boolean := False;
      Text_Next_Source       : Core.Byte_Offset := 0;
      Number_Open            : Boolean := False;
      Number_Next_Source     : Core.Byte_Offset := 0;
   end record;

   procedure Check (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Check;

   function To_Input (Text : String; First : Offset) return Ada.Streams.Stream_Element_Array is
      Result : Ada.Streams.Stream_Element_Array
        (First .. First + Offset (Text'Length) - 1);
   begin
      if Text'Length > 0 then
         for Position in 0 .. Text'Length - 1 loop
            Result (First + Offset (Position)) :=
              Ada.Streams.Stream_Element (Character'Pos (Text (Text'First + Position)));
         end loop;
      end if;
      return Result;
   end To_Input;

   procedure Append
     (Target : in out String;
      Length : in out Natural;
      Value  : Ada.Streams.Stream_Element) is
   begin
      Check (Length < Target'Length, "test observation text capacity exhausted");
      Length := Length + 1;
      Target (Target'First + Length - 1) := Character'Val (Value);
   end Append;

   procedure Observe_Event
     (Item              : Core.Event;
      Exact_Input       : Ada.Streams.Stream_Element_Array;
      Exact_Input_First : Core.Byte_Offset;
      Seen              : in out Observation)
   is
      procedure Append_Decoded (Value : Ada.Streams.Stream_Element) is
      begin
         if Item.Kind = Core.Name_Fragment then
            Append (Seen.Name_Text, Seen.Name_Length, Value);
         elsif Item.Kind = Core.String_Fragment then
            Append (Seen.String_Text, Seen.String_Length, Value);
         else
            Check (False, "decoded payload appeared on a non-text event");
         end if;
      end Append_Decoded;
   begin
      Seen.Events (Item.Kind) := Seen.Events (Item.Kind) + 1;

      case Item.Kind is
         when Core.Name_Begin | Core.String_Begin =>
            Check (not Seen.Text_Open, "text token began while another text token was open");
            Check (Item.Source.Octet_Length = 1, "text begin does not cover its quote");
            Seen.Text_Open := True;
            Seen.Text_Next_Source := Item.Source.First + Item.Source.Octet_Length;

         when Core.Name_Fragment | Core.String_Fragment =>
            Check (Seen.Text_Open, "text fragment has no open text token");
            Check
              (Item.Source.First = Seen.Text_Next_Source,
               "text raw source fragments have a gap, overlap, or reordering");
            Seen.Text_Next_Source := Seen.Text_Next_Source + Item.Source.Octet_Length;

         when Core.Name_End | Core.String_End =>
            Check (Seen.Text_Open, "text end has no open text token");
            Check (Item.Source.First = Seen.Text_Next_Source, "text end is not source-contiguous");
            Check (Item.Source.Octet_Length = 1, "text end does not cover its quote");
            Seen.Text_Next_Source := Seen.Text_Next_Source + Item.Source.Octet_Length;
            Seen.Text_Open := False;

         when Core.Number_Begin =>
            Check (not Seen.Number_Open, "number began while another number was open");
            Check (Item.Source.Octet_Length = 0, "number begin unexpectedly consumed source");
            Seen.Number_Open := True;
            Seen.Number_Next_Source := Item.Source.First;

         when Core.Number_Fragment =>
            Check (Seen.Number_Open, "number fragment has no open number token");
            Check
              (Item.Source.First = Seen.Number_Next_Source,
               "number source fragments have a gap, overlap, or reordering");
            Seen.Number_Next_Source := Seen.Number_Next_Source + Item.Source.Octet_Length;

         when Core.Number_End =>
            Check (Seen.Number_Open, "number end has no open number token");
            Check (Item.Source.First = Seen.Number_Next_Source, "number end source is not contiguous");
            Check (Item.Source.Octet_Length = 0, "number end unexpectedly consumed source");
            Seen.Number_Open := False;

         when others =>
            null;
      end case;

      if Item.Has_Raw_Slice then
         Check
           (Item.Raw_Slice.First_Count <= Exact_Input'Length,
            "raw slice starts beyond the exact Next input");
         Check
           (Item.Raw_Slice.Octet_Length <= Exact_Input'Length - Item.Raw_Slice.First_Count,
            "raw slice ends beyond the exact Next input");
         Check
           (Item.Source.First = Exact_Input_First + Core.Byte_Offset (Item.Raw_Slice.First_Count),
            "raw slice is associated with the wrong source byte");
         Check
           (Item.Source.Octet_Length = Core.Byte_Offset (Item.Raw_Slice.Octet_Length),
            "raw slice and source lengths disagree");
         Seen.Raw_Associations := Seen.Raw_Associations + 1;

         if Item.Kind in Core.Name_Fragment | Core.String_Fragment | Core.Number_Fragment then
            for Position in Count range 0 .. Item.Raw_Slice.Octet_Length - 1 loop
               Append
                 (Seen.Raw_Prefix,
                  Seen.Raw_Prefix_Length,
                  Exact_Input
                    (Exact_Input'First
                     + Offset (Item.Raw_Slice.First_Count)
                     + Offset (Position)));

               if Item.Kind = Core.Number_Fragment then
                  Append
                    (Seen.Number_Text,
                     Seen.Number_Length,
                     Exact_Input
                       (Exact_Input'First
                        + Offset (Item.Raw_Slice.First_Count)
                        + Offset (Position)));
               end if;
            end loop;
         end if;
      end if;

      case Item.Decoded_Kind is
         when Core.No_Decoded_Fragment =>
            null;

         when Core.Decoded_Is_Raw_Range =>
            Check (Item.Has_Raw_Slice, "decoded raw range has no exact input association");
            Check (Item.Decoded_Source = Item.Source, "decoded raw source is not the event source");
            Check
              (Item.Raw_Slice.Octet_Length = Count (Item.Decoded_Source.Octet_Length),
               "decoded raw range lengths disagree");

            for Position in Count range 0 .. Item.Raw_Slice.Octet_Length - 1 loop
               Append_Decoded
                 (Exact_Input
                    (Exact_Input'First
                     + Offset (Item.Raw_Slice.First_Count)
                     + Offset (Position)));
            end loop;

         when Core.Decoded_Inline_Scalar =>
            Check (Item.Has_Raw_Slice, "inline scalar omitted its current-call raw range");
            Check
              (Item.Decoded_Source.Octet_Length >= Item.Source.Octet_Length,
               "inline decoded source is shorter than its current-call raw span");
            Check
              (Item.Source.First >= Item.Decoded_Source.First,
               "inline raw span precedes the complete decoded source");
            Check
              (Item.Source.First + Item.Source.Octet_Length
                 = Item.Decoded_Source.First + Item.Decoded_Source.Octet_Length,
               "inline raw span does not complete the decoded source");
            Check (Item.Decoded.Length in 1 .. 4, "inline scalar length is invalid");
            for Position in 1 .. Item.Decoded.Length loop
               Append_Decoded (Item.Decoded.Octets (Position));
            end loop;
      end case;

      if Item.Kind in Core.Name_Fragment | Core.String_Fragment then
         Seen.Fragment_Count := Seen.Fragment_Count + 1;
         if Seen.Fragment_Count <= Seen.Fragments'Length then
            Seen.Fragments (Seen.Fragment_Count) :=
              (Kind           => Item.Kind,
               Source         => Item.Source,
               Decoded_Kind   => Item.Decoded_Kind,
               Decoded_Source => Item.Decoded_Source,
               Decoded_Length => Item.Decoded.Length);
         end if;
      end if;
   end Observe_Event;

   procedure Drain
     (Parser      : in out Core.Parser;
      Input       : Ada.Streams.Stream_Element_Array;
      Input_First : Core.Byte_Offset;
      Final_Input : Boolean;
      Seen        : in out Observation)
   is
      Used   : Count := 0;
      Result : Core.Next_Result;
   begin
      loop
         if Used < Input'Length then
            declare
               First       : constant Offset := Input'First + Offset (Used);
               Exact_First : constant Core.Byte_Offset := Input_First + Core.Byte_Offset (Used);
            begin
               Core.Next (Parser, Input (First .. Input'Last), Final_Input, Result);
               if Result.Outcome = Core.Event_Ready then
                  Observe_Event (Result.Item, Input (First .. Input'Last), Exact_First, Seen);
               end if;
            end;
         else
            declare
               Empty : Ada.Streams.Stream_Element_Array (1 .. 0);
            begin
               Core.Next (Parser, Empty, Final_Input, Result);
               if Result.Outcome = Core.Event_Ready then
                  Observe_Event (Result.Item, Empty, Input_First + Core.Byte_Offset (Used), Seen);
               end if;
            end;
         end if;

         Check (Result.Consumed <= Input'Length - Used, "consumed count exceeds supplied suffix");
         Used := Used + Result.Consumed;

         case Result.Outcome is
            when Core.Event_Ready =>
               if Result.Item.Kind = Core.Number_Fragment then
                  Seen.Number_Fragment_Octets :=
                    Seen.Number_Fragment_Octets + Result.Item.Raw_Slice.Octet_Length;
               end if;
            when Core.Need_Input =>
               Check (Used = Input'Length, "Need_Input left an unconsumed suffix");
               Seen.Outcome := Result.Outcome;
               exit;
            when Core.Document_Complete | Core.Parse_Failed | Core.Call_Rejected =>
               Seen.Outcome := Result.Outcome;
               Seen.Diagnostic := Result.Diagnostic;
               exit;
         end case;
      end loop;
   end Drain;

   function Parse
     (Text          : String;
      Split         : Natural;
      Maximum_Depth : Natural := 8) return Observation
   is
      Parser : Core.Parser (Maximum_Depth, Test_Name_Octet_Capacity, Test_Name_Capacity);
      Seen   : Observation;
   begin
      Core.Initialize (Parser);

      if Split > 0 then
         declare
            Prefix : constant Ada.Streams.Stream_Element_Array :=
              To_Input (Text (Text'First .. Text'First + Split - 1), -7);
         begin
            Drain (Parser, Prefix, 0, False, Seen);
            if Seen.Outcome /= Core.Need_Input then
               return Seen;
            end if;
         end;
      end if;

      declare
         Suffix : constant Ada.Streams.Stream_Element_Array :=
           To_Input (Text (Text'First + Split .. Text'Last), 11);
      begin
         Drain (Parser, Suffix, Core.Byte_Offset (Split), True, Seen);
      end;

      return Seen;
   end Parse;

   function Parse_One_Byte (Text : String) return Observation is
      Parser : Core.Parser (8, Test_Name_Octet_Capacity, Test_Name_Capacity);
      Seen   : Observation;
   begin
      Core.Initialize (Parser);

      if Text'Length = 0 then
         declare
            Empty : constant Ada.Streams.Stream_Element_Array := To_Input (Text, -23);
         begin
            Drain (Parser, Empty, 0, True, Seen);
         end;
      else
         for Position in 0 .. Text'Length - 1 loop
            declare
               Empty : constant Ada.Streams.Stream_Element_Array :=
                 To_Input ("", Offset (-47 + Position));
            begin
               Drain (Parser, Empty, Core.Byte_Offset (Position), False, Seen);
               if Seen.Outcome /= Core.Need_Input then
                  return Seen;
               end if;
            end;

            declare
               One : constant Ada.Streams.Stream_Element_Array :=
                 To_Input
                   (Text (Text'First + Position .. Text'First + Position),
                    Offset (-23 + Position));
            begin
               Drain
                 (Parser,
                  One,
                  Core.Byte_Offset (Position),
                  Position = Text'Length - 1,
                  Seen);
               if Position < Text'Length - 1 and then Seen.Outcome /= Core.Need_Input then
                  return Seen;
               end if;
            end;
         end loop;
      end if;

      return Seen;
   end Parse_One_Byte;

   function Parse_Randomized
     (Text : String;
      Seed : Interfaces.Unsigned_32) return Observation
   is
      --  Campaign data only.  These LCG coefficients do not affect parser behavior.
      Generator : Interfaces.Unsigned_32 := Seed;
      Parser    : Core.Parser (8, Test_Name_Octet_Capacity, Test_Name_Capacity);
      Seen      : Observation;
      Position  : Natural := 0;
   begin
      Core.Initialize (Parser);

      while Position < Text'Length loop
         Generator := Generator * 1_664_525 + 1_013_904_223;

         if (Generator and 3) = 0 then
            declare
               Empty : constant Ada.Streams.Stream_Element_Array :=
                 To_Input ("", Offset (-41 + Position));
            begin
               Drain (Parser, Empty, Core.Byte_Offset (Position), False, Seen);
               Check (Seen.Outcome = Core.Need_Input, "empty chunk changed parser progress");
            end;
         end if;

         declare
            Remaining : constant Natural := Text'Length - Position;
            Requested : constant Natural := Natural (Generator mod 17) + 1;
            Length    : constant Natural := Natural'Min (Remaining, Requested);
            Chunk     : constant Ada.Streams.Stream_Element_Array :=
              To_Input
                (Text (Text'First + Position .. Text'First + Position + Length - 1),
                 Offset (37 + Position));
         begin
            Drain
              (Parser,
               Chunk,
               Core.Byte_Offset (Position),
               Position + Length = Text'Length,
               Seen);
            Position := Position + Length;
            if Position < Text'Length then
               if Seen.Outcome /= Core.Need_Input then
                  return Seen;
               end if;
            end if;
         end;
      end loop;

      return Seen;
   end Parse_Randomized;

   function Parse_Partition (Text : String; Boundaries : Interfaces.Unsigned_32) return Observation is
      Parser      : Core.Parser (8, Test_Name_Octet_Capacity, Test_Name_Capacity);
      Seen        : Observation;
      Chunk_First : Natural := 0;
   begin
      Check (Text'Length > 0, "partition schedule requires a nonempty fixture");
      Core.Initialize (Parser);

      for Position in 0 .. Text'Length - 1 loop
         if Position = Text'Length - 1
           or else (Boundaries and Interfaces.Shift_Left (1, Position)) /= 0
         then
            declare
               Chunk : constant Ada.Streams.Stream_Element_Array :=
                 To_Input
                   (Text
                      (Text'First + Chunk_First
                       .. Text'First + Position),
                    Offset (-31 + Chunk_First));
            begin
               Drain
                 (Parser,
                  Chunk,
                  Core.Byte_Offset (Chunk_First),
                  Position = Text'Length - 1,
                  Seen);
               if Position < Text'Length - 1 then
                  Check (Seen.Outcome = Core.Need_Input, "partition schedule terminated early");
               end if;
            end;
            Chunk_First := Position + 1;
         end if;
      end loop;

      return Seen;
   end Parse_Partition;

   procedure Check_All_Partitions (Text : String; Expected : String) is
      Last_Mask : constant Interfaces.Unsigned_32 :=
        Interfaces.Shift_Left (1, Text'Length - 1) - 1;
   begin
      Check (Text'Length in 1 .. 31, "partition fixture exceeds the test mask");
      for Mask in Interfaces.Unsigned_32 range 0 .. Last_Mask loop
         declare
            Seen : constant Observation := Parse_Partition (Text, Mask);
         begin
            Check (Seen.Outcome = Core.Document_Complete, "valid partition rejected");
            Check
              (Seen.String_Text (1 .. Seen.String_Length) = Expected,
               "partition changed decoded text");
         end;
      end loop;
   end Check_All_Partitions;

   procedure Check_Valid_Splits
     (Text                     : String;
      Expected_Number_Octets   : Count := 0;
      Expected_Number_Text     : String := "";
      Expected_Arrays          : Natural := 0;
      Expected_Objects         : Natural := 0)
   is
      procedure Check_Observation (Seen : Observation; Schedule : String) is
      begin
         Check (Seen.Outcome = Core.Document_Complete, Schedule & " rejected valid input: " & Text);
         Check (not Seen.Text_Open, Schedule & " left a text token open");
         Check (not Seen.Number_Open, Schedule & " left a number token open");
         Check (Seen.Events (Core.Document_Begin) = 1, Schedule & " omitted document begin");
         Check (Seen.Events (Core.Document_End) = 1, Schedule & " omitted document end");
         Check
           (Seen.Number_Fragment_Octets = Expected_Number_Octets,
            Schedule & " changed number fragment length");
         Check
           (Seen.Number_Text (1 .. Seen.Number_Length) = Expected_Number_Text,
            Schedule & " changed exact number lexeme bytes");
         Check (Seen.Events (Core.Array_Begin) = Expected_Arrays, Schedule & " changed array count");
         Check (Seen.Events (Core.Array_End) = Expected_Arrays, Schedule & " changed array count");
         Check (Seen.Events (Core.Object_Begin) = Expected_Objects, Schedule & " changed object count");
         Check (Seen.Events (Core.Object_End) = Expected_Objects, Schedule & " changed object count");
      end Check_Observation;
   begin
      for Split in 0 .. Text'Length loop
         Check_Observation (Parse (Text, Split), "two-chunk split" & Natural'Image (Split));
      end loop;

      Check_Observation (Parse_One_Byte (Text), "one-byte schedule");
      for Seed in Interfaces.Unsigned_32 range 1 .. 16 loop
         Check_Observation (Parse_Randomized (Text, Seed), "random schedule" & Seed'Image);
      end loop;
   end Check_Valid_Splits;

   procedure Check_Valid_Text_Splits
     (Text             : String;
      Expected_Name    : String := "";
      Expected_String  : String := "";
      Expected_Names   : Natural := 0;
      Expected_Strings : Natural := 1)
   is
      procedure Check_Observation (Seen : Observation; Schedule : String) is
      begin
         Check (Seen.Outcome = Core.Document_Complete, Schedule & " rejected valid text");
         Check (not Seen.Text_Open, Schedule & " left text source coverage incomplete");
         Check (Seen.Events (Core.Name_Begin) = Expected_Names, Schedule & " changed name count");
         Check (Seen.Events (Core.Name_End) = Expected_Names, Schedule & " changed name count");
         Check (Seen.Events (Core.String_Begin) = Expected_Strings, Schedule & " changed string count");
         Check (Seen.Events (Core.String_End) = Expected_Strings, Schedule & " changed string count");
         Check
           (Seen.Name_Text (1 .. Seen.Name_Length) = Expected_Name,
            Schedule & " changed decoded name");
         Check
           (Seen.String_Text (1 .. Seen.String_Length) = Expected_String,
            Schedule & " changed decoded string");
         Check (Seen.Raw_Associations > 0, Schedule & " emitted no checked raw association");
      end Check_Observation;
   begin
      for Split in 0 .. Text'Length loop
         Check_Observation (Parse (Text, Split), "two-chunk split" & Natural'Image (Split));
      end loop;

      Check_Observation (Parse_One_Byte (Text), "one-byte schedule");
      for Seed in Interfaces.Unsigned_32 range 1 .. 16 loop
         Check_Observation (Parse_Randomized (Text, Seed), "random schedule" & Seed'Image);
      end loop;
   end Check_Valid_Text_Splits;

   procedure Check_Invalid
     (Text   : String;
      Code   : Core.Error_Code;
      At_Byte : Core.Byte_Offset)
   is
   begin
      for Split in 0 .. Text'Length loop
         declare
            Seen : constant Observation := Parse (Text, Split);
         begin
            Check (Seen.Outcome = Core.Parse_Failed, "invalid document accepted: " & Text);
            Check (Seen.Diagnostic.Code = Code, "wrong error code for: " & Text);
            Check (Seen.Diagnostic.Offset = At_Byte, "wrong error offset for: " & Text);
         end;
      end loop;

      declare
         Seen : constant Observation := Parse_One_Byte (Text);
      begin
         Check (Seen.Outcome = Core.Parse_Failed, "one-byte schedule accepted invalid input");
         Check (Seen.Diagnostic.Code = Code, "one-byte schedule changed the error code");
         Check (Seen.Diagnostic.Offset = At_Byte, "one-byte schedule changed the error offset");
      end;

      for Seed in Interfaces.Unsigned_32 range 1 .. 8 loop
         declare
            Seen : constant Observation := Parse_Randomized (Text, Seed);
         begin
            Check (Seen.Outcome = Core.Parse_Failed, "random schedule accepted invalid input");
            Check (Seen.Diagnostic.Code = Code, "random schedule changed the error code");
            Check (Seen.Diagnostic.Offset = At_Byte, "random schedule changed the error offset");
         end;
      end loop;
   end Check_Invalid;

   procedure Check_Duplicate
     (Text    : String;
      At_Byte : Core.Byte_Offset;
      Expected_Name_Begins : Natural := 2;
      Expected_Name_Ends   : Natural := 1) is
      procedure Check_Observation (Seen : Observation; Schedule : String) is
      begin
         Check (Seen.Outcome = Core.Parse_Failed, Schedule & " accepted a duplicate name");
         Check (Seen.Diagnostic.Code = Core.Duplicate_Name, Schedule & " changed duplicate status");
         Check (Seen.Diagnostic.Offset = At_Byte, Schedule & " changed duplicate offset");
         Check
           (Seen.Events (Core.Name_Begin) = Expected_Name_Begins,
            Schedule & " changed provisional name begins");
         Check
           (Seen.Events (Core.Name_End) = Expected_Name_Ends,
            Schedule & "published the rejecting Name_End");
      end Check_Observation;
   begin
      for Split in 0 .. Text'Length loop
         Check_Observation (Parse (Text, Split), "duplicate split" & Natural'Image (Split));
      end loop;
      Check_Observation (Parse_One_Byte (Text), "duplicate one-byte schedule");
      for Seed in Interfaces.Unsigned_32 range 1 .. 8 loop
         Check_Observation (Parse_Randomized (Text, Seed), "duplicate random schedule" & Seed'Image);
      end loop;
   end Check_Duplicate;

   procedure Check_Malformed_Prefix_Invariance
     (Text             : String;
      Code             : Core.Error_Code;
      At_Byte          : Core.Byte_Offset;
      Expected_Raw     : String;
      Expected_Decoded : String := "")
   is
      procedure Check_Observation (Seen : Observation; Schedule : String) is
      begin
         Check (Seen.Outcome = Core.Parse_Failed, Schedule & " accepted malformed input");
         Check (Seen.Diagnostic.Code = Code, Schedule & " changed the error code");
         Check (Seen.Diagnostic.Offset = At_Byte, Schedule & " changed the error offset");
         Check
           (Seen.Raw_Prefix (1 .. Seen.Raw_Prefix_Length) = Expected_Raw,
            Schedule
            & " changed the provisional raw prefix; expected length"
            & Natural'Image (Expected_Raw'Length)
            & ", observed"
            & Natural'Image (Seen.Raw_Prefix_Length));
         Check
           (Seen.String_Text (1 .. Seen.String_Length) = Expected_Decoded,
            Schedule & " changed the provisional decoded prefix");
      end Check_Observation;
   begin
      for Split in 0 .. Text'Length loop
         Check_Observation (Parse (Text, Split), "two-chunk split" & Natural'Image (Split));
      end loop;

      Check_Observation (Parse_One_Byte (Text), "one-byte schedule");
   end Check_Malformed_Prefix_Invariance;

   procedure Check_Truncated_Prefixes (Text : String) is
   begin
      for Prefix_Length in 0 .. Text'Length - 1 loop
         declare
            Prefix : constant String :=
              Text (Text'First .. Text'First + Prefix_Length - 1);
         begin
            for Split in 0 .. Prefix_Length loop
               declare
                  Seen : constant Observation := Parse (Prefix, Split);
               begin
                  Check (Seen.Outcome = Core.Parse_Failed, "truncated text prefix was accepted");
                  Check
                    (Seen.Diagnostic.Code = Core.Truncated_Input,
                     "valid text prefix did not report truncation");
                  Check
                    (Seen.Diagnostic.Offset = Core.Byte_Offset (Prefix_Length),
                     "truncated text prefix reported the wrong offset");
               end;
            end loop;

            declare
               Seen : constant Observation := Parse_One_Byte (Prefix);
            begin
               Check
                 (Seen.Outcome = Core.Parse_Failed,
                  "one-byte schedule accepted a truncated text prefix");
               Check
                 (Seen.Diagnostic.Code = Core.Truncated_Input,
                  "one-byte truncated prefix changed the error code");
               Check
                 (Seen.Diagnostic.Offset = Core.Byte_Offset (Prefix_Length),
                  "one-byte truncated prefix changed the error offset");
            end;
         end;
      end loop;
   end Check_Truncated_Prefixes;

   procedure Check_Truncated_Raw_Prefix
     (Text             : String;
      Expected_Raw     : String;
      Expected_Decoded : String := "") is
   begin
      Check_Malformed_Prefix_Invariance
        (Text,
         Core.Truncated_Input,
         Core.Byte_Offset (Text'Length),
         Expected_Raw,
         Expected_Decoded);
   end Check_Truncated_Raw_Prefix;

   function Fragment_With_Kind
     (Seen : Observation;
      Kind : Core.Decoded_Fragment_Kind) return Positive is
   begin
      for Position in 1 .. Natural'Min (Seen.Fragment_Count, Seen.Fragments'Length) loop
         if Seen.Fragments (Position).Decoded_Kind = Kind then
            return Position;
         end if;
      end loop;

      raise Program_Error with "expected decoded fragment kind was not observed";
   end Fragment_With_Kind;

   Quote           : constant Character := '"';
   Reverse_Solidus : constant Character := '\';
   Euro            : constant String :=
     Character'Val (16#E2#) & Character'Val (16#82#) & Character'Val (16#AC#);
   E_Acute         : constant String := Character'Val (16#C3#) & Character'Val (16#A9#);
   Combining_Acute : constant String := Character'Val (16#CC#) & Character'Val (16#81#);
   Grinning_Face : constant String :=
     Character'Val (16#F0#)
     & Character'Val (16#9F#)
     & Character'Val (16#98#)
     & Character'Val (16#80#);
   First_Supplementary : constant String :=
     Character'Val (16#F0#)
     & Character'Val (16#90#)
     & Character'Val (16#80#)
     & Character'Val (16#80#);
   Last_Scalar : constant String :=
     Character'Val (16#F4#)
     & Character'Val (16#8F#)
     & Character'Val (16#BF#)
     & Character'Val (16#BF#);

   procedure Check_Simple_Escapes is
   begin
      Check_Valid_Text_Splits
        (Quote & Reverse_Solidus & Quote & Quote,
         Expected_String => String'(1 => Quote));
      Check_Valid_Text_Splits
        (Quote & Reverse_Solidus & Reverse_Solidus & Quote,
         Expected_String => String'(1 => Reverse_Solidus));
      Check_Valid_Text_Splits
        (Quote & Reverse_Solidus & '/' & Quote,
         Expected_String => "/");
      Check_Valid_Text_Splits
        (Quote & Reverse_Solidus & 'b' & Quote,
         Expected_String => String'(1 => Character'Val (16#08#)));
      Check_Valid_Text_Splits
        (Quote & Reverse_Solidus & 'f' & Quote,
         Expected_String => String'(1 => Character'Val (16#0C#)));
      Check_Valid_Text_Splits
        (Quote & Reverse_Solidus & 'n' & Quote,
         Expected_String => String'(1 => ASCII.LF));
      Check_Valid_Text_Splits
        (Quote & Reverse_Solidus & 'r' & Quote,
         Expected_String => String'(1 => ASCII.CR));
      Check_Valid_Text_Splits
        (Quote & Reverse_Solidus & 't' & Quote,
         Expected_String => String'(1 => ASCII.HT));
   end Check_Simple_Escapes;

   function Nested_Arrays (Depth : Positive) return String is
      Result : String (1 .. 2 * Depth);
   begin
      for Position in 1 .. Depth loop
         Result (Position) := '[';
         Result (Result'Last - Position + 1) := ']';
      end loop;
      return Result;
   end Nested_Arrays;

   procedure Check_Depth_Boundaries is
      --  1 .. 8 is campaign coverage, not a parser capacity recommendation.
   begin
      declare
         Scalar : constant Observation := Parse ("null", 0, Maximum_Depth => 0);
         Denied : constant Observation := Parse ("[]", 0, Maximum_Depth => 0);
      begin
         Check (Scalar.Outcome = Core.Document_Complete, "zero container capacity rejected a scalar");
         Check (Denied.Outcome = Core.Parse_Failed, "zero container capacity accepted a container");
         Check (Denied.Diagnostic.Code = Core.Depth_Exhausted, "wrong zero-depth error");
         Check (Denied.Diagnostic.Offset = 0, "wrong zero-depth offset");
      end;

      for Maximum in Positive range 1 .. 8 loop
         declare
            Exact : constant String := Nested_Arrays (Maximum);
            Excess : constant String := Nested_Arrays (Maximum + 1);
         begin
            for Split in 0 .. Exact'Length loop
               declare
                  Seen : constant Observation := Parse (Exact, Split, Maximum);
               begin
                  Check (Seen.Outcome = Core.Document_Complete, "exact depth boundary was rejected");
               end;
            end loop;

            for Split in 0 .. Excess'Length loop
               declare
                  Seen : constant Observation := Parse (Excess, Split, Maximum);
               begin
                  Check (Seen.Outcome = Core.Parse_Failed, "N+1 depth was accepted");
                  Check (Seen.Diagnostic.Code = Core.Depth_Exhausted, "wrong N+1 depth error");
                  Check
                    (Seen.Diagnostic.Offset = Core.Byte_Offset (Maximum),
                     "wrong N+1 depth error offset");
               end;
            end loop;
         end;
      end loop;
   end Check_Depth_Boundaries;

   procedure Check_Lifecycle is
      Empty : constant Ada.Streams.Stream_Element_Array := To_Input ("", -9);
      Input : constant Ada.Streams.Stream_Element_Array := To_Input ("x", 17);
   begin
      declare
         Parser : Core.Parser (1, Test_Name_Octet_Capacity, Test_Name_Capacity);
      begin
         Core.Abort_Document (Parser);
         Check (Core.State (Parser) = Core.Uninitialized, "uninitialized abort was not a no-op");
         Core.Initialize (Parser);
         Core.Abort_Document (Parser);
         Check (Core.State (Parser) = Core.Aborted, "ready abort did not enter Aborted");
         Core.Abort_Document (Parser);
         Check (Core.State (Parser) = Core.Aborted, "aborted abort was not idempotent");
         Core.Reset (Parser);
         Check (Core.State (Parser) = Core.Ready, "aborted parser did not reset");
      end;

      declare
         Parser : Core.Parser (1, Test_Name_Octet_Capacity, Test_Name_Capacity);
         Result : Core.Next_Result;
      begin
         Core.Initialize (Parser);
         Core.Next (Parser, Empty, False, Result);
         Check (Result.Outcome = Core.Event_Ready, "active lifecycle setup emitted no begin event");
         Core.Abort_Document (Parser);
         Check (Core.State (Parser) = Core.Aborted, "active abort did not enter Aborted");
      end;

      declare
         Parser  : Core.Parser (1, Test_Name_Octet_Capacity, Test_Name_Capacity);
         Seen    : Observation;
         Result  : Core.Next_Result;
         Primary : Core.Diagnostic;
      begin
         Core.Initialize (Parser);
         Drain (Parser, Input, 0, True, Seen);
         Check (Seen.Outcome = Core.Parse_Failed, "failed lifecycle setup did not fail");
         Primary := Core.Terminal_Diagnostic (Parser);
         Core.Next (Parser, Empty, True, Result);
         Check (Result.Outcome = Core.Call_Rejected, "call after failure was not rejected");
         Check (Result.Consumed = 0, "rejected failed call consumed input");
         Check (Result.Diagnostic.Code = Core.Invalid_State, "rejected failed call diagnostic is wrong");
         Check (Core.Terminal_Diagnostic (Parser) = Primary, "rejected call replaced primary failure");
         Core.Abort_Document (Parser);
         Check (Core.State (Parser) = Core.Aborted, "failed abort did not enter Aborted");
         Check (Core.Terminal_Diagnostic (Parser) = Primary, "abort replaced primary failure");
         Core.Reset (Parser);
         Seen := (others => <>);
         Drain (Parser, To_Input ("null", -3), 0, True, Seen);
         Check (Seen.Outcome = Core.Document_Complete, "failed parser was not reusable after reset");
      end;

      declare
         Parser : Core.Parser (1, Test_Name_Octet_Capacity, Test_Name_Capacity);
         Seen   : Observation;
         Result : Core.Next_Result;
      begin
         Core.Initialize (Parser);
         Drain (Parser, To_Input ("[]", 29), 0, True, Seen);
         Check (Seen.Outcome = Core.Document_Complete, "completed lifecycle setup failed");
         Core.Next (Parser, Empty, True, Result);
         Check (Result.Outcome = Core.Call_Rejected, "call after completion was not rejected");
         Check (Result.Consumed = 0, "rejected completed call consumed input");
         Check (Result.Diagnostic.Code = Core.Invalid_State, "completed rejection diagnostic is wrong");
         Core.Abort_Document (Parser);
         Check (Core.State (Parser) = Core.Aborted, "completed abort did not revoke completion");
         Core.Reset (Parser);
         Seen := (others => <>);
         Drain (Parser, To_Input (Quote & "reuse" & Quote, -13), 0, True, Seen);
         Check (Seen.Outcome = Core.Document_Complete, "completed parser was not reusable after reset");
         Check (Seen.String_Text (1 .. Seen.String_Length) = "reuse", "reset reuse changed text");
      end;
   end Check_Lifecycle;

   procedure Check_Duplicate_Capacities is
      procedure Check_With_Capacities
        (Text          : String;
         Name_Octets   : Natural;
         Names         : Natural;
         Expected      : Core.Next_Outcome;
         Expected_Code : Core.Error_Code := Core.No_Error;
         Expected_At   : Core.Byte_Offset := 0;
         Expected_Name_Ends : Natural := 0;
         Check_Prefix       : Boolean := False;
         Expected_Raw       : String := "";
         Expected_Decoded   : String := "") is
         procedure Check_Seen (Seen : Observation; Schedule : String) is
         begin
            Check (Seen.Outcome = Expected, Schedule & " changed capacity outcome");
            if Expected = Core.Parse_Failed then
               Check (Seen.Diagnostic.Code = Expected_Code, Schedule & " changed capacity status");
               Check (Seen.Diagnostic.Offset = Expected_At, Schedule & " changed capacity offset");
               Check
                 (Seen.Events (Core.Name_End) = Expected_Name_Ends,
                  Schedule & " published a rejecting Name_End");
            end if;
            if Check_Prefix then
               Check
                 (Seen.Raw_Prefix (1 .. Seen.Raw_Prefix_Length) = Expected_Raw,
                  Schedule
                  & " changed the capacity-denied raw prefix; expected length"
                  & Natural'Image (Expected_Raw'Length)
                  & ", observed"
                  & Natural'Image (Seen.Raw_Prefix_Length));
               Check
                 (Seen.Name_Text (1 .. Seen.Name_Length) = Expected_Decoded,
                  Schedule
                  & " changed the capacity-denied decoded prefix; expected length"
                  & Natural'Image (Expected_Decoded'Length)
                  & ", observed"
                  & Natural'Image (Seen.Name_Length));
            end if;
         end Check_Seen;
      begin
         for Split in 0 .. Text'Length loop
            declare
               Parser : Core.Parser (4, Name_Octets, Names);
               Seen   : Observation;
            begin
               Core.Initialize (Parser);
               if Split > 0 then
                  Drain
                    (Parser,
                     To_Input (Text (Text'First .. Text'First + Split - 1), -41),
                     0,
                     False,
                     Seen);
               end if;
               if Split = 0 or else Seen.Outcome = Core.Need_Input then
                  Drain
                    (Parser,
                     To_Input (Text (Text'First + Split .. Text'Last), 37),
                     Core.Byte_Offset (Split),
                     True,
                     Seen);
               end if;
               Check_Seen (Seen, "capacity split" & Natural'Image (Split));
            end;
         end loop;

         declare
            Parser : Core.Parser (4, Name_Octets, Names);
            Seen   : Observation;
         begin
            Core.Initialize (Parser);
            for Position in 0 .. Text'Length - 1 loop
               Drain
                 (Parser,
                  To_Input
                    (Text (Text'First + Position .. Text'First + Position),
                     Offset (-19 + Position)),
                  Core.Byte_Offset (Position),
                  Position = Text'Length - 1,
                  Seen);
               exit when Seen.Outcome /= Core.Need_Input;
            end loop;
            Check_Seen (Seen, "capacity one-byte schedule");
         end;

         for Seed in Interfaces.Unsigned_32 range 1 .. 4 loop
            declare
               Parser    : Core.Parser (4, Name_Octets, Names);
               Seen      : Observation;
               Generator : Interfaces.Unsigned_32 := Seed;
               Position  : Natural := 0;
            begin
               Core.Initialize (Parser);
               while Position < Text'Length loop
                  Generator := Generator * 1_664_525 + 1_013_904_223;
                  declare
                     Length : constant Natural :=
                       Natural'Min (Text'Length - Position, Natural (Generator mod 5) + 1);
                  begin
                     Drain
                       (Parser,
                        To_Input
                          (Text (Text'First + Position .. Text'First + Position + Length - 1),
                           Offset (23 + Position)),
                        Core.Byte_Offset (Position),
                        Position + Length = Text'Length,
                        Seen);
                     Position := Position + Length;
                  end;
                  exit when Seen.Outcome /= Core.Need_Input;
               end loop;
               Check_Seen (Seen, "capacity random schedule" & Seed'Image);
            end;
         end loop;
      end Check_With_Capacities;

      procedure Check_Pending_Failure_Transition is
         Text  : constant String := "{" & Quote & "ab" & Quote & ":0}";
         Input : constant Ada.Streams.Stream_Element_Array := To_Input (Text, -33);

         procedure Next_On_Suffix
           (Parser      : in out Core.Parser;
            Used        : in out Count;
            Final_Input : Boolean;
            Result      : out Core.Next_Result) is
         begin
            if Used < Input'Length then
               Core.Next
                 (Parser,
                  Input (Input'First + Offset (Used) .. Input'Last),
                  Final_Input,
                  Result);
            else
               declare
                  Empty : Ada.Streams.Stream_Element_Array (19 .. 18);
               begin
                  Core.Next (Parser, Empty, Final_Input, Result);
               end;
            end if;
            Used := Used + Result.Consumed;
         end Next_On_Suffix;

         procedure Reach_Accepted_Prefix
           (Parser : in out Core.Parser;
            Used   : in out Count;
            Result : out Core.Next_Result) is
         begin
            Core.Initialize (Parser);
            Next_On_Suffix (Parser, Used, False, Result);
            Check (Result.Item.Kind = Core.Document_Begin, "pending setup missed document begin");
            Next_On_Suffix (Parser, Used, False, Result);
            Check (Result.Item.Kind = Core.Object_Begin, "pending setup missed object begin");
            Next_On_Suffix (Parser, Used, False, Result);
            Check (Result.Item.Kind = Core.Name_Begin, "pending setup missed name begin");
            Next_On_Suffix (Parser, Used, False, Result);
            Check (Result.Outcome = Core.Event_Ready, "accepted name prefix was not an event");
            Check (Result.Item.Kind = Core.Name_Fragment, "accepted name prefix changed kind");
            Check
              (Result.Item.Decoded_Kind = Core.Decoded_Is_Raw_Range,
               "accepted name prefix was not decoded");
            Check (Result.Item.Source = (First => 2, Octet_Length => 1), "accepted prefix moved");
            Check (Core.State (Parser) = Core.Active, "accepted prefix changed parser state");
         end Reach_Accepted_Prefix;

         procedure Reach_Pending
           (Parser : in out Core.Parser;
            Used   : in out Count;
            Result : out Core.Next_Result) is
         begin
            Reach_Accepted_Prefix (Parser, Used, Result);
            Next_On_Suffix (Parser, Used, False, Result);
            Check (Result.Outcome = Core.Event_Ready, "denied scalar did not expose raw provenance");
            Check (Result.Item.Kind = Core.Name_Fragment, "denied scalar changed event kind");
            Check
              (Result.Item.Decoded_Kind = Core.No_Decoded_Fragment,
               "denied scalar was incorrectly decoded");
            Check (Result.Item.Source = (First => 3, Octet_Length => 1), "denied scalar moved");
            Check (Core.State (Parser) = Core.Failure_Pending, "denial was not latched");
            Check
              (Core.Terminal_Diagnostic (Parser)
                 = (Code => Core.Name_Storage_Exhausted, Offset => 3),
               "pending denial changed its diagnostic");
         end Reach_Pending;
      begin
         declare
            Parser : Core.Parser (4, 1, 1);
            Used   : Count := 0;
            Result : Core.Next_Result;
         begin
            Reach_Pending (Parser, Used, Result);
            Next_On_Suffix (Parser, Used, True, Result);
            Check (Result.Outcome = Core.Parse_Failed, "pending denial was not reported");
            Check (Result.Consumed = 0, "pending denial consumed following input");
            Check (Core.State (Parser) = Core.Failed, "reported denial did not become terminal");
         end;

         declare
            Parser : Core.Parser (4, 1, 1);
            Used   : Count := 0;
            Result : Core.Next_Result;
         begin
            Reach_Accepted_Prefix (Parser, Used, Result);
            Core.Abort_Document (Parser);
            Check (Core.State (Parser) = Core.Aborted, "active prefix abort did not cancel");
         end;

         declare
            Parser  : Core.Parser (4, 1, 1);
            Used    : Count := 0;
            Result  : Core.Next_Result;
            Primary : Core.Diagnostic;
         begin
            Reach_Pending (Parser, Used, Result);
            Primary := Core.Terminal_Diagnostic (Parser);
            Core.Abort_Document (Parser);
            Check (Core.State (Parser) = Core.Failed, "pending abort hid the primary failure");
            Check
              (Core.Terminal_Diagnostic (Parser) = Primary,
               "pending abort replaced the primary failure");
         end;

         declare
            Parser : Core.Parser (4, 1, 1);
            Used   : Count := 0;
            Result : Core.Next_Result;
            Seen   : Observation;
         begin
            Reach_Pending (Parser, Used, Result);
            Core.Reset (Parser);
            Check (Core.State (Parser) = Core.Ready, "pending denial could not reset");
            Drain (Parser, To_Input ("{}", 71), 0, True, Seen);
            Check (Seen.Outcome = Core.Document_Complete, "pending reset did not permit reuse");
         end;
      end Check_Pending_Failure_Transition;

      procedure Check_Short_Escape_Denial_Event is
         Text   : constant String :=
           "{" & Quote & Reverse_Solidus & Quote & Quote & ":0}";
         Input  : constant Ada.Streams.Stream_Element_Array := To_Input (Text, -57);
         Parser : Core.Parser (4, 0, 1);
         Used   : Count := 0;
         Result : Core.Next_Result;

         procedure Expect (Kind : Core.Event_Kind) is
         begin
            Core.Next
              (Parser,
               Input (Input'First + Offset (Used) .. Input'Last),
               False,
               Result);
            Used := Used + Result.Consumed;
            Check (Result.Outcome = Core.Event_Ready, "short escape setup did not emit an event");
            Check (Result.Item.Kind = Kind, "short escape setup changed event order");
         end Expect;
      begin
         Core.Initialize (Parser);
         Expect (Core.Document_Begin);
         Expect (Core.Object_Begin);
         Expect (Core.Name_Begin);

         Core.Next
           (Parser,
            Input (Input'First + Offset (Used) .. Input'Last),
            False,
            Result);
         Check (Result.Outcome = Core.Event_Ready, "short escape denial did not emit raw provenance");
         Check (Result.Item.Kind = Core.Name_Fragment, "short escape denial changed event kind");
         Check
           (Result.Item.Decoded_Kind = Core.No_Decoded_Fragment,
            "short escape denial exposed decoded data");
         Check
           (Result.Item.Source = (First => 2, Octet_Length => 2),
            "monolithic short escape was not one complete raw-only scalar event");
         Check (Result.Consumed = 2, "short escape denial consumed beyond its scalar");
         Check (Core.State (Parser) = Core.Failure_Pending, "short escape denial was not pending");
      end Check_Short_Escape_Denial_Event;
   begin
      Check_With_Capacities
        (Quote
         & "value"
         & Euro
         & Reverse_Solidus & "n"
         & Reverse_Solidus & "uD83D" & Reverse_Solidus & "uDE00"
         & Quote,
         0,
         0,
         Core.Document_Complete);
      Check_With_Capacities
        ("["
         & Quote & "outer" & Reverse_Solidus & "t" & Quote
         & ",["
         & Quote & Euro & Reverse_Solidus & "u0061" & Quote
         & "]]",
         0,
         0,
         Core.Document_Complete);
      Check_With_Capacities ("{" & Quote & Quote & ":0}", 0, 1, Core.Document_Complete);
      Check_With_Capacities
        ("{" & Quote & "a" & Quote & ":0}",
         0,
         1,
         Core.Parse_Failed,
         Core.Name_Storage_Exhausted,
         2,
         Check_Prefix     => True,
         Expected_Raw     => "a",
         Expected_Decoded => "");
      Check_With_Capacities
        ("{" & Quote & Quote & ":0}",
         0,
         0,
         Core.Parse_Failed,
         Core.Duplicate_Index_Exhausted,
         1);
      Check_With_Capacities
        ("{" & Quote & "a" & Quote & ":0," & Quote & "b" & Quote & ":1}",
         4,
         1,
         Core.Parse_Failed,
         Core.Duplicate_Index_Exhausted,
         7,
         Expected_Name_Ends => 1);
      Check_With_Capacities
        ("{" & Quote & "a" & Quote & ":0," & Quote & "a" & Quote & ":1}",
         1,
         1,
         Core.Parse_Failed,
         Core.Name_Storage_Exhausted,
         8,
         Expected_Name_Ends => 1,
         Check_Prefix       => True,
         Expected_Raw       => "a0a",
         Expected_Decoded   => "a");
      Check_With_Capacities
        ("{" & Quote & E_Acute & Quote & ":0}", 2, 1, Core.Document_Complete);
      Check_With_Capacities
        ("{" & Quote & E_Acute & Quote & ":0}",
         1,
         1,
         Core.Parse_Failed,
         Core.Name_Storage_Exhausted,
         2,
         Check_Prefix     => True,
         Expected_Raw     => E_Acute,
         Expected_Decoded => "");
      Check_With_Capacities
        ("{" & Quote & Reverse_Solidus & "u20AC" & Quote & ":0}",
         2,
         1,
         Core.Parse_Failed,
         Core.Name_Storage_Exhausted,
         2,
         Check_Prefix     => True,
         Expected_Raw     => Reverse_Solidus & "u20AC",
         Expected_Decoded => "");
      Check_With_Capacities
        ("{" & Quote & Reverse_Solidus & Quote & Quote & ":0}",
         0,
         1,
         Core.Parse_Failed,
         Core.Name_Storage_Exhausted,
         2,
         Check_Prefix     => True,
         Expected_Raw     => Reverse_Solidus & Quote,
         Expected_Decoded => "");
      Check_With_Capacities
        ("{" & Quote & Reverse_Solidus & Reverse_Solidus & Quote & ":0}",
         0,
         1,
         Core.Parse_Failed,
         Core.Name_Storage_Exhausted,
         2,
         Check_Prefix     => True,
         Expected_Raw     => Reverse_Solidus & Reverse_Solidus,
         Expected_Decoded => "");
      Check_With_Capacities
        ("{" & Quote & Grinning_Face & Quote & ":0}",
         3,
         1,
         Core.Parse_Failed,
         Core.Name_Storage_Exhausted,
         2,
         Check_Prefix     => True,
         Expected_Raw     => Grinning_Face,
         Expected_Decoded => "");
      Check_With_Capacities
        ("{" & Quote & Reverse_Solidus & "uD83D" & Reverse_Solidus & "uDE00" & Quote & ":0}",
         3,
         1,
         Core.Parse_Failed,
         Core.Name_Storage_Exhausted,
         2,
         Check_Prefix     => True,
         Expected_Raw     => Reverse_Solidus & "uD83D" & Reverse_Solidus & "uDE00",
         Expected_Decoded => "");
      Check_With_Capacities
        ("{" & Quote & "a" & Quote & ":0," & Quote & "b" & Quote & ":1}",
         2,
         2,
         Core.Document_Complete);
      Check_With_Capacities
        ("{" & Quote & "abcde" & Quote & ":0}",
         4,
         1,
         Core.Parse_Failed,
         Core.Name_Storage_Exhausted,
         6,
         Check_Prefix     => True,
         Expected_Raw     => "abcde",
         Expected_Decoded => "abcd");

      --  Syntax validation precedes name-octet denial until a complete valid
      --  scalar exists.  Name-index denial occurs earlier, at the opening
      --  quote, because no candidate can begin.
      Check_With_Capacities
        ("{" & Quote & Character'Val (1) & Quote & ":0}",
         0,
         1,
         Core.Parse_Failed,
         Core.Raw_Control_Character,
         2);
      Check_With_Capacities
        ("{" & Quote & Character'Val (16#C0#) & Quote & ":0}",
         0,
         1,
         Core.Parse_Failed,
         Core.Invalid_UTF8,
         2);
      Check_With_Capacities
        ("{" & Quote & Reverse_Solidus & "q" & Quote & ":0}",
         0,
         1,
         Core.Parse_Failed,
         Core.Invalid_Escape,
         3);
      Check_With_Capacities
        ("{" & Quote & Reverse_Solidus & "uDC00" & Quote & ":0}",
         0,
         1,
         Core.Parse_Failed,
         Core.Invalid_Surrogate,
         2);
      Check_With_Capacities
        ("{" & Quote & Reverse_Solidus & "uD800" & Reverse_Solidus & "u0041" & Quote & ":0}",
         0,
         1,
         Core.Parse_Failed,
         Core.Invalid_Surrogate,
         2);
      Check_With_Capacities
        ("{" & Quote & Character'Val (1) & Quote & ":0}",
         0,
         0,
         Core.Parse_Failed,
         Core.Duplicate_Index_Exhausted,
         1);

      declare
         Parser : Core.Parser (4, 16, 4);
         Seen   : Observation;
      begin
         Core.Initialize (Parser);
         Drain
           (Parser,
            To_Input ("{" & Quote & "a" & Quote & ":0," & Quote & "a" & Quote & ":1}", -7),
            0,
            True,
            Seen);
         Check (Seen.Diagnostic.Code = Core.Duplicate_Name, "duplicate reset setup did not fail");
         Core.Reset (Parser);
         Seen := (others => <>);
         Drain (Parser, To_Input ("{" & Quote & "b" & Quote & ":0}", 11), 0, True, Seen);
         Check (Seen.Outcome = Core.Document_Complete, "duplicate reset left a ghost name");
      end;

      declare
         Parser : Core.Parser (4, 0, 1);
         Seen   : Observation;
      begin
         Core.Initialize (Parser);
         Drain (Parser, To_Input ("{" & Quote & "a" & Quote & ":0}", -5), 0, True, Seen);
         Check
           (Seen.Diagnostic.Code = Core.Name_Storage_Exhausted,
            "resource reset setup did not fail");
         Core.Reset (Parser);
         Seen := (others => <>);
         Drain (Parser, To_Input ("{" & Quote & Quote & ":0}", 13), 0, True, Seen);
         Check (Seen.Outcome = Core.Document_Complete, "resource reset left arena storage live");
      end;

      Check_Pending_Failure_Transition;
      Check_Short_Escape_Denial_Event;
   end Check_Duplicate_Capacities;

begin
   Check_Valid_Splits ("null");
   Check_Valid_Splits ("true");
   Check_Valid_Splits ("false");
   Check_Valid_Splits ("0", 1, "0");
   Check_Valid_Splits ("-12.34e+5", 9, "-12.34e+5");
   Check_Valid_Splits ("-0", 2, "-0");
   Check_Valid_Splits ("1E-999999", 9, "1E-999999");
   Check_Valid_Splits
     ("[-0,1.25,6E+7]",
      Expected_Number_Octets => 10,
      Expected_Number_Text   => "-01.256E+7",
      Expected_Arrays        => 1);
   Check_Valid_Splits
     ("[null,true,false,0]",
      Expected_Number_Octets => 1,
      Expected_Number_Text   => "0",
      Expected_Arrays        => 1);
   Check_Valid_Splits ("[[],{}]", Expected_Arrays => 2, Expected_Objects => 1);
   Check_Valid_Splits
     ("{"
      & Quote & Quote & ":0,"
      & Quote & Reverse_Solidus & "u0000" & Quote & ":1,"
      & Quote & "a" & Quote & ":2,"
      & Quote & "a" & Reverse_Solidus & "u0000" & Quote & ":3,"
      & Quote & "ab" & Quote & ":4,"
      & Quote & "abc" & Quote & ":5}",
      Expected_Number_Octets => 6,
      Expected_Number_Text   => "012345",
      Expected_Objects       => 1);
   Check_Valid_Splits
     ("{" & Quote & "x" & Quote & ":{" & Quote & "a" & Quote & ":0},"
      & Quote & "y" & Quote & ":{" & Quote & "a" & Quote & ":1}}",
      Expected_Number_Octets => 2,
      Expected_Number_Text   => "01",
      Expected_Objects       => 3);
   Check_Valid_Text_Splits
     ("{" & Quote & Reverse_Solidus & "u00E9" & Quote & ":0,"
      & Quote & "e" & Reverse_Solidus & "u0301" & Quote & ":1}",
      Expected_Name    => E_Acute & "e" & Combining_Acute,
      Expected_Names   => 2,
      Expected_Strings => 0);
   Check_Valid_Text_Splits
     ("{" & Quote & "a" & Quote & ":0," & Quote & "A" & Quote & ":1}",
      Expected_Name    => "aA",
      Expected_Names   => 2,
      Expected_Strings => 0);

   Check_Valid_Text_Splits (Quote & Quote, Expected_String => "");
   Check_Valid_Text_Splits (Quote & "ascii" & Quote, Expected_String => "ascii");
   Check_Simple_Escapes;
   Check_Valid_Text_Splits
     (Quote & Reverse_Solidus & "u20AC" & Quote,
      Expected_String => Euro);
   Check_Valid_Text_Splits
     (Quote & Reverse_Solidus & "uD83D" & Reverse_Solidus & "uDE00" & Quote,
      Expected_String => Grinning_Face);
   Check_Valid_Text_Splits
     (Quote & Reverse_Solidus & "uD800" & Reverse_Solidus & "uDC00" & Quote,
      Expected_String => First_Supplementary);
   Check_Valid_Text_Splits
     (Quote & Reverse_Solidus & "uDBFF" & Reverse_Solidus & "uDFFF" & Quote,
      Expected_String => Last_Scalar);
   Check_Valid_Text_Splits
     ("{"
      & Quote & "a" & Quote & ":" & Quote & "b" & Quote
      & ","
      & Quote & Reverse_Solidus & "u20AC" & Quote
      & ":"
      & Quote & Euro & Quote
      & "}",
      Expected_Name    => "a" & Euro,
      Expected_String  => "b" & Euro,
      Expected_Names   => 2,
      Expected_Strings => 2);

   Check_All_Partitions (Quote & Quote, "");
   Check_All_Partitions (Quote & "a" & Quote, "a");
   Check_All_Partitions
     (Quote & Reverse_Solidus & "n" & Quote,
      String'(1 => ASCII.LF));
   Check_All_Partitions ("null", "");
   Check_All_Partitions ("-1", "");
   Check_All_Partitions ("[0]", "");
   Check_All_Partitions ("{" & Quote & Quote & ":0}", "");

   declare
      Document   : constant String := Quote & Euro & Quote;
      Same_Chunk : constant Observation := Parse (Document, 0);
      Split_UTF8 : constant Observation := Parse (Document, 2);
      Inline     : Positive;
   begin
      Check (Same_Chunk.Outcome = Core.Document_Complete, "same-chunk UTF-8 rejected");
      Check (Same_Chunk.Fragment_Count = 1, "same-chunk UTF-8 was not one fragment");
      Check
        (Same_Chunk.Fragments (1).Decoded_Kind = Core.Decoded_Is_Raw_Range,
         "same-chunk UTF-8 was copied instead of borrowed");
      Check
        (Same_Chunk.Fragments (1).Source = (First => 1, Octet_Length => 3),
         "same-chunk UTF-8 source range is wrong");
      Check (Split_UTF8.Outcome = Core.Document_Complete, "split UTF-8 rejected");
      Check (Split_UTF8.Fragment_Count = 2, "split UTF-8 did not preserve both raw spans");
      Inline := Fragment_With_Kind (Split_UTF8, Core.Decoded_Inline_Scalar);
      Check
        (Split_UTF8.Fragments (Inline).Decoded_Kind = Core.Decoded_Inline_Scalar,
         "split UTF-8 did not use stable inline scalar bytes");
      Check
        (Split_UTF8.Fragments (Inline).Source = (First => 2, Octet_Length => 2),
         "split UTF-8 current-call source range is wrong");
      Check
        (Split_UTF8.Fragments (Inline).Decoded_Source = (First => 1, Octet_Length => 3),
         "split UTF-8 complete scalar provenance is wrong");
      Check
        (Split_UTF8.Fragments (Inline).Decoded_Length = 3,
         "split UTF-8 decoded length is wrong");
      Check
        (Split_UTF8.String_Text (1 .. Split_UTF8.String_Length) = Euro,
         "split UTF-8 decoded bytes changed");
   end;

   declare
      Document : constant String := Quote & "a" & Euro & Grinning_Face & "z" & Quote;
      Seen     : constant Observation := Parse (Document, 0);
   begin
      Check (Seen.Outcome = Core.Document_Complete, "contiguous UTF-8 bulk span rejected");
      Check (Seen.Fragment_Count = 1, "valid UTF-8 bulk span dispatched once per scalar");
      Check
        (Seen.Fragments (1).Decoded_Kind = Core.Decoded_Is_Raw_Range,
         "valid UTF-8 bulk span was copied instead of borrowed");
      Check
        (Seen.String_Text (1 .. Seen.String_Length) = "a" & Euro & Grinning_Face & "z",
         "valid UTF-8 bulk span changed decoded bytes");
   end;

   declare
      Escaped : constant Observation :=
        Parse (Quote & Reverse_Solidus & "u20AC" & Quote, 0);
   begin
      Check (Escaped.Fragment_Count = 1, "Unicode escape was not one scalar fragment");
      Check
        (Escaped.Fragments (1).Source = (First => 1, Octet_Length => 6),
         "Unicode escape source range is wrong");
      Check
        (Escaped.Fragments (1).Decoded_Source = Escaped.Fragments (1).Source,
         "Unicode escape decoded provenance is wrong");
      Check (Escaped.Fragments (1).Decoded_Length = 3, "Unicode escape UTF-8 length is wrong");
   end;

   Check_Invalid ("truex", Core.Invalid_Literal, 4);
   Check_Invalid ("01", Core.Invalid_Number, 1);
   Check_Invalid ("[0,]", Core.Unexpected_Token, 3);
   Check_Invalid ("1.", Core.Truncated_Input, 2);

   Check_Duplicate
     ("{" & Quote & "a" & Quote & ":0," & Quote & "a" & Quote & ":1}", 7);
   Check_Duplicate
     ("{" & Quote & "a" & Quote & ":0,"
      & Quote & Reverse_Solidus & "u0061" & Quote & ":1}",
      7);
   Check_Duplicate
     ("{" & Quote & Reverse_Solidus & "u20AC" & Quote & ":0,"
      & Quote & Euro & Quote & ":1}",
      12);
   Check_Duplicate
     ("{" & Quote & Reverse_Solidus & "u00E9" & Quote & ":0,"
      & Quote & E_Acute & Quote & ":1}",
      12);
   Check_Duplicate
     ("{" & Quote & Reverse_Solidus & "uD83D" & Reverse_Solidus & "uDE00" & Quote & ":0,"
      & Quote & Grinning_Face & Quote & ":1}",
      18);
   Check_Duplicate
     ("{" & Quote & Reverse_Solidus & "/" & Quote & ":0,"
      & Quote & "/" & Quote & ":1}",
      8);
   Check_Duplicate
     ("{" & Quote & "a" & Quote & ":{" & Quote & "a" & Quote & ":0},"
      & Quote & "a" & Quote & ":1}",
      13,
      Expected_Name_Begins => 3,
      Expected_Name_Ends   => 2);

   Check_Duplicate_Capacities;

   Check_Malformed_Prefix_Invariance
     ("12x", Core.Invalid_Number, 2, Expected_Raw => "12");
   Check_Malformed_Prefix_Invariance
     ("[1.]", Core.Invalid_Number, 3, Expected_Raw => "1.");

   Check_Invalid
     (Quote & "a" & Character'Val (16#01#) & "b" & Quote,
      Core.Raw_Control_Character,
      2);
   Check_Invalid
     (Quote & Character'Val (16#C2#) & ' ' & Quote,
      Core.Invalid_UTF8,
      2);
   Check_Malformed_Prefix_Invariance
     (Quote & "a" & Character'Val (16#C2#) & ' ' & Quote,
      Core.Invalid_UTF8,
      3,
      Expected_Raw     => "a" & Character'Val (16#C2#),
      Expected_Decoded => "a");
   Check_Malformed_Prefix_Invariance
     (Quote
      & "a"
      & Character'Val (16#E2#)
      & Character'Val (16#82#)
      & ' '
      & Quote,
      Core.Invalid_UTF8,
      4,
      Expected_Raw     => "a" & Character'Val (16#E2#) & Character'Val (16#82#),
      Expected_Decoded => "a");
   Check_Invalid
     (Quote & Character'Val (16#C0#) & Character'Val (16#AF#) & Quote,
      Core.Invalid_UTF8,
      1);
   Check_Invalid
     (Quote
      & Character'Val (16#E0#)
      & Character'Val (16#80#)
      & Character'Val (16#80#)
      & Quote,
      Core.Invalid_UTF8,
      1);
   Check_Invalid
     (Quote
      & Character'Val (16#ED#)
      & Character'Val (16#A0#)
      & Character'Val (16#80#)
      & Quote,
      Core.Invalid_UTF8,
      1);
   Check_Invalid
     (Quote
      & Character'Val (16#F4#)
      & Character'Val (16#90#)
      & Character'Val (16#80#)
      & Character'Val (16#80#)
      & Quote,
      Core.Invalid_UTF8,
      1);
   Check_Invalid
     (Quote & Character'Val (16#80#) & Quote,
      Core.Invalid_UTF8,
      1);
   Check_Invalid
     (Quote & Reverse_Solidus & "x" & Quote,
      Core.Invalid_Escape,
      2);
   Check_Malformed_Prefix_Invariance
     (Quote & "a" & Reverse_Solidus & "x" & Quote,
      Core.Invalid_Escape,
      3,
      Expected_Raw     => "a" & Reverse_Solidus,
      Expected_Decoded => "a");
   Check_Malformed_Prefix_Invariance
     (Quote & Reverse_Solidus & "n" & Reverse_Solidus & "x" & Quote,
      Core.Invalid_Escape,
      4,
      Expected_Raw     => Reverse_Solidus & "n" & Reverse_Solidus,
      Expected_Decoded => String'(1 => ASCII.LF));
   Check_Invalid
     (Quote & Reverse_Solidus & "u12G4" & Quote,
      Core.Invalid_Escape,
      5);
   Check_Malformed_Prefix_Invariance
     (Quote & "a" & Reverse_Solidus & "u12G4" & Quote,
      Core.Invalid_Escape,
      6,
      Expected_Raw     => "a" & Reverse_Solidus & "u12",
      Expected_Decoded => "a");
   Check_Invalid
     (Quote & Reverse_Solidus & "uG000" & Quote,
      Core.Invalid_Escape,
      3);
   Check_Invalid
     (Quote & Reverse_Solidus & "u0G00" & Quote,
      Core.Invalid_Escape,
      4);
   Check_Invalid
     (Quote & Reverse_Solidus & "u000G" & Quote,
      Core.Invalid_Escape,
      6);
   Check_Invalid
     (Quote & Reverse_Solidus & "uDC00" & Quote,
      Core.Invalid_Surrogate,
      1);
   Check_Malformed_Prefix_Invariance
     (Quote & Reverse_Solidus & "uDC00" & Quote,
      Core.Invalid_Surrogate,
      1,
      Expected_Raw => Reverse_Solidus & "uDC0");
   Check_Invalid
     (Quote & Reverse_Solidus & "uDFFF" & Quote,
      Core.Invalid_Surrogate,
      1);
   Check_Invalid
     (Quote & Reverse_Solidus & "uD800x" & Quote,
      Core.Invalid_Surrogate,
      1);
   Check_Malformed_Prefix_Invariance
     (Quote & Reverse_Solidus & "uD800x" & Quote,
      Core.Invalid_Surrogate,
      1,
      Expected_Raw => Reverse_Solidus & "uD800");
   Check_Malformed_Prefix_Invariance
     (Quote & Reverse_Solidus & "uD800" & Reverse_Solidus & "q" & Quote,
      Core.Invalid_Escape,
      8,
      Expected_Raw => Reverse_Solidus & "uD800" & Reverse_Solidus);
   Check_Invalid
     (Quote & Reverse_Solidus & "uD800" & Reverse_Solidus & "u0041" & Quote,
      Core.Invalid_Surrogate,
      1);
   Check_Malformed_Prefix_Invariance
     (Quote & Reverse_Solidus & "uD800" & Reverse_Solidus & "u0041" & Quote,
      Core.Invalid_Surrogate,
      1,
      Expected_Raw => Reverse_Solidus & "uD800" & Reverse_Solidus & "u004");
   Check_Invalid
     (Quote & Reverse_Solidus & "uD800" & Reverse_Solidus & "uDBFF" & Quote,
      Core.Invalid_Surrogate,
      1);
   Check_Invalid
     (Quote & Reverse_Solidus & "uD800" & Quote,
      Core.Invalid_Surrogate,
      1);
   Check_Invalid
     ("{" & Quote & Reverse_Solidus & "uDC00" & Quote & ":null}",
      Core.Invalid_Surrogate,
      2);

   Check_Truncated_Prefixes (Quote & "ascii" & Quote);
   Check_Truncated_Prefixes (Quote & Euro & Quote);
   Check_Truncated_Prefixes ("{" & Quote & "a" & Quote & ":" & Quote & "b" & Quote & "}");
   Check_Truncated_Prefixes
     (Quote & Reverse_Solidus & "uD83D" & Reverse_Solidus & "uDE00" & Quote);

   --  A final call publishes every newly consumed raw-only span before the
   --  following empty final call latches truncation.  The aggregate provisional
   --  prefix must therefore be independent of chunk scheduling.
   Check_Truncated_Raw_Prefix
     (Quote & "a" & Character'Val (16#E2#),
      "a" & Character'Val (16#E2#),
      "a");
   Check_Truncated_Raw_Prefix
     (Quote & Character'Val (16#E2#) & Character'Val (16#82#),
      Character'Val (16#E2#) & Character'Val (16#82#));
   Check_Truncated_Raw_Prefix
     (Quote & Character'Val (16#C2#),
      String'(1 => Character'Val (16#C2#)));
   Check_Truncated_Raw_Prefix
     (Quote & Character'Val (16#F0#),
      String'(1 => Character'Val (16#F0#)));
   Check_Truncated_Raw_Prefix
     (Quote & Character'Val (16#F0#) & Character'Val (16#90#),
      Character'Val (16#F0#) & Character'Val (16#90#));
   Check_Truncated_Raw_Prefix
     (Quote
      & Character'Val (16#F0#)
      & Character'Val (16#90#)
      & Character'Val (16#80#),
      Character'Val (16#F0#)
      & Character'Val (16#90#)
      & Character'Val (16#80#));
   Check_Truncated_Raw_Prefix
     (Quote & "a" & Reverse_Solidus,
      "a" & Reverse_Solidus,
      "a");
   Check_Truncated_Raw_Prefix
     (Quote & Reverse_Solidus & "u",
      Reverse_Solidus & "u");
   Check_Truncated_Raw_Prefix
     (Quote & Reverse_Solidus & "u0",
      Reverse_Solidus & "u0");
   Check_Truncated_Raw_Prefix
     (Quote & Reverse_Solidus & "u00",
      Reverse_Solidus & "u00");
   Check_Truncated_Raw_Prefix
     (Quote & Reverse_Solidus & "u000",
      Reverse_Solidus & "u000");
   Check_Truncated_Raw_Prefix
     (Quote & Reverse_Solidus & "uD800",
      Reverse_Solidus & "uD800");
   Check_Truncated_Raw_Prefix
     (Quote & Reverse_Solidus & "uD800" & Reverse_Solidus,
      Reverse_Solidus & "uD800" & Reverse_Solidus);
   Check_Truncated_Raw_Prefix
     (Quote & Reverse_Solidus & "uD800" & Reverse_Solidus & "u",
      Reverse_Solidus & "uD800" & Reverse_Solidus & "u");
   Check_Truncated_Raw_Prefix
     (Quote & Reverse_Solidus & "uD800" & Reverse_Solidus & "uD",
      Reverse_Solidus & "uD800" & Reverse_Solidus & "uD");
   Check_Truncated_Raw_Prefix
     (Quote & Reverse_Solidus & "uD800" & Reverse_Solidus & "uDC",
      Reverse_Solidus & "uD800" & Reverse_Solidus & "uDC");
   Check_Truncated_Raw_Prefix
     (Quote & Reverse_Solidus & "uD800" & Reverse_Solidus & "uDC0",
      Reverse_Solidus & "uD800" & Reverse_Solidus & "uDC0");

   Check_Depth_Boundaries;

   declare
      Long_Text   : constant String (1 .. 4_096) := [others => 'a'];
      Long_Number : constant String := "1." & String'(1 .. 4_096 => '0');
   begin
      Check_Valid_Text_Splits
        (Quote & Long_Text & Quote,
         Expected_String => Long_Text);
      Check_Valid_Splits
        (Long_Number,
         Expected_Number_Octets => Count (Long_Number'Length),
         Expected_Number_Text   => Long_Number);
   end;

   Check_Lifecycle;
end Flyology_JSON.Parser_Core_Tests;
