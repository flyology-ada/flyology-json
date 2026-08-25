with Ada.Streams;
with Flyology_JSON.Parser_Core;
with Interfaces;
with System;

procedure Flyology_JSON.Parser_Core_Tests is

   package Core renames Flyology_JSON.Parser_Core;

   use type Ada.Streams.Stream_Element_Count;
   use type Ada.Streams.Stream_Element;
   use type Core.Byte_Offset;
   use type Core.Buffered_Slice_Status;
   use type Core.Chunk_Range;
   use type Core.Decoded_Fragment_Kind;
   use type Core.Diagnostic;
   use type Core.Drain_Stop;
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
   Test_Text_Capacity       : constant := 8_192;
   Test_Fragment_Capacity   : constant := 64;
   Test_Name_Octet_Capacity : constant := Test_Text_Capacity;
   Test_Name_Capacity       : constant := 256;

   type Fragment_Observation is record
      Kind           : Core.Event_Kind := Core.String_Fragment;
      Source         : Core.Source_Range := (First => 0, Octet_Length => 0);
      Decoded_Kind   : Core.Decoded_Fragment_Kind := Core.No_Decoded_Fragment;
      Decoded_Source : Core.Source_Range := (First => 0, Octet_Length => 0);
      Decoded_Length : Natural := 0;
   end record;

   type Fragment_Observations is array (Positive range 1 .. Test_Fragment_Capacity) of Fragment_Observation;

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

   procedure Append (Target : in out String; Length : in out Natural; Value : Ada.Streams.Stream_Element) is
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
         when Core.Name_Begin | Core.String_Begin       =>
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

         when Core.Name_End | Core.String_End           =>
            Check (Seen.Text_Open, "text end has no open text token");
            Check (Item.Source.First = Seen.Text_Next_Source, "text end is not source-contiguous");
            Check (Item.Source.Octet_Length = 1, "text end does not cover its quote");
            Seen.Text_Next_Source := Seen.Text_Next_Source + Item.Source.Octet_Length;
            Seen.Text_Open := False;

         when Core.Number_Begin                         =>
            Check (not Seen.Number_Open, "number began while another number was open");
            Check (Item.Source.Octet_Length = 0, "number begin unexpectedly consumed source");
            Seen.Number_Open := True;
            Seen.Number_Next_Source := Item.Source.First;

         when Core.Number_Fragment                      =>
            Check (Seen.Number_Open, "number fragment has no open number token");
            Check
              (Item.Source.First = Seen.Number_Next_Source,
               "number source fragments have a gap, overlap, or reordering");
            Seen.Number_Next_Source := Seen.Number_Next_Source + Item.Source.Octet_Length;

         when Core.Number_End                           =>
            Check (Seen.Number_Open, "number end has no open number token");
            Check (Item.Source.First = Seen.Number_Next_Source, "number end source is not contiguous");
            Check (Item.Source.Octet_Length = 0, "number end unexpectedly consumed source");
            Seen.Number_Open := False;

         when others                                    =>
            null;
      end case;

      if Item.Has_Raw_Slice then
         Check
           (Item.Raw_Slice.First_Count <= Exact_Input'Length, "raw slice starts beyond the exact Next input");
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
                  Exact_Input (Exact_Input'First + Offset (Item.Raw_Slice.First_Count) + Offset (Position)));

               if Item.Kind = Core.Number_Fragment then
                  Append
                    (Seen.Number_Text,
                     Seen.Number_Length,
                     Exact_Input
                       (Exact_Input'First + Offset (Item.Raw_Slice.First_Count) + Offset (Position)));
               end if;
            end loop;
         end if;
      end if;

      case Item.Decoded_Kind is
         when Core.No_Decoded_Fragment   =>
            null;

         when Core.Decoded_Is_Raw_Range  =>
            Check (Item.Has_Raw_Slice, "decoded raw range has no exact input association");
            Check (Item.Decoded_Source = Item.Source, "decoded raw source is not the event source");
            Check
              (Item.Raw_Slice.Octet_Length = Count (Item.Decoded_Source.Octet_Length),
               "decoded raw range lengths disagree");

            for Position in Count range 0 .. Item.Raw_Slice.Octet_Length - 1 loop
               Append_Decoded
                 (Exact_Input (Exact_Input'First + Offset (Item.Raw_Slice.First_Count) + Offset (Position)));
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
               Decoded_Source =>
                 (if Item.Decoded_Kind = Core.No_Decoded_Fragment
                  then (First => 0, Octet_Length => 0)
                  else Item.Decoded_Source),
               Decoded_Length =>
                 (if Item.Decoded_Kind = Core.Decoded_Inline_Scalar then Item.Decoded.Length else 0));
         end if;
      end if;
   end Observe_Event;

   function Equivalent_Event (Left, Right : Core.Event) return Boolean is
   begin
      if Left.Kind /= Right.Kind
        or else Left.Source /= Right.Source
        or else Left.Has_Raw_Slice /= Right.Has_Raw_Slice
        or else Left.Decoded_Kind /= Right.Decoded_Kind
      then
         return False;
      end if;

      if Left.Has_Raw_Slice and then Left.Raw_Slice /= Right.Raw_Slice then
         return False;
      end if;

      case Left.Decoded_Kind is
         when Core.No_Decoded_Fragment   =>
            null;

         when Core.Decoded_Is_Raw_Range  =>
            if Left.Decoded_Source /= Right.Decoded_Source then
               return False;
            end if;

         when Core.Decoded_Inline_Scalar =>
            if Left.Decoded_Source /= Right.Decoded_Source or else Left.Decoded.Length /= Right.Decoded.Length
            then
               return False;
            end if;
            for Position in 1 .. Left.Decoded.Length loop
               if Left.Decoded.Octets (Position) /= Right.Decoded.Octets (Position) then
                  return False;
               end if;
            end loop;
      end case;

      return Left.Kind /= Core.Boolean_Value or else Left.Boolean_Data = Right.Boolean_Data;
   end Equivalent_Event;

   procedure Check_Buffered_Event
     (Buffered_Item : Core.Buffered_Event;
      Plain_Item    : Core.Event;
      Input_First   : Core.Byte_Offset;
      Input_Length  : Count)
   is
      Slice  : Core.Chunk_Range;
      Status : Core.Buffered_Slice_Status;
   begin
      Check (Core.Buffered_Kind (Buffered_Item) = Plain_Item.Kind, "buffered drain event kind changed");
      Check (Core.Buffered_Source (Buffered_Item) = Plain_Item.Source, "buffered drain source range changed");
      Check
        (Core.Buffered_Has_Raw_Slice (Buffered_Item) = Plain_Item.Has_Raw_Slice,
         "buffered drain raw presence changed");
      Check
        (Core.Buffered_Decoded_Kind (Buffered_Item) = Plain_Item.Decoded_Kind,
         "buffered drain decoded kind changed");

      Core.Resolve_Buffered_Raw_Range (Buffered_Item, Input_First, Input_Length, Slice, Status);
      if Plain_Item.Has_Raw_Slice then
         Check (Status = Core.Slice_Resolved, "buffered raw slice did not resolve in its producing window");
         Check (Slice = Plain_Item.Raw_Slice, "buffered raw slice changed");

         Core.Resolve_Buffered_Raw_Range
           (Buffered_Item,
            Plain_Item.Source.First + Plain_Item.Source.Octet_Length,
            0,
            Slice,
            Status);
         Check (Status = Core.Range_Outside_Window, "outside buffered raw coordinates were accepted");
         Check (Slice = (First_Count => 0, Octet_Length => 0), "stale buffered resolution returned a range");

         Core.Resolve_Buffered_Raw_Range (Buffered_Item, Input_First, 0, Slice, Status);
         Check (Status = Core.Range_Outside_Window, "short buffered raw window was accepted");
         Check (Slice = (First_Count => 0, Octet_Length => 0), "short buffered window returned a range");
      else
         Check (Status = Core.No_Raw_Slice, "buffered event without raw source resolved a slice");
         Check (Slice = (First_Count => 0, Octet_Length => 0), "raw-free buffered event returned a range");
      end if;

      case Plain_Item.Decoded_Kind is
         when Core.No_Decoded_Fragment   =>
            null;

         when Core.Decoded_Is_Raw_Range  =>
            Check
              (Core.Buffered_Decoded_Source (Buffered_Item) = Plain_Item.Decoded_Source,
               "buffered decoded raw source changed");

         when Core.Decoded_Inline_Scalar =>
            declare
               Scalar : constant Core.Inline_Scalar := Core.Buffered_Decoded_Scalar (Buffered_Item);
            begin
               Check (Core.Buffered_Decoded_Source (Buffered_Item) = Plain_Item.Decoded_Source,
                      "buffered inline source changed");
               Check (Scalar.Length = Plain_Item.Decoded.Length, "buffered inline length changed");
               for Position in 1 .. Scalar.Length loop
                  Check
                    (Scalar.Octets (Position) = Plain_Item.Decoded.Octets (Position),
                     "buffered inline octets changed");
               end loop;
            end;
      end case;

      if Plain_Item.Kind = Core.Boolean_Value then
         Check
           (Core.Buffered_Boolean_Data (Buffered_Item) = Plain_Item.Boolean_Data,
            "buffered Boolean value changed");
      end if;
   end Check_Buffered_Event;

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
            when Core.Event_Ready                                                =>
               if Result.Item.Kind = Core.Number_Fragment then
                  Seen.Number_Fragment_Octets :=
                    Seen.Number_Fragment_Octets + Result.Item.Raw_Slice.Octet_Length;
               end if;

            when Core.Need_Input                                                 =>
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

   procedure Drain_Batched
     (Parser       : in out Core.Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      Input_First  : Core.Byte_Offset;
      Final_Input  : Boolean;
      Capacity     : Positive;
      Buffer_First : Offset;
      Seen         : in out Observation)
   is
      Events : Core.Event_Array (Buffer_First .. Buffer_First + Offset (Capacity) - 1);
      Used   : Count := 0;
      Result : Core.Drain_Result;
   begin
      loop
         if Used < Input'Length then
            declare
               First       : constant Offset := Input'First + Offset (Used);
               Exact_First : constant Core.Byte_Offset := Input_First + Core.Byte_Offset (Used);
               Exact_Input : Ada.Streams.Stream_Element_Array renames Input (First .. Input'Last);
            begin
               Core.Drain (Parser, Exact_Input, Final_Input, Events, Result);
               if Result.Produced > 0 then
                  for Position in Count range 0 .. Result.Produced - 1 loop
                     Observe_Event
                       (Events (Events'First + Offset (Position)), Exact_Input, Exact_First, Seen);
                     if Events (Events'First + Offset (Position)).Kind = Core.Number_Fragment then
                        Seen.Number_Fragment_Octets :=
                          Seen.Number_Fragment_Octets
                          + Events (Events'First + Offset (Position)).Raw_Slice.Octet_Length;
                     end if;
                  end loop;
               end if;
            end;
         else
            declare
               Empty : Ada.Streams.Stream_Element_Array (19 .. 18);
            begin
               Core.Drain (Parser, Empty, Final_Input, Events, Result);
               if Result.Produced > 0 then
                  for Position in Count range 0 .. Result.Produced - 1 loop
                     Observe_Event
                       (Events (Events'First + Offset (Position)),
                        Empty,
                        Input_First + Core.Byte_Offset (Used),
                        Seen);
                  end loop;
               end if;
            end;
         end if;

         Check (Result.Consumed <= Input'Length - Used, "batched drain consumed beyond its input");
         Used := Used + Result.Consumed;

         case Result.Stop is
            when Core.Drain_Buffer_Full       =>
               Check
                 (Result.Produced = Count (Events'Length),
                  "non-null batched drain stopped before filling its event buffer");

            when Core.Drain_Need_Input        =>
               Check (Used = Input'Length, "batched drain requested input before consuming its chunk");
               Seen.Outcome := Core.Need_Input;
               exit;

            when Core.Drain_Document_Complete =>
               Seen.Outcome := Core.Document_Complete;
               Seen.Diagnostic := Result.Diagnostic;
               exit;

            when Core.Drain_Parse_Failed      =>
               Seen.Outcome := Core.Parse_Failed;
               Seen.Diagnostic := Result.Diagnostic;
               exit;

            when Core.Drain_Call_Rejected     =>
               Seen.Outcome := Core.Call_Rejected;
               Seen.Diagnostic := Result.Diagnostic;
               exit;
         end case;
      end loop;
   end Drain_Batched;

   function Parse (Text : String; Split : Natural; Maximum_Depth : Natural := 8) return Observation is
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

   function Parse_Batched
     (Text          : String;
      Split         : Natural;
      Capacity      : Positive;
      Buffer_First  : Offset;
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
            Drain_Batched (Parser, Prefix, 0, False, Capacity, Buffer_First, Seen);
            if Seen.Outcome /= Core.Need_Input then
               return Seen;
            end if;
         end;
      end if;

      declare
         Suffix : constant Ada.Streams.Stream_Element_Array :=
           To_Input (Text (Text'First + Split .. Text'Last), 11);
      begin
         Drain_Batched (Parser, Suffix, Core.Byte_Offset (Split), True, Capacity, Buffer_First, Seen);
      end;

      return Seen;
   end Parse_Batched;

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
               Empty : constant Ada.Streams.Stream_Element_Array := To_Input ("", Offset (-47 + Position));
            begin
               Drain (Parser, Empty, Core.Byte_Offset (Position), False, Seen);
               if Seen.Outcome /= Core.Need_Input then
                  return Seen;
               end if;
            end;

            declare
               One : constant Ada.Streams.Stream_Element_Array :=
                 To_Input (Text (Text'First + Position .. Text'First + Position), Offset (-23 + Position));
            begin
               Drain (Parser, One, Core.Byte_Offset (Position), Position = Text'Length - 1, Seen);
               if Position < Text'Length - 1 and then Seen.Outcome /= Core.Need_Input then
                  return Seen;
               end if;
            end;
         end loop;
      end if;

      return Seen;
   end Parse_One_Byte;

   function Parse_Randomized
     (Text                : String;
      Seed                : Interfaces.Unsigned_32;
      Maximum_Depth       : Natural := 8;
      Name_Octet_Capacity : Natural := Test_Name_Octet_Capacity;
      Name_Capacity       : Natural := Test_Name_Capacity) return Observation
   is
      --  Campaign data only.  These LCG coefficients do not affect parser behavior.
      Generator : Interfaces.Unsigned_32 := Seed;
      Parser    : Core.Parser (Maximum_Depth, Name_Octet_Capacity, Name_Capacity);
      Seen      : Observation;
      Position  : Natural := 0;
   begin
      Core.Initialize (Parser);

      while Position < Text'Length loop
         Generator := Generator * 1_664_525 + 1_013_904_223;

         if (Generator and 3) = 0 then
            declare
               Empty : constant Ada.Streams.Stream_Element_Array := To_Input ("", Offset (-41 + Position));
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
                (Text (Text'First + Position .. Text'First + Position + Length - 1), Offset (37 + Position));
         begin
            Drain (Parser, Chunk, Core.Byte_Offset (Position), Position + Length = Text'Length, Seen);
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

   function Parse_Randomized_Batched
     (Text                : String;
      Seed                : Interfaces.Unsigned_32;
      Capacity            : Positive;
      Buffer_First        : Offset;
      Maximum_Depth       : Natural := 8;
      Name_Octet_Capacity : Natural := Test_Name_Octet_Capacity;
      Name_Capacity       : Natural := Test_Name_Capacity) return Observation
   is
      --  Match Parse_Randomized's input schedule while independently varying
      --  the event buffer's capacity and lower bound.
      Generator : Interfaces.Unsigned_32 := Seed;
      Parser    : Core.Parser (Maximum_Depth, Name_Octet_Capacity, Name_Capacity);
      Seen      : Observation;
      Position  : Natural := 0;
   begin
      Core.Initialize (Parser);

      while Position < Text'Length loop
         Generator := Generator * 1_664_525 + 1_013_904_223;

         if (Generator and 3) = 0 then
            declare
               Empty : constant Ada.Streams.Stream_Element_Array := To_Input ("", Offset (-41 + Position));
            begin
               Drain_Batched
                 (Parser, Empty, Core.Byte_Offset (Position), False, Capacity, Buffer_First, Seen);
               Check (Seen.Outcome = Core.Need_Input, "empty chunk changed batched progress");
            end;
         end if;

         declare
            Remaining : constant Natural := Text'Length - Position;
            Requested : constant Natural := Natural (Generator mod 17) + 1;
            Length    : constant Natural := Natural'Min (Remaining, Requested);
            Chunk     : constant Ada.Streams.Stream_Element_Array :=
              To_Input
                (Text (Text'First + Position .. Text'First + Position + Length - 1), Offset (37 + Position));
         begin
            Drain_Batched
              (Parser,
               Chunk,
               Core.Byte_Offset (Position),
               Position + Length = Text'Length,
               Capacity,
               Buffer_First,
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
   end Parse_Randomized_Batched;

   function Parse_Partition
     (Text : String; Boundaries : Interfaces.Unsigned_32; Allow_Failure : Boolean := False) return Observation
   is
      Parser      : Core.Parser (8, Test_Name_Octet_Capacity, Test_Name_Capacity);
      Seen        : Observation;
      Chunk_First : Natural := 0;
   begin
      Check (Text'Length > 0, "partition schedule requires a nonempty fixture");
      Core.Initialize (Parser);

      for Position in 0 .. Text'Length - 1 loop
         if Position = Text'Length - 1 or else (Boundaries and Interfaces.Shift_Left (1, Position)) /= 0 then
            declare
               Chunk : constant Ada.Streams.Stream_Element_Array :=
                 To_Input
                   (Text (Text'First + Chunk_First .. Text'First + Position), Offset (-31 + Chunk_First));
            begin
               Drain (Parser, Chunk, Core.Byte_Offset (Chunk_First), Position = Text'Length - 1, Seen);
               if Position < Text'Length - 1 then
                  if Allow_Failure and then Seen.Outcome = Core.Parse_Failed then
                     return Seen;
                  end if;
                  Check (Seen.Outcome = Core.Need_Input, "partition schedule terminated early");
               end if;
            end;
            Chunk_First := Position + 1;
         end if;
      end loop;

      return Seen;
   end Parse_Partition;

   procedure Check_All_Partitions (Text : String; Expected : String) is
      Last_Mask : constant Interfaces.Unsigned_32 := Interfaces.Shift_Left (1, Text'Length - 1) - 1;
   begin
      Check (Text'Length in 1 .. 31, "partition fixture exceeds the test mask");
      for Mask in Interfaces.Unsigned_32 range 0 .. Last_Mask loop
         declare
            Seen : constant Observation := Parse_Partition (Text, Mask);
         begin
            Check (Seen.Outcome = Core.Document_Complete, "valid partition rejected");
            Check (Seen.String_Text (1 .. Seen.String_Length) = Expected, "partition changed decoded text");
         end;
      end loop;
   end Check_All_Partitions;

   procedure Check_Valid_Splits
     (Text                   : String;
      Expected_Number_Octets : Count := 0;
      Expected_Number_Text   : String := "";
      Expected_Arrays        : Natural := 0;
      Expected_Objects       : Natural := 0)
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
         Check (Seen.Name_Text (1 .. Seen.Name_Length) = Expected_Name, Schedule & " changed decoded name");
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

   procedure Check_Invalid (Text : String; Code : Core.Error_Code; At_Byte : Core.Byte_Offset) is
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

   procedure Check_Invalid_Literal (Text : String; Code : Core.Error_Code; At_Byte : Core.Byte_Offset) is
      Longest_JSON_Literal : constant String := "false";
   begin
      Check_Invalid (Text, Code, At_Byte);
      Check
        (Text'Length in 1 .. Longest_JSON_Literal'Length,
         "literal partition fixture exceeds the longest JSON literal");
      declare
         Last_Mask : constant Interfaces.Unsigned_32 := Interfaces.Shift_Left (1, Text'Length - 1) - 1;
      begin
         for Mask in Interfaces.Unsigned_32 range 0 .. Last_Mask loop
            declare
               Seen : constant Observation := Parse_Partition (Text, Mask, Allow_Failure => True);
            begin
               Check (Seen.Outcome = Core.Parse_Failed, "partition schedule accepted invalid input");
               Check (Seen.Diagnostic.Code = Code, "partition schedule changed the error code");
               Check (Seen.Diagnostic.Offset = At_Byte, "partition schedule changed the error offset");
            end;
         end loop;
      end;
   end Check_Invalid_Literal;

   procedure Check_Duplicate
     (Text                 : String;
      At_Byte              : Core.Byte_Offset;
      Expected_Name_Begins : Natural := 2;
      Expected_Name_Ends   : Natural := 1)
   is
      procedure Check_Observation (Seen : Observation; Schedule : String) is
      begin
         Check (Seen.Outcome = Core.Parse_Failed, Schedule & " accepted a duplicate name");
         Check (Seen.Diagnostic.Code = Core.Duplicate_Name, Schedule & " changed duplicate status");
         Check (Seen.Diagnostic.Offset = At_Byte, Schedule & " changed duplicate offset");
         Check
           (Seen.Events (Core.Name_Begin) = Expected_Name_Begins,
            Schedule & " changed provisional name begins");
         Check
           (Seen.Events (Core.Name_End) = Expected_Name_Ends, Schedule & "published the rejecting Name_End");
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
            Prefix : constant String := Text (Text'First .. Text'First + Prefix_Length - 1);
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
               Check (Seen.Outcome = Core.Parse_Failed, "one-byte schedule accepted a truncated text prefix");
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
     (Text : String; Expected_Raw : String; Expected_Decoded : String := "") is
   begin
      Check_Malformed_Prefix_Invariance
        (Text, Core.Truncated_Input, Core.Byte_Offset (Text'Length), Expected_Raw, Expected_Decoded);
   end Check_Truncated_Raw_Prefix;

   procedure Check_Literal_Transport is
      Parser : Core.Parser (1, 0, 0);
      Result : Core.Next_Result;
      Empty  : Ada.Streams.Stream_Element_Array (1 .. 0);
   begin
      Core.Initialize (Parser);
      Core.Next (Parser, Empty, False, Result);
      Check (Result.Outcome = Core.Event_Ready, "literal transport omitted document begin");

      declare
         Input : constant Ada.Streams.Stream_Element_Array := To_Input ("null", -29);
      begin
         Core.Next (Parser, Input, True, Result);
         Check (Result.Outcome = Core.Event_Ready, "monolithic null did not emit its value");
         Check (Result.Item.Kind = Core.Null_Value, "monolithic null emitted the wrong event");
         Check (Result.Consumed = 4, "monolithic null reported the wrong consumed count");
         Check (Result.Item.Has_Raw_Slice, "monolithic null lost its raw slice");
         Check
           (Result.Item.Raw_Slice = (First_Count => 0, Octet_Length => 4),
            "monolithic null reported the wrong raw slice");
         Check
           (Result.Item.Source = (First => 0, Octet_Length => 4),
            "monolithic null reported the wrong source range");
      end;

      Core.Next (Parser, Empty, True, Result);
      Check (Result.Outcome = Core.Event_Ready, "monolithic null omitted document end");
      Core.Next (Parser, Empty, True, Result);
      Check (Result.Outcome = Core.Document_Complete, "monolithic null did not complete");
      Core.Reset (Parser);
      Core.Next (Parser, Empty, False, Result);
      declare
         Input : constant Ada.Streams.Stream_Element_Array := To_Input ("true", 43);
      begin
         Core.Next (Parser, Input, False, Result);
         Check (Result.Outcome = Core.Need_Input, "nonfinal exact literal was published early");
         Check (Result.Consumed = 4, "nonfinal exact literal changed its consumed count");
      end;
      declare
         Delimiter : constant Ada.Streams.Stream_Element_Array := To_Input (" ", -17);
      begin
         Core.Next (Parser, Delimiter, True, Result);
         Check (Result.Outcome = Core.Event_Ready, "continued exact literal did not emit");
         Check (Result.Item.Kind = Core.Boolean_Value, "continued true emitted the wrong event");
         Check (Result.Consumed = 0, "literal emission consumed its lookahead delimiter");
         Check (not Result.Item.Has_Raw_Slice, "split literal retained a stale raw slice");
      end;
   end Check_Literal_Transport;

   function Fragment_With_Kind (Seen : Observation; Kind : Core.Decoded_Fragment_Kind) return Positive is
   begin
      for Position in 1 .. Natural'Min (Seen.Fragment_Count, Seen.Fragments'Length) loop
         if Seen.Fragments (Position).Decoded_Kind = Kind then
            return Position;
         end if;
      end loop;

      raise Program_Error with "expected decoded fragment kind was not observed";
   end Fragment_With_Kind;

   Quote               : constant Character := '"';
   Reverse_Solidus     : constant Character := '\';
   Euro                : constant String :=
     Character'Val (16#E2#) & Character'Val (16#82#) & Character'Val (16#AC#);
   E_Acute             : constant String := Character'Val (16#C3#) & Character'Val (16#A9#);
   Combining_Acute     : constant String := Character'Val (16#CC#) & Character'Val (16#81#);
   Grinning_Face       : constant String :=
     Character'Val (16#F0#) & Character'Val (16#9F#) & Character'Val (16#98#) & Character'Val (16#80#);
   First_Supplementary : constant String :=
     Character'Val (16#F0#) & Character'Val (16#90#) & Character'Val (16#80#) & Character'Val (16#80#);
   Last_Scalar         : constant String :=
     Character'Val (16#F4#) & Character'Val (16#8F#) & Character'Val (16#BF#) & Character'Val (16#BF#);

   procedure Check_Simple_Escapes is
   begin
      Check_Valid_Text_Splits
        (Quote & Reverse_Solidus & Quote & Quote, Expected_String => String'(1 => Quote));
      Check_Valid_Text_Splits
        (Quote & Reverse_Solidus & Reverse_Solidus & Quote, Expected_String => String'(1 => Reverse_Solidus));
      Check_Valid_Text_Splits (Quote & Reverse_Solidus & '/' & Quote, Expected_String => "/");
      Check_Valid_Text_Splits
        (Quote & Reverse_Solidus & 'b' & Quote, Expected_String => String'(1 => Character'Val (16#08#)));
      Check_Valid_Text_Splits
        (Quote & Reverse_Solidus & 'f' & Quote, Expected_String => String'(1 => Character'Val (16#0C#)));
      Check_Valid_Text_Splits
        (Quote & Reverse_Solidus & 'n' & Quote, Expected_String => String'(1 => ASCII.LF));
      Check_Valid_Text_Splits
        (Quote & Reverse_Solidus & 'r' & Quote, Expected_String => String'(1 => ASCII.CR));
      Check_Valid_Text_Splits
        (Quote & Reverse_Solidus & 't' & Quote, Expected_String => String'(1 => ASCII.HT));
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
            Exact  : constant String := Nested_Arrays (Maximum);
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
                  Check (Seen.Diagnostic.Offset = Core.Byte_Offset (Maximum), "wrong N+1 depth error offset");
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
        (Text               : String;
         Name_Octets        : Natural;
         Names              : Natural;
         Expected           : Core.Next_Outcome;
         Expected_Code      : Core.Error_Code := Core.No_Error;
         Expected_At        : Core.Byte_Offset := 0;
         Expected_Name_Ends : Natural := 0;
         Check_Prefix       : Boolean := False;
         Expected_Raw       : String := "";
         Expected_Decoded   : String := "")
      is
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
                  Drain (Parser, To_Input (Text (Text'First .. Text'First + Split - 1), -41), 0, False, Seen);
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
                  To_Input (Text (Text'First + Position .. Text'First + Position), Offset (-19 + Position)),
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
               Core.Next (Parser, Input (Input'First + Offset (Used) .. Input'Last), Final_Input, Result);
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
           (Parser : in out Core.Parser; Used : in out Count; Result : out Core.Next_Result) is
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
              (Result.Item.Decoded_Kind = Core.Decoded_Is_Raw_Range, "accepted name prefix was not decoded");
            Check (Result.Item.Source = (First => 2, Octet_Length => 1), "accepted prefix moved");
            Check (Core.State (Parser) = Core.Active, "accepted prefix changed parser state");
         end Reach_Accepted_Prefix;

         procedure Reach_Pending
           (Parser : in out Core.Parser; Used : in out Count; Result : out Core.Next_Result) is
         begin
            Reach_Accepted_Prefix (Parser, Used, Result);
            Next_On_Suffix (Parser, Used, False, Result);
            Check (Result.Outcome = Core.Event_Ready, "denied scalar did not expose raw provenance");
            Check (Result.Item.Kind = Core.Name_Fragment, "denied scalar changed event kind");
            Check
              (Result.Item.Decoded_Kind = Core.No_Decoded_Fragment, "denied scalar was incorrectly decoded");
            Check (Result.Item.Source = (First => 3, Octet_Length => 1), "denied scalar moved");
            Check (Core.State (Parser) = Core.Failure_Pending, "denial was not latched");
            Check
              (Core.Terminal_Diagnostic (Parser) = (Code => Core.Name_Storage_Exhausted, Offset => 1),
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
            Check (Core.Terminal_Diagnostic (Parser) = Primary, "pending abort replaced the primary failure");
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
         Text   : constant String := "{" & Quote & Reverse_Solidus & Quote & Quote & ":0}";
         Input  : constant Ada.Streams.Stream_Element_Array := To_Input (Text, -57);
         Parser : Core.Parser (4, 0, 1);
         Used   : Count := 0;
         Result : Core.Next_Result;

         procedure Expect (Kind : Core.Event_Kind) is
         begin
            Core.Next (Parser, Input (Input'First + Offset (Used) .. Input'Last), False, Result);
            Used := Used + Result.Consumed;
            Check (Result.Outcome = Core.Event_Ready, "short escape setup did not emit an event");
            Check (Result.Item.Kind = Kind, "short escape setup changed event order");
         end Expect;
      begin
         Core.Initialize (Parser);
         Expect (Core.Document_Begin);
         Expect (Core.Object_Begin);
         Expect (Core.Name_Begin);

         Core.Next (Parser, Input (Input'First + Offset (Used) .. Input'Last), False, Result);
         Check (Result.Outcome = Core.Event_Ready, "short escape denial did not emit raw provenance");
         Check (Result.Item.Kind = Core.Name_Fragment, "short escape denial changed event kind");
         Check
           (Result.Item.Decoded_Kind = Core.No_Decoded_Fragment, "short escape denial exposed decoded data");
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
         & Reverse_Solidus
         & "n"
         & Reverse_Solidus
         & "uD83D"
         & Reverse_Solidus
         & "uDE00"
         & Quote,
         0,
         0,
         Core.Document_Complete);
      Check_With_Capacities
        ("["
         & Quote
         & "outer"
         & Reverse_Solidus
         & "t"
         & Quote
         & ",["
         & Quote
         & Euro
         & Reverse_Solidus
         & "u0061"
         & Quote
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
         1,
         Check_Prefix     => True,
         Expected_Raw     => "a",
         Expected_Decoded => "");
      Check_With_Capacities
        ("{" & Quote & Quote & ":0}", 0, 0, Core.Parse_Failed, Core.Duplicate_Index_Exhausted, 1);
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
         7,
         Expected_Name_Ends => 1,
         Check_Prefix       => True,
         Expected_Raw       => "a0a",
         Expected_Decoded   => "a");
      Check_With_Capacities ("{" & Quote & E_Acute & Quote & ":0}", 2, 1, Core.Document_Complete);
      Check_With_Capacities
        ("{" & Quote & E_Acute & Quote & ":0}",
         1,
         1,
         Core.Parse_Failed,
         Core.Name_Storage_Exhausted,
         1,
         Check_Prefix     => True,
         Expected_Raw     => E_Acute,
         Expected_Decoded => "");
      Check_With_Capacities
        ("{" & Quote & Reverse_Solidus & "u20AC" & Quote & ":0}",
         2,
         1,
         Core.Parse_Failed,
         Core.Name_Storage_Exhausted,
         1,
         Check_Prefix     => True,
         Expected_Raw     => Reverse_Solidus & "u20AC",
         Expected_Decoded => "");
      Check_With_Capacities
        ("{" & Quote & Reverse_Solidus & Quote & Quote & ":0}",
         0,
         1,
         Core.Parse_Failed,
         Core.Name_Storage_Exhausted,
         1,
         Check_Prefix     => True,
         Expected_Raw     => Reverse_Solidus & Quote,
         Expected_Decoded => "");
      Check_With_Capacities
        ("{" & Quote & Reverse_Solidus & Reverse_Solidus & Quote & ":0}",
         0,
         1,
         Core.Parse_Failed,
         Core.Name_Storage_Exhausted,
         1,
         Check_Prefix     => True,
         Expected_Raw     => Reverse_Solidus & Reverse_Solidus,
         Expected_Decoded => "");
      Check_With_Capacities
        ("{" & Quote & Grinning_Face & Quote & ":0}",
         3,
         1,
         Core.Parse_Failed,
         Core.Name_Storage_Exhausted,
         1,
         Check_Prefix     => True,
         Expected_Raw     => Grinning_Face,
         Expected_Decoded => "");
      Check_With_Capacities
        ("{" & Quote & Reverse_Solidus & "uD83D" & Reverse_Solidus & "uDE00" & Quote & ":0}",
         3,
         1,
         Core.Parse_Failed,
         Core.Name_Storage_Exhausted,
         1,
         Check_Prefix     => True,
         Expected_Raw     => Reverse_Solidus & "uD83D" & Reverse_Solidus & "uDE00",
         Expected_Decoded => "");
      Check_With_Capacities
        ("{" & Quote & "a" & Quote & ":0," & Quote & "b" & Quote & ":1}", 2, 2, Core.Document_Complete);
      Check_With_Capacities
        ("{" & Quote & "abcde" & Quote & ":0}",
         4,
         1,
         Core.Parse_Failed,
         Core.Name_Storage_Exhausted,
         1,
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
        ("{" & Quote & Character'Val (16#C0#) & Quote & ":0}", 0, 1, Core.Parse_Failed, Core.Invalid_UTF8, 2);
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
         Check (Seen.Diagnostic.Code = Core.Name_Storage_Exhausted, "resource reset setup did not fail");
         Core.Reset (Parser);
         Seen := (others => <>);
         Drain (Parser, To_Input ("{" & Quote & Quote & ":0}", 13), 0, True, Seen);
         Check (Seen.Outcome = Core.Document_Complete, "resource reset left arena storage live");
      end;

      Check_Pending_Failure_Transition;
      Check_Short_Escape_Denial_Event;
   end Check_Duplicate_Capacities;

   procedure Check_Drain_Parity is
      type Capacity_Array is array (Positive range <>) of Positive;
      type Bound_Array is array (Positive range <>) of Offset;

      Capacities : constant Capacity_Array := [1, 2, 3, 4, 7, 16, 64];
      Bounds     : constant Bound_Array := [-31, 0, 29];

      procedure Check_Text (Text : String) is
      begin
         for Split in 0 .. Text'Length loop
            declare
               Expected : constant Observation := Parse (Text, Split);
            begin
               for Capacity of Capacities loop
                  for Buffer_First of Bounds loop
                     declare
                        Actual : constant Observation := Parse_Batched (Text, Split, Capacity, Buffer_First);
                     begin
                        Check
                          (Actual = Expected,
                           "batched transcript changed at split"
                           & Natural'Image (Split)
                           & " capacity"
                           & Positive'Image (Capacity)
                           & " bound"
                           & Offset'Image (Buffer_First));
                     end;
                  end loop;
               end loop;
            end;
         end loop;
      end Check_Text;

      procedure Check_Randomized
        (Text                : String;
         Maximum_Depth       : Natural := 8;
         Name_Octet_Capacity : Natural := Test_Name_Octet_Capacity;
         Name_Capacity       : Natural := Test_Name_Capacity) is
      begin
         for Seed in Interfaces.Unsigned_32 range 1 .. 8 loop
            declare
               Expected : constant Observation :=
                 Parse_Randomized (Text, Seed, Maximum_Depth, Name_Octet_Capacity, Name_Capacity);
            begin
               for Capacity of Capacities loop
                  for Buffer_First of Bounds loop
                     declare
                        Actual : constant Observation :=
                          Parse_Randomized_Batched
                            (Text,
                             Seed,
                             Capacity,
                             Buffer_First,
                             Maximum_Depth,
                             Name_Octet_Capacity,
                             Name_Capacity);
                     begin
                        Check
                          (Actual = Expected,
                           "random batched transcript changed for seed"
                           & Seed'Image
                           & " capacity"
                           & Positive'Image (Capacity)
                           & " bound"
                           & Offset'Image (Buffer_First));
                     end;
                  end loop;
               end loop;
            end;
         end loop;
      end Check_Randomized;

      procedure Check_Capacity_One (Text : String) is
         Input       : constant Ada.Streams.Stream_Element_Array := To_Input (Text, -43);
         Next_Parser : Core.Parser (8, Test_Name_Octet_Capacity, Test_Name_Capacity);
         Many_Parser : Core.Parser (8, Test_Name_Octet_Capacity, Test_Name_Capacity);
         Events      : Core.Event_Array (-17 .. -17);
         Next_Item   : Core.Next_Result;
         Many_Item   : Core.Drain_Result;
         Used        : Count := 0;

         function Outcome return Core.Next_Outcome
         is (case Many_Item.Stop is
               when Core.Drain_Buffer_Full       => Core.Event_Ready,
               when Core.Drain_Need_Input        => Core.Need_Input,
               when Core.Drain_Document_Complete => Core.Document_Complete,
               when Core.Drain_Parse_Failed      => Core.Parse_Failed,
               when Core.Drain_Call_Rejected     => Core.Call_Rejected);

         procedure Compare is
         begin
            Check (Many_Item.Consumed = Next_Item.Consumed, "capacity-one consumed count changed");
            Check (Outcome = Next_Item.Outcome, "capacity-one outcome changed");
            Check (Many_Item.Diagnostic = Next_Item.Diagnostic, "capacity-one diagnostic changed");
            Check (Core.State (Many_Parser) = Core.State (Next_Parser), "capacity-one state changed");
            if Next_Item.Outcome = Core.Event_Ready then
               Check (Many_Item.Produced = 1, "capacity-one drain omitted its event");
               Check
                 (Equivalent_Event (Events (-17), Next_Item.Item),
                  "capacity-one eligible event fields changed");
            else
               Check (Many_Item.Produced = 0, "capacity-one terminal returned an event");
            end if;
         end Compare;
      begin
         Core.Initialize (Next_Parser);
         Core.Initialize (Many_Parser);

         loop
            if Used < Input'Length then
               declare
                  Exact_Input : Ada.Streams.Stream_Element_Array renames
                    Input (Input'First + Offset (Used) .. Input'Last);
               begin
                  Core.Next (Next_Parser, Exact_Input, True, Next_Item);
                  Core.Drain (Many_Parser, Exact_Input, True, Events, Many_Item);
               end;
            else
               declare
                  Empty : Ada.Streams.Stream_Element_Array (41 .. 40);
               begin
                  Core.Next (Next_Parser, Empty, True, Next_Item);
                  Core.Drain (Many_Parser, Empty, True, Events, Many_Item);
               end;
            end if;

            Compare;
            Used := Used + Next_Item.Consumed;
            exit when Next_Item.Outcome /= Core.Event_Ready;
         end loop;
      end Check_Capacity_One;
   begin
      Check_Text ("null");
      Check_Text ("[null,true,false,0,-12.3e+4]");
      --  A partial literal following completed dense-array literals must not
      --  reuse the previous literal's lookahead limit.
      Check_Text ("[null,true,fa");
      Check_Text ("[null,0");
      Check_Text ("[null,00]");
      Check_Text ("[null,0x]");
      Check_Text ("[null,0}");
      Check_Text ("[null,0 ]");
      Check_Text
        (Quote
         & "a"
         & Euro
         & Reverse_Solidus
         & "n"
         & Reverse_Solidus
         & "uD83D"
         & Reverse_Solidus
         & "uDE00"
         & Quote);
      Check_Text ("{" & Quote & "a" & Quote & ":[0," & Quote & Reverse_Solidus & "u20AC" & Quote & "]}");
      Check_Text ("truex");
      Check_Text ("[0,]");
      Check_Text (Quote & "a" & Reverse_Solidus & "x" & Quote);
      Check_Text (Quote & Character'Val (16#E2#) & Character'Val (16#82#));
      Check_Text (Quote & Reverse_Solidus & "uD800" & Reverse_Solidus & "u0041" & Quote);

      Check_Randomized
        ("[null,true,false,0,-12.3e+4,{"
         & Quote
         & "x"
         & Quote
         & ":"
         & Quote
         & Reverse_Solidus
         & "u20AC"
         & Quote
         & "}]");
      Check_Randomized
        ("{" & Quote & "a" & Quote & ":0," & Quote & Reverse_Solidus & "u0061" & Quote & ":1}");
      Check_Randomized ("[[[0]]]", Maximum_Depth => 2);
      Check_Randomized ("{" & Quote & "ab" & Quote & ":0}", Name_Octet_Capacity => 1, Name_Capacity => 1);
      Check_Randomized (Quote & Reverse_Solidus & "uD800" & Quote);

      Check_Capacity_One ("[null,true,false,0,-12.3e+4]");
      Check_Capacity_One
        ("{"
         & Quote
         & "a"
         & Quote
         & ":"
         & Quote
         & Reverse_Solidus
         & "uD83D"
         & Reverse_Solidus
         & "uDE00"
         & Quote
         & "}");
      Check_Capacity_One ("truex");
      Check_Capacity_One (Quote & Reverse_Solidus & "uD800" & Quote);
   end Check_Drain_Parity;

   procedure Check_Drain_Boundaries is
      Empty : Ada.Streams.Stream_Element_Array (7 .. 6);
   begin
      declare
         Parser : Core.Parser (2, 8, 4);
         Input  : constant Ada.Streams.Stream_Element_Array := To_Input ("[]", -9);
         Events : Core.Event_Array (13 .. 12);
         Result : Core.Drain_Result;
      begin
         Core.Initialize (Parser);
         Core.Drain (Parser, Input, True, Events, Result);
         Check (Result.Stop = Core.Drain_Buffer_Full, "null event buffer changed stop reason");
         Check (Result.Consumed = 0, "null event buffer consumed input");
         Check (Result.Produced = 0, "null event buffer produced an event");
         Check (Core.State (Parser) = Core.Ready, "null event buffer changed parser state");

         declare
            One : Core.Next_Result;
         begin
            Core.Next (Parser, Input, True, One);
            Check (One.Outcome = Core.Event_Ready, "null event buffer prevented later parsing");
            Check (One.Item.Kind = Core.Document_Begin, "null event buffer advanced the parser");
         end;
      end;

      declare
         Parser : Core.Parser (2, 8, 4);
         Input  : constant Ada.Streams.Stream_Element_Array := To_Input ("[]", -9);
         Events : Core.Event_Array (-11 .. -10);
         Result : Core.Drain_Result;
      begin
         Core.Initialize (Parser);
         Core.Drain (Parser, Input, True, Events, Result);
         Check (Result.Stop = Core.Drain_Buffer_Full, "first exact-capacity drain did not fill");
         Check (Result.Consumed = 1, "first exact-capacity drain consumed past array begin");
         Check (Result.Produced = 2, "first exact-capacity drain produced the wrong count");
         Check (Events (-11).Kind = Core.Document_Begin, "batched document begin moved");
         Check (Events (-10).Kind = Core.Array_Begin, "batched array begin moved");
         Check
           (Events (-10).Raw_Slice = (First_Count => 0, Octet_Length => 1),
            "batched array begin raw range is not outer-input relative");

         Core.Drain (Parser, Input (Input'Last .. Input'Last), True, Events, Result);
         Check (Result.Stop = Core.Drain_Buffer_Full, "second exact-capacity drain did not fill");
         Check (Result.Consumed = 1, "second exact-capacity drain consumed the wrong count");
         Check (Events (-11).Kind = Core.Array_End, "batched array end moved");
         Check (Events (-10).Kind = Core.Document_End, "batched document end moved");

         Core.Drain (Parser, Empty, True, Events, Result);
         Check
           (Result.Stop = Core.Drain_Document_Complete,
            "exact-capacity drain did not complete on its next call");
         Check (Result.Produced = 0, "completion call returned an event");
      end;

      declare
         Parser : Core.Parser (2, 8, 4);
         Input  : constant Ada.Streams.Stream_Element_Array := To_Input ("[]", 37);
         Events : Core.Event_Array (23 .. 30);
         Result : Core.Drain_Result;
      begin
         Core.Initialize (Parser);
         Core.Drain (Parser, Input, True, Events, Result);
         Check
           (Result.Stop = Core.Drain_Document_Complete, "underfull event buffer did not return completion");
         Check (Result.Consumed = 2, "underfull event buffer changed total consumption");
         Check (Result.Produced = 4, "underfull event buffer omitted document events");
         Check (Events (23).Kind = Core.Document_Begin, "underfull event order changed at begin");
         Check (Events (24).Kind = Core.Array_Begin, "underfull event order changed at array begin");
         Check (Events (25).Kind = Core.Array_End, "underfull event order changed at array end");
         Check (Events (26).Kind = Core.Document_End, "underfull event order changed at end");

         Core.Drain (Parser, Empty, True, Events, Result);
         Check (Result.Stop = Core.Drain_Call_Rejected, "completed drain call was not rejected");
         Check (Result.Consumed = 0, "rejected drain consumed input");
         Check (Result.Produced = 0, "rejected drain produced an event");
         Check (Result.Diagnostic.Code = Core.Invalid_State, "rejected drain diagnostic changed");
      end;

      declare
         Parser : Core.Parser (2, 8, 4);
         Prefix : constant Ada.Streams.Stream_Element_Array := To_Input ("[", -3);
         Suffix : constant Ada.Streams.Stream_Element_Array := To_Input ("]", 17);
         Events : Core.Event_Array (-5 .. 2);
         Result : Core.Drain_Result;
      begin
         Core.Initialize (Parser);
         Core.Drain (Parser, Prefix, False, Events, Result);
         Check (Result.Stop = Core.Drain_Need_Input, "batched prefix did not request input");
         Check (Result.Consumed = 1, "batched prefix did not consume its input");
         Check (Result.Produced = 2, "batched prefix omitted provisional events");

         Core.Drain (Parser, Suffix, True, Events, Result);
         Check (Result.Stop = Core.Drain_Document_Complete, "batched suffix did not complete");
         Check (Result.Consumed = 1, "batched suffix changed consumption");
         Check (Result.Produced = 2, "batched suffix omitted closing events");
      end;

      declare
         Parser : Core.Parser (2, 8, 4);
         Input  : constant Ada.Streams.Stream_Element_Array := To_Input ("[x", 5);
         Events : Core.Event_Array (0 .. 7);
         Result : Core.Drain_Result;
      begin
         Core.Initialize (Parser);
         Core.Drain (Parser, Input, True, Events, Result);
         Check (Result.Stop = Core.Drain_Parse_Failed, "batched malformed input did not fail");
         Check (Result.Consumed = 2, "batched malformed failure consumed the wrong count");
         Check (Result.Produced = 2, "batched malformed failure lost its provisional prefix");
         Check (Events (0).Kind = Core.Document_Begin, "malformed prefix lost document begin");
         Check (Events (1).Kind = Core.Array_Begin, "malformed prefix lost array begin");
         Check
           (Result.Diagnostic = (Code => Core.Unexpected_Token, Offset => 1),
            "batched malformed diagnostic changed");
      end;

      declare
         Text  : constant String := "{" & Quote & "ab" & Quote & ":0}";
         Input : constant Ada.Streams.Stream_Element_Array := To_Input (Text, -33);
      begin
         declare
            Parser : Core.Parser (4, 1, 1);
            Events : Core.Event_Array (9 .. 13);
            Result : Core.Drain_Result;
         begin
            Core.Initialize (Parser);
            Core.Drain (Parser, Input, False, Events, Result);
            Check (Result.Stop = Core.Drain_Buffer_Full, "pending failure did not fill exact buffer");
            Check (Result.Consumed = 4, "pending failure consumed beyond denied name scalar");
            Check (Result.Produced = 5, "pending failure changed provisional event count");
            Check (Events (13).Kind = Core.Name_Fragment, "pending failure lost raw fragment");
            Check
              (Events (13).Decoded_Kind = Core.No_Decoded_Fragment,
               "pending failure exposed denied decoded data");
            Check (Core.State (Parser) = Core.Failure_Pending, "full drain reported failure early");

            Core.Drain
              (Parser, Input (Input'First + Offset (Result.Consumed) .. Input'Last), True, Events, Result);
            Check (Result.Stop = Core.Drain_Parse_Failed, "pending failure was not reported");
            Check (Result.Consumed = 0, "pending failure consumed following input");
            Check (Result.Produced = 0, "pending failure returned a second event");
            Check
              (Result.Diagnostic = (Code => Core.Name_Storage_Exhausted, Offset => 1),
               "pending failure diagnostic changed");
         end;

         declare
            Parser : Core.Parser (4, 1, 1);
            Events : Core.Event_Array (-19 .. -12);
            Result : Core.Drain_Result;
         begin
            Core.Initialize (Parser);
            Core.Drain (Parser, Input, True, Events, Result);
            Check (Result.Stop = Core.Drain_Parse_Failed, "underfull drain hid pending failure");
            Check (Result.Consumed = 4, "underfull pending failure changed consumption");
            Check (Result.Produced = 5, "underfull pending failure lost provisional events");
            Check (Core.State (Parser) = Core.Failed, "underfull pending failure was not terminal");
            Check
              (Result.Diagnostic = (Code => Core.Name_Storage_Exhausted, Offset => 1),
               "underfull pending failure changed primary diagnostic");
         end;
      end;
   end Check_Drain_Boundaries;

   procedure Check_Buffered_Drain_Parity is
      type Capacity_Array is array (Positive range <>) of Positive;
      type Bound_Array is array (Positive range <>) of Offset;

      Capacities : constant Capacity_Array := [1, 2, 3, 4, 7];
      Bounds     : constant Bound_Array := [-23, 19];

      procedure Run_Schedule
        (Text                : String;
         Capacity            : Positive;
         Buffer_First        : Offset;
         Split               : Natural := 0;
         Randomized          : Boolean := False;
         Seed                : Interfaces.Unsigned_32 := 0;
         Maximum_Depth       : Natural := 8;
         Name_Octet_Capacity : Natural := Test_Name_Octet_Capacity;
         Name_Capacity       : Natural := Test_Name_Capacity)
      is
         Plain_Parser    : Core.Parser (Maximum_Depth, Name_Octet_Capacity, Name_Capacity);
         Buffered_Parser : Core.Parser (Maximum_Depth, Name_Octet_Capacity, Name_Capacity);
         Plain_Events    : Core.Event_Array (Buffer_First .. Buffer_First + Offset (Capacity) - 1);
         Buffered_Events :
           Core.Buffered_Event_Array (-Buffer_First .. -Buffer_First + Offset (Capacity) - 1);

         procedure Check_Chunk
           (Input       : Ada.Streams.Stream_Element_Array;
            Input_First : Core.Byte_Offset;
            Final_Input : Boolean;
            Stop        : out Core.Drain_Stop)
         is
            Used            : Count := 0;
            Plain_Result    : Core.Drain_Result;
            Buffered_Result : Core.Buffered_Drain_Result;
         begin
            loop
               declare
                  First       : constant Offset := Input'First + Offset (Used);
                  Exact_Input : Ada.Streams.Stream_Element_Array renames Input (First .. Input'Last);
                  Exact_First : constant Core.Byte_Offset := Input_First + Core.Byte_Offset (Used);
               begin
                  Core.Drain (Plain_Parser, Exact_Input, Final_Input, Plain_Events, Plain_Result);
                  Core.Buffered_Drain
                    (Buffered_Parser, Exact_Input, Final_Input, Buffered_Events, Buffered_Result);

                  Check
                    (Buffered_Result.Input_First = Exact_First,
                     "buffered drain lost its exact input origin");
                  Check (Buffered_Result.Stop = Plain_Result.Stop, "buffered drain stop changed");
                  Check
                    (Buffered_Result.Consumed = Plain_Result.Consumed,
                     "buffered drain consumed count changed");
                  Check
                    (Buffered_Result.Produced = Plain_Result.Produced,
                     "buffered drain produced count changed");
                  Check
                    (Buffered_Result.Diagnostic = Plain_Result.Diagnostic,
                     "buffered drain diagnostic changed");
                  Check
                    (Core.State (Buffered_Parser) = Core.State (Plain_Parser),
                     "buffered drain parser state changed");

                  if Plain_Result.Produced > 0 then
                     for Position in Count range 0 .. Plain_Result.Produced - 1 loop
                        declare
                           Plain_Item : Core.Event renames
                             Plain_Events (Plain_Events'First + Offset (Position));
                           Buffered_Item : Core.Buffered_Event renames
                             Buffered_Events (Buffered_Events'First + Offset (Position));
                        begin
                           Check_Buffered_Event
                             (Buffered_Item,
                              Plain_Item,
                              Buffered_Result.Input_First,
                              Exact_Input'Length);
                        end;
                     end loop;
                  end if;
               end;

               Used := Used + Plain_Result.Consumed;
               Stop := Plain_Result.Stop;
               exit when Stop /= Core.Drain_Buffer_Full;
            end loop;
         end Check_Chunk;

         Stop : Core.Drain_Stop := Core.Drain_Need_Input;
      begin
         Core.Initialize (Plain_Parser);
         Core.Initialize (Buffered_Parser);

         if Randomized then
            declare
               Generator : Interfaces.Unsigned_32 := Seed;
               Position  : Natural := 0;
            begin
               while Position < Text'Length loop
                  Generator := Generator * 1_664_525 + 1_013_904_223;
                  if (Generator and 3) = 0 then
                     declare
                        Empty : constant Ada.Streams.Stream_Element_Array :=
                          To_Input ("", Offset (-41 + Position));
                     begin
                        Check_Chunk (Empty, Core.Byte_Offset (Position), False, Stop);
                        exit when Stop /= Core.Drain_Need_Input;
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
                     Check_Chunk
                       (Chunk,
                        Core.Byte_Offset (Position),
                        Position + Length = Text'Length,
                        Stop);
                     Position := Position + Length;
                     exit when Stop /= Core.Drain_Need_Input;
                  end;
               end loop;
            end;
         else
            if Split > 0 then
               declare
                  Prefix : constant Ada.Streams.Stream_Element_Array :=
                    To_Input (Text (Text'First .. Text'First + Split - 1), -37);
               begin
                  Check_Chunk (Prefix, 0, False, Stop);
               end;
            end if;

            if Split = 0 or else Stop = Core.Drain_Need_Input then
               declare
                  Suffix : constant Ada.Streams.Stream_Element_Array :=
                    To_Input (Text (Text'First + Split .. Text'Last), 43);
               begin
                  Check_Chunk (Suffix, Core.Byte_Offset (Split), True, Stop);
               end;
            end if;
         end if;
      end Run_Schedule;

      procedure Check_Text
        (Text                : String;
         Maximum_Depth       : Natural := 8;
         Name_Octet_Capacity : Natural := Test_Name_Octet_Capacity;
         Name_Capacity       : Natural := Test_Name_Capacity)
      is
      begin
         for Capacity of Capacities loop
            for Buffer_First of Bounds loop
               for Split in 0 .. Text'Length loop
                  Run_Schedule
                    (Text,
                     Capacity,
                     Buffer_First,
                     Split,
                     Maximum_Depth       => Maximum_Depth,
                     Name_Octet_Capacity => Name_Octet_Capacity,
                     Name_Capacity       => Name_Capacity);
               end loop;

               for Seed in Interfaces.Unsigned_32 range 1 .. 8 loop
                  Run_Schedule
                    (Text,
                     Capacity,
                     Buffer_First,
                     Randomized          => True,
                     Seed                => Seed,
                     Maximum_Depth       => Maximum_Depth,
                     Name_Octet_Capacity => Name_Octet_Capacity,
                     Name_Capacity       => Name_Capacity);
               end loop;
            end loop;
         end loop;
      end Check_Text;
   begin
      Check
        (Core.Buffered_Event'Size = 24 * System.Storage_Unit,
         "buffered event descriptor no longer occupies 24 octets");
      Check
        (Core.Buffered_Event_Array'Component_Size = 24 * System.Storage_Unit,
         "buffered event array stride no longer occupies 24 octets");
      Check_Text ("null");
      Check_Text ("[null,true,false,0,-12.3e+4]");
      Check_Text ("[null,true,fa");
      Check_Text ("[null,0");
      Check_Text ("[null,00]");
      Check_Text ("[null,0x]");
      Check_Text ("[null,0}");
      Check_Text ("[null,0 ]");
      Check_Text
        (Quote
         & "a"
         & Character'Val (16#E2#)
         & Character'Val (16#82#)
         & Character'Val (16#AC#)
         & Reverse_Solidus
         & "n"
         & Reverse_Solidus
         & "uD83D"
         & Reverse_Solidus
         & "uDE00"
         & Quote);
      Check_Text
        ("{" & Quote & "a" & Quote & ":[0," & Quote & Reverse_Solidus & "u20AC" & Quote & "]}");
      Check_Text ("truex");
      Check_Text ("[0,]");
      Check_Text ("[[[0]]]", Maximum_Depth => 2);
      Check_Text
        ("{" & Quote & "a" & Quote & ":0," & Quote & Reverse_Solidus & "u0061" & Quote & ":1}");
      Check_Text
        ("{" & Quote & "ab" & Quote & ":0}", Name_Octet_Capacity => 1, Name_Capacity => 1);
      Check_Text (Quote & "a" & Reverse_Solidus & "x" & Quote);
      Check_Text (Quote & Character'Val (16#E2#) & Character'Val (16#82#));
      Check_Text (Quote & Reverse_Solidus & "uD800" & Reverse_Solidus & "u0041" & Quote);
      Check_Text (Quote & Reverse_Solidus & "uD800" & Quote);

      declare
         Plain_Parser    : Core.Parser (2, 8, 4);
         Buffered_Parser : Core.Parser (2, 8, 4);
         Input           : constant Ada.Streams.Stream_Element_Array := To_Input ("[]", -11);
         Plain_Events    : Core.Event_Array (9 .. 8);
         Buffered_Events : Core.Buffered_Event_Array (-7 .. -8);
         Plain_Result    : Core.Drain_Result;
         Buffered_Result : Core.Buffered_Drain_Result;
      begin
         Core.Initialize (Plain_Parser);
         Core.Initialize (Buffered_Parser);
         Core.Drain (Plain_Parser, Input, True, Plain_Events, Plain_Result);
         Core.Buffered_Drain (Buffered_Parser, Input, True, Buffered_Events, Buffered_Result);
         Check (Buffered_Result.Stop = Plain_Result.Stop, "null buffered stop changed");
         Check (Buffered_Result.Consumed = 0, "null buffered drain consumed input");
         Check (Buffered_Result.Produced = 0, "null buffered drain produced an event");
         Check (Core.State (Buffered_Parser) = Core.Ready, "null buffered drain changed state");
      end;
   end Check_Buffered_Drain_Parity;

begin
   Check_Drain_Parity;
   Check_Drain_Boundaries;
   Check_Buffered_Drain_Parity;
   Check_Valid_Splits ("null");
   Check_Valid_Splits ("true");
   Check_Valid_Splits ("false");
   Check_Valid_Splits ("[ null , true , false ]", Expected_Arrays => 1);
   Check_Valid_Splits ("{" & Quote & "x" & Quote & ":false}", Expected_Objects => 1);
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
     ("[null,true,false,0]", Expected_Number_Octets => 1, Expected_Number_Text => "0", Expected_Arrays => 1);
   Check_Valid_Splits ("[[],{}]", Expected_Arrays => 2, Expected_Objects => 1);
   Check_Valid_Splits
     ("{"
      & Quote
      & Quote
      & ":0,"
      & Quote
      & Reverse_Solidus
      & "u0000"
      & Quote
      & ":1,"
      & Quote
      & "a"
      & Quote
      & ":2,"
      & Quote
      & "a"
      & Reverse_Solidus
      & "u0000"
      & Quote
      & ":3,"
      & Quote
      & "ab"
      & Quote
      & ":4,"
      & Quote
      & "abc"
      & Quote
      & ":5}",
      Expected_Number_Octets => 6,
      Expected_Number_Text   => "012345",
      Expected_Objects       => 1);
   Check_Valid_Splits
     ("{"
      & Quote
      & "x"
      & Quote
      & ":{"
      & Quote
      & "a"
      & Quote
      & ":0},"
      & Quote
      & "y"
      & Quote
      & ":{"
      & Quote
      & "a"
      & Quote
      & ":1}}",
      Expected_Number_Octets => 2,
      Expected_Number_Text   => "01",
      Expected_Objects       => 3);
   Check_Valid_Text_Splits
     ("{"
      & Quote
      & Reverse_Solidus
      & "u00E9"
      & Quote
      & ":0,"
      & Quote
      & "e"
      & Reverse_Solidus
      & "u0301"
      & Quote
      & ":1}",
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
   Check_Valid_Text_Splits (Quote & Reverse_Solidus & "u20AC" & Quote, Expected_String => Euro);
   Check_Valid_Text_Splits
     (Quote & Reverse_Solidus & "uD83D" & Reverse_Solidus & "uDE00" & Quote,
      Expected_String => Grinning_Face);
   Check_Valid_Text_Splits
     (Quote & Reverse_Solidus & "uD800" & Reverse_Solidus & "uDC00" & Quote,
      Expected_String => First_Supplementary);
   Check_Valid_Text_Splits
     (Quote & Reverse_Solidus & "uDBFF" & Reverse_Solidus & "uDFFF" & Quote, Expected_String => Last_Scalar);
   Check_Valid_Text_Splits
     ("{"
      & Quote
      & "a"
      & Quote
      & ":"
      & Quote
      & "b"
      & Quote
      & ","
      & Quote
      & Reverse_Solidus
      & "u20AC"
      & Quote
      & ":"
      & Quote
      & Euro
      & Quote
      & "}",
      Expected_Name    => "a" & Euro,
      Expected_String  => "b" & Euro,
      Expected_Names   => 2,
      Expected_Strings => 2);

   Check_All_Partitions (Quote & Quote, "");
   Check_All_Partitions (Quote & "a" & Quote, "a");
   Check_All_Partitions (Quote & Reverse_Solidus & "n" & Quote, String'(1 => ASCII.LF));
   Check_All_Partitions ("null", "");
   Check_All_Partitions ("true", "");
   Check_All_Partitions ("false", "");
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
      Check (Split_UTF8.Fragments (Inline).Decoded_Length = 3, "split UTF-8 decoded length is wrong");
      Check
        (Split_UTF8.String_Text (1 .. Split_UTF8.String_Length) = Euro, "split UTF-8 decoded bytes changed");
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
      Escaped : constant Observation := Parse (Quote & Reverse_Solidus & "u20AC" & Quote, 0);
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

   Check_Invalid_Literal ("truex", Core.Invalid_Literal, 4);
   Check_Invalid_Literal ("nxll", Core.Invalid_Literal, 1);
   Check_Invalid_Literal ("nuxl", Core.Invalid_Literal, 2);
   Check_Invalid_Literal ("nulx", Core.Invalid_Literal, 3);
   Check_Invalid_Literal ("nullx", Core.Invalid_Literal, 4);
   Check_Invalid_Literal ("txue", Core.Invalid_Literal, 1);
   Check_Invalid_Literal ("trxe", Core.Invalid_Literal, 2);
   Check_Invalid_Literal ("trux", Core.Invalid_Literal, 3);
   Check_Invalid_Literal ("fxlse", Core.Invalid_Literal, 1);
   Check_Invalid_Literal ("faxse", Core.Invalid_Literal, 2);
   Check_Invalid_Literal ("falxe", Core.Invalid_Literal, 3);
   Check_Invalid_Literal ("falsx", Core.Invalid_Literal, 4);
   Check_Invalid_Literal ("n", Core.Truncated_Input, 1);
   Check_Invalid_Literal ("nu", Core.Truncated_Input, 2);
   Check_Invalid_Literal ("nul", Core.Truncated_Input, 3);
   Check_Invalid_Literal ("t", Core.Truncated_Input, 1);
   Check_Invalid_Literal ("tr", Core.Truncated_Input, 2);
   Check_Invalid_Literal ("tru", Core.Truncated_Input, 3);
   Check_Invalid_Literal ("f", Core.Truncated_Input, 1);
   Check_Invalid_Literal ("fa", Core.Truncated_Input, 2);
   Check_Invalid_Literal ("fal", Core.Truncated_Input, 3);
   Check_Invalid_Literal ("fals", Core.Truncated_Input, 4);
   Check_Invalid ("01", Core.Invalid_Number, 1);
   Check_Invalid ("[0,]", Core.Unexpected_Token, 3);
   Check_Invalid ("1.", Core.Truncated_Input, 2);
   Check_Literal_Transport;

   Check_Duplicate ("{" & Quote & "a" & Quote & ":0," & Quote & "a" & Quote & ":1}", 7);
   Check_Duplicate ("{" & Quote & "a" & Quote & ":0," & Quote & Reverse_Solidus & "u0061" & Quote & ":1}", 7);
   Check_Duplicate
     ("{" & Quote & Reverse_Solidus & "u20AC" & Quote & ":0," & Quote & Euro & Quote & ":1}", 12);
   Check_Duplicate
     ("{" & Quote & Reverse_Solidus & "u00E9" & Quote & ":0," & Quote & E_Acute & Quote & ":1}", 12);
   Check_Duplicate
     ("{"
      & Quote
      & Reverse_Solidus
      & "uD83D"
      & Reverse_Solidus
      & "uDE00"
      & Quote
      & ":0,"
      & Quote
      & Grinning_Face
      & Quote
      & ":1}",
      18);
   Check_Duplicate ("{" & Quote & Reverse_Solidus & "/" & Quote & ":0," & Quote & "/" & Quote & ":1}", 8);
   Check_Duplicate
     ("{" & Quote & "a" & Quote & ":{" & Quote & "a" & Quote & ":0}," & Quote & "a" & Quote & ":1}",
      13,
      Expected_Name_Begins => 3,
      Expected_Name_Ends   => 2);

   Check_Duplicate_Capacities;

   Check_Malformed_Prefix_Invariance ("12x", Core.Invalid_Number, 2, Expected_Raw => "12");
   Check_Malformed_Prefix_Invariance ("[1.]", Core.Invalid_Number, 3, Expected_Raw => "1.");

   Check_Invalid (Quote & "a" & Character'Val (16#01#) & "b" & Quote, Core.Raw_Control_Character, 2);
   Check_Invalid (Quote & Character'Val (16#C2#) & ' ' & Quote, Core.Invalid_UTF8, 2);
   Check_Malformed_Prefix_Invariance
     (Quote & "a" & Character'Val (16#C2#) & ' ' & Quote,
      Core.Invalid_UTF8,
      3,
      Expected_Raw     => "a" & Character'Val (16#C2#),
      Expected_Decoded => "a");
   Check_Malformed_Prefix_Invariance
     (Quote & "a" & Character'Val (16#E2#) & Character'Val (16#82#) & ' ' & Quote,
      Core.Invalid_UTF8,
      4,
      Expected_Raw     => "a" & Character'Val (16#E2#) & Character'Val (16#82#),
      Expected_Decoded => "a");
   Check_Invalid (Quote & Character'Val (16#C0#) & Character'Val (16#AF#) & Quote, Core.Invalid_UTF8, 1);
   Check_Invalid
     (Quote & Character'Val (16#E0#) & Character'Val (16#80#) & Character'Val (16#80#) & Quote,
      Core.Invalid_UTF8,
      1);
   Check_Invalid
     (Quote & Character'Val (16#ED#) & Character'Val (16#A0#) & Character'Val (16#80#) & Quote,
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
   Check_Invalid (Quote & Character'Val (16#80#) & Quote, Core.Invalid_UTF8, 1);
   Check_Invalid (Quote & Reverse_Solidus & "x" & Quote, Core.Invalid_Escape, 2);
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
   Check_Invalid (Quote & Reverse_Solidus & "u12G4" & Quote, Core.Invalid_Escape, 5);
   Check_Malformed_Prefix_Invariance
     (Quote & "a" & Reverse_Solidus & "u12G4" & Quote,
      Core.Invalid_Escape,
      6,
      Expected_Raw     => "a" & Reverse_Solidus & "u12",
      Expected_Decoded => "a");
   Check_Invalid (Quote & Reverse_Solidus & "uG000" & Quote, Core.Invalid_Escape, 3);
   Check_Invalid (Quote & Reverse_Solidus & "u0G00" & Quote, Core.Invalid_Escape, 4);
   Check_Invalid (Quote & Reverse_Solidus & "u000G" & Quote, Core.Invalid_Escape, 6);
   Check_Invalid (Quote & Reverse_Solidus & "uDC00" & Quote, Core.Invalid_Surrogate, 1);
   Check_Malformed_Prefix_Invariance
     (Quote & Reverse_Solidus & "uDC00" & Quote,
      Core.Invalid_Surrogate,
      1,
      Expected_Raw => Reverse_Solidus & "uDC0");
   Check_Invalid (Quote & Reverse_Solidus & "uDFFF" & Quote, Core.Invalid_Surrogate, 1);
   Check_Invalid (Quote & Reverse_Solidus & "uD800x" & Quote, Core.Invalid_Surrogate, 1);
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
     (Quote & Reverse_Solidus & "uD800" & Reverse_Solidus & "u0041" & Quote, Core.Invalid_Surrogate, 1);
   Check_Malformed_Prefix_Invariance
     (Quote & Reverse_Solidus & "uD800" & Reverse_Solidus & "u0041" & Quote,
      Core.Invalid_Surrogate,
      1,
      Expected_Raw => Reverse_Solidus & "uD800" & Reverse_Solidus & "u004");
   Check_Invalid
     (Quote & Reverse_Solidus & "uD800" & Reverse_Solidus & "uDBFF" & Quote, Core.Invalid_Surrogate, 1);
   Check_Invalid (Quote & Reverse_Solidus & "uD800" & Quote, Core.Invalid_Surrogate, 1);
   Check_Invalid ("{" & Quote & Reverse_Solidus & "uDC00" & Quote & ":null}", Core.Invalid_Surrogate, 2);

   Check_Truncated_Prefixes (Quote & "ascii" & Quote);
   Check_Truncated_Prefixes (Quote & Euro & Quote);
   Check_Truncated_Prefixes ("{" & Quote & "a" & Quote & ":" & Quote & "b" & Quote & "}");
   Check_Truncated_Prefixes (Quote & Reverse_Solidus & "uD83D" & Reverse_Solidus & "uDE00" & Quote);

   --  A final call publishes every newly consumed raw-only span before the
   --  following empty final call latches truncation.  The aggregate provisional
   --  prefix must therefore be independent of chunk scheduling.
   Check_Truncated_Raw_Prefix (Quote & "a" & Character'Val (16#E2#), "a" & Character'Val (16#E2#), "a");
   Check_Truncated_Raw_Prefix
     (Quote & Character'Val (16#E2#) & Character'Val (16#82#),
      Character'Val (16#E2#) & Character'Val (16#82#));
   Check_Truncated_Raw_Prefix (Quote & Character'Val (16#C2#), String'(1 => Character'Val (16#C2#)));
   Check_Truncated_Raw_Prefix (Quote & Character'Val (16#F0#), String'(1 => Character'Val (16#F0#)));
   Check_Truncated_Raw_Prefix
     (Quote & Character'Val (16#F0#) & Character'Val (16#90#),
      Character'Val (16#F0#) & Character'Val (16#90#));
   Check_Truncated_Raw_Prefix
     (Quote & Character'Val (16#F0#) & Character'Val (16#90#) & Character'Val (16#80#),
      Character'Val (16#F0#) & Character'Val (16#90#) & Character'Val (16#80#));
   Check_Truncated_Raw_Prefix (Quote & "a" & Reverse_Solidus, "a" & Reverse_Solidus, "a");
   Check_Truncated_Raw_Prefix (Quote & Reverse_Solidus & "u", Reverse_Solidus & "u");
   Check_Truncated_Raw_Prefix (Quote & Reverse_Solidus & "u0", Reverse_Solidus & "u0");
   Check_Truncated_Raw_Prefix (Quote & Reverse_Solidus & "u00", Reverse_Solidus & "u00");
   Check_Truncated_Raw_Prefix (Quote & Reverse_Solidus & "u000", Reverse_Solidus & "u000");
   Check_Truncated_Raw_Prefix (Quote & Reverse_Solidus & "uD800", Reverse_Solidus & "uD800");
   Check_Truncated_Raw_Prefix
     (Quote & Reverse_Solidus & "uD800" & Reverse_Solidus, Reverse_Solidus & "uD800" & Reverse_Solidus);
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
      Check_Valid_Text_Splits (Quote & Long_Text & Quote, Expected_String => Long_Text);
      Check_Valid_Splits
        (Long_Number,
         Expected_Number_Octets => Count (Long_Number'Length),
         Expected_Number_Text   => Long_Number);
   end;

   Check_Lifecycle;
end Flyology_JSON.Parser_Core_Tests;
