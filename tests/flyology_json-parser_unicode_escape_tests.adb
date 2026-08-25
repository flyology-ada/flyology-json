with Ada.Streams;
with Flyology_JSON.Parser_Core;
with Interfaces;

procedure Flyology_JSON.Parser_Unicode_Escape_Tests is

   package Core renames Flyology_JSON.Parser_Core;

   use type Ada.Streams.Stream_Element_Count;
   use type Ada.Streams.Stream_Element;
   use type Core.Byte_Offset;
   use type Core.Decoded_Fragment_Kind;
   use type Core.Error_Code;
   use type Core.Event_Kind;
   use type Core.Next_Outcome;
   use type Core.Source_Range;
   use type Interfaces.Unsigned_32;

   subtype Count is Ada.Streams.Stream_Element_Count;
   subtype Offset is Ada.Streams.Stream_Element_Offset;
   subtype U32 is Interfaces.Unsigned_32;

   --  Explicit storage for this scalar-focused fixture set, not parser defaults.
   Test_Name_Octet_Capacity : constant := 64;
   Test_Name_Capacity       : constant := 8;

   type Scalar_Observation is record
      Outcome          : Core.Next_Outcome := Core.Need_Input;
      Diagnostic       : Core.Diagnostic := (Code => Core.No_Error, Offset => 0);
      Decoded          : Ada.Streams.Stream_Element_Array (1 .. 4) := [others => 0];
      Decoded_Length   : Natural := 0;
      Text_Open        : Boolean := False;
      Text_Next_Source : Core.Byte_Offset := 0;
      Scalar_Count     : Natural := 0;
   end record;

   procedure Check (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Check;

   function To_Input (Text : String; First : Offset) return Ada.Streams.Stream_Element_Array is
      Result : Ada.Streams.Stream_Element_Array (First .. First + Offset (Text'Length) - 1);
   begin
      if Text'Length > 0 then
         for Position in 0 .. Text'Length - 1 loop
            Result (First + Offset (Position)) :=
              Ada.Streams.Stream_Element (Character'Pos (Text (Text'First + Position)));
         end loop;
      end if;
      return Result;
   end To_Input;

   function Hex_Digit (Value : Natural) return Character is
     (if Value < 10 then Character'Val (Character'Pos ('0') + Value)
      else Character'Val (Character'Pos ('A') + Value - 10));

   function Escape (Unit : Natural) return String is
      Result : String (1 .. 6);
   begin
      Result (1) := '\';
      Result (2) := 'u';
      Result (3) := Hex_Digit ((Unit / 16#1000#) mod 16);
      Result (4) := Hex_Digit ((Unit / 16#100#) mod 16);
      Result (5) := Hex_Digit ((Unit / 16#10#) mod 16);
      Result (6) := Hex_Digit (Unit mod 16);
      return Result;
   end Escape;

   function Encode_UTF8 (Code_Point : U32) return Scalar_Observation is
      Result : Scalar_Observation;
   begin
      if Code_Point <= 16#7F# then
         Result.Decoded_Length := 1;
         Result.Decoded (1) := Ada.Streams.Stream_Element (Code_Point);
      elsif Code_Point <= 16#7FF# then
         Result.Decoded_Length := 2;
         Result.Decoded (1) := 16#C0# or Ada.Streams.Stream_Element (Code_Point / 2**6);
         Result.Decoded (2) := 16#80# or Ada.Streams.Stream_Element (Code_Point and 16#3F#);
      elsif Code_Point <= 16#FFFF# then
         Result.Decoded_Length := 3;
         Result.Decoded (1) := 16#E0# or Ada.Streams.Stream_Element (Code_Point / 2**12);
         Result.Decoded (2) :=
           16#80# or Ada.Streams.Stream_Element ((Code_Point / 2**6) and 16#3F#);
         Result.Decoded (3) := 16#80# or Ada.Streams.Stream_Element (Code_Point and 16#3F#);
      else
         Result.Decoded_Length := 4;
         Result.Decoded (1) := 16#F0# or Ada.Streams.Stream_Element (Code_Point / 2**18);
         Result.Decoded (2) :=
           16#80# or Ada.Streams.Stream_Element ((Code_Point / 2**12) and 16#3F#);
         Result.Decoded (3) :=
           16#80# or Ada.Streams.Stream_Element ((Code_Point / 2**6) and 16#3F#);
         Result.Decoded (4) := 16#80# or Ada.Streams.Stream_Element (Code_Point and 16#3F#);
      end if;
      return Result;
   end Encode_UTF8;

   procedure Observe
     (Item        : Core.Event;
      Exact_Input : Ada.Streams.Stream_Element_Array;
      Input_First : Core.Byte_Offset;
      Seen        : in out Scalar_Observation) is
   begin
      if Item.Has_Raw_Slice then
         Check (Item.Raw_Slice.First_Count <= Exact_Input'Length, "raw range starts outside input");
         Check
           (Item.Raw_Slice.Octet_Length <= Exact_Input'Length - Item.Raw_Slice.First_Count,
            "raw range ends outside input");
         Check
           (Item.Source.First = Input_First + Core.Byte_Offset (Item.Raw_Slice.First_Count),
            "raw range has the wrong absolute source");
         Check
           (Item.Source.Octet_Length = Core.Byte_Offset (Item.Raw_Slice.Octet_Length),
            "raw and absolute source lengths differ");
      end if;

      case Item.Kind is
         when Core.String_Begin =>
            Check (not Seen.Text_Open, "nested string begin");
            Check (Item.Source = (First => 0, Octet_Length => 1), "wrong opening quote source");
            Seen.Text_Open := True;
            Seen.Text_Next_Source := 1;

         when Core.String_Fragment =>
            Check (Seen.Text_Open, "string fragment outside string");
            Check (Item.Source.First = Seen.Text_Next_Source, "fragment source gap or overlap");
            Seen.Text_Next_Source := Seen.Text_Next_Source + Item.Source.Octet_Length;

            if Item.Decoded_Kind = Core.Decoded_Inline_Scalar then
               Seen.Scalar_Count := Seen.Scalar_Count + 1;
               Check (Seen.Scalar_Count = 1, "one escape emitted more than one scalar");
               Seen.Decoded_Length := Item.Decoded.Length;
               for Position in 1 .. Item.Decoded.Length loop
                  Seen.Decoded (Offset (Position)) := Item.Decoded.Octets (Position);
               end loop;
               Check
                 (Item.Decoded_Source.First = 1,
                  "decoded escape provenance does not begin at the reverse solidus");
               Check
                 (Item.Decoded_Source.First + Item.Decoded_Source.Octet_Length
                    = Item.Source.First + Item.Source.Octet_Length,
                  "decoded escape provenance does not end with its current raw fragment");
            else
               Check
                 (Item.Decoded_Kind = Core.No_Decoded_Fragment,
                  "escape unexpectedly exposed undecoded source as decoded text");
            end if;

         when Core.String_End =>
            Check (Seen.Text_Open, "string end outside string");
            Check (Item.Source.First = Seen.Text_Next_Source, "closing quote source gap or overlap");
            Check (Item.Source.Octet_Length = 1, "wrong closing quote source length");
            Seen.Text_Next_Source := Seen.Text_Next_Source + 1;
            Seen.Text_Open := False;

         when others =>
            null;
      end case;
   end Observe;

   procedure Drain
     (Parser      : in out Core.Parser;
      Input       : Ada.Streams.Stream_Element_Array;
      Input_First : Core.Byte_Offset;
      Final_Input : Boolean;
      Seen        : in out Scalar_Observation)
   is
      Used   : Count := 0;
      Result : Core.Next_Result;
   begin
      loop
         if Used < Input'Length then
            declare
               First : constant Offset := Input'First + Offset (Used);
            begin
               Core.Next (Parser, Input (First .. Input'Last), Final_Input, Result);
               if Result.Outcome = Core.Event_Ready then
                  Observe
                    (Result.Item,
                     Input (First .. Input'Last),
                     Input_First + Core.Byte_Offset (Used),
                     Seen);
               end if;
            end;
         else
            declare
               Empty : Ada.Streams.Stream_Element_Array (1 .. 0);
            begin
               Core.Next (Parser, Empty, Final_Input, Result);
               if Result.Outcome = Core.Event_Ready then
                  Observe (Result.Item, Empty, Input_First + Core.Byte_Offset (Used), Seen);
               end if;
            end;
         end if;

         Check (Result.Consumed <= Input'Length - Used, "consumed beyond supplied suffix");
         Used := Used + Result.Consumed;
         case Result.Outcome is
            when Core.Event_Ready =>
               null;
            when Core.Need_Input =>
               Check (Used = Input'Length, "Need_Input left an unconsumed suffix");
               Seen.Outcome := Result.Outcome;
               return;
            when Core.Document_Complete | Core.Parse_Failed | Core.Call_Rejected =>
               Seen.Outcome := Result.Outcome;
               Seen.Diagnostic := Result.Diagnostic;
               return;
         end case;
      end loop;
   end Drain;

   function Parse (Document : String; Split : Natural) return Scalar_Observation is
      Parser : Core.Parser (1, Test_Name_Octet_Capacity, Test_Name_Capacity, Core.Reject_Duplicates);
      Seen   : Scalar_Observation;
   begin
      Core.Initialize (Parser);
      if Split > 0 then
         Drain
           (Parser,
            To_Input (Document (Document'First .. Document'First + Split - 1), -17),
            0,
            False,
            Seen);
         if Seen.Outcome /= Core.Need_Input then
            return Seen;
         end if;
      end if;

      Drain
        (Parser,
         To_Input (Document (Document'First + Split .. Document'Last), 23),
         Core.Byte_Offset (Split),
         True,
         Seen);
      return Seen;
   end Parse;

   function Parse_One_Byte (Document : String) return Scalar_Observation is
      Parser : Core.Parser (1, Test_Name_Octet_Capacity, Test_Name_Capacity, Core.Reject_Duplicates);
      Seen   : Scalar_Observation;
   begin
      Core.Initialize (Parser);
      for Position in 0 .. Document'Length - 1 loop
         Drain
           (Parser,
            To_Input ("", Offset (-43 + Position)),
            Core.Byte_Offset (Position),
            False,
            Seen);
         if Seen.Outcome /= Core.Need_Input then
            return Seen;
         end if;

         Drain
           (Parser,
            To_Input
              (Document (Document'First + Position .. Document'First + Position),
               Offset (-31 + Position)),
            Core.Byte_Offset (Position),
            Position = Document'Length - 1,
            Seen);
         if Position < Document'Length - 1 and then Seen.Outcome /= Core.Need_Input then
            return Seen;
         end if;
      end loop;
      return Seen;
   end Parse_One_Byte;

   procedure Check_Valid (Seen : Scalar_Observation; Code_Point : U32; Length : Natural) is
      Expected : constant Scalar_Observation := Encode_UTF8 (Code_Point);
   begin
      Check (Seen.Outcome = Core.Document_Complete, "valid Unicode escape was rejected");
      Check (not Seen.Text_Open, "valid escape left its string open");
      Check (Seen.Text_Next_Source = Core.Byte_Offset (Length), "valid escape source is incomplete");
      Check (Seen.Scalar_Count = 1, "valid escape did not emit exactly one decoded scalar");
      Check (Seen.Decoded_Length = Expected.Decoded_Length, "wrong decoded UTF-8 length");
      for Position in 1 .. Seen.Decoded_Length loop
         Check
           (Seen.Decoded (Offset (Position)) = Expected.Decoded (Offset (Position)),
            "wrong decoded UTF-8 bytes");
      end loop;
   end Check_Valid;

   procedure Check_Invalid (Seen : Scalar_Observation) is
   begin
      Check (Seen.Outcome = Core.Parse_Failed, "isolated surrogate was accepted");
      Check (Seen.Diagnostic.Code = Core.Invalid_Surrogate, "wrong isolated-surrogate error");
      Check (Seen.Diagnostic.Offset = 1, "wrong isolated-surrogate blame offset");
      Check (Seen.Scalar_Count = 0, "invalid surrogate published a decoded scalar");
   end Check_Invalid;

   procedure Check_Valid_Schedules (Document : String; Code_Point : U32) is
   begin
      for Split in 0 .. Document'Length loop
         Check_Valid (Parse (Document, Split), Code_Point, Document'Length);
      end loop;
      Check_Valid (Parse_One_Byte (Document), Code_Point, Document'Length);
   end Check_Valid_Schedules;

   procedure Check_Invalid_Schedules (Document : String) is
   begin
      for Split in 0 .. Document'Length loop
         Check_Invalid (Parse (Document, Split));
      end loop;
      Check_Invalid (Parse_One_Byte (Document));
   end Check_Invalid_Schedules;

   Quote : constant Character := '"';

begin
   --  Exhaust every UTF-16 code unit through the parser, rather than only the
   --  isolated escape decoder.  Non-surrogates must produce one scalar;
   --  isolated high and low surrogates must fail at their opening reverse solidus.
   for Unit in Natural range 0 .. 16#FFFF# loop
      declare
         Document : constant String := Quote & Escape (Unit) & Quote;
         Seen     : constant Scalar_Observation := Parse (Document, 0);
      begin
         if Unit in 16#D800# .. 16#DFFF# then
            Check_Invalid (Seen);
         else
            Check_Valid (Seen, U32 (Unit), Document'Length);
         end if;
      end;
   end loop;

   --  Exhaust all 1,048,576 legal high/low combinations through the complete
   --  parser.  This is campaign coverage, not a Unicode policy or API limit.
   for High in Natural range 16#D800# .. 16#DBFF# loop
      for Low in Natural range 16#DC00# .. 16#DFFF# loop
         declare
            Document : constant String := Quote & Escape (High) & Escape (Low) & Quote;
            Point    : constant U32 :=
              16#10000# + U32 (High - 16#D800#) * 16#400# + U32 (Low - 16#DC00#);
         begin
            Check_Valid (Parse (Document, 0), Point, Document'Length);
         end;
      end loop;
   end loop;

   --  Every split for scalar-width and surrogate boundary classes.
   Check_Valid_Schedules (Quote & Escape (16#0000#) & Quote, 16#0000#);
   Check_Valid_Schedules (Quote & Escape (16#001F#) & Quote, 16#001F#);
   Check_Valid_Schedules (Quote & Escape (16#007F#) & Quote, 16#007F#);
   Check_Valid_Schedules (Quote & Escape (16#0080#) & Quote, 16#0080#);
   Check_Valid_Schedules (Quote & Escape (16#07FF#) & Quote, 16#07FF#);
   Check_Valid_Schedules (Quote & Escape (16#0800#) & Quote, 16#0800#);
   Check_Valid_Schedules (Quote & Escape (16#D7FF#) & Quote, 16#D7FF#);
   Check_Valid_Schedules (Quote & Escape (16#E000#) & Quote, 16#E000#);
   Check_Valid_Schedules (Quote & Escape (16#FFFF#) & Quote, 16#FFFF#);

   Check_Invalid_Schedules (Quote & Escape (16#D800#) & Quote);
   Check_Invalid_Schedules (Quote & Escape (16#DBFF#) & Quote);
   Check_Invalid_Schedules (Quote & Escape (16#DC00#) & Quote);
   Check_Invalid_Schedules (Quote & Escape (16#DFFF#) & Quote);

   Check_Valid_Schedules
     (Quote & Escape (16#D800#) & Escape (16#DC00#) & Quote,
      16#10000#);
   Check_Valid_Schedules
     (Quote & Escape (16#D800#) & Escape (16#DFFF#) & Quote,
      16#103FF#);
   Check_Valid_Schedules
     (Quote & Escape (16#DBFF#) & Escape (16#DC00#) & Quote,
      16#10FC00#);
   Check_Valid_Schedules
     (Quote & Escape (16#DBFF#) & Escape (16#DFFF#) & Quote,
      16#10FFFF#);
   Check_Valid_Schedules (Quote & "\ud83d\ude00" & Quote, 16#1F600#);
end Flyology_JSON.Parser_Unicode_Escape_Tests;
