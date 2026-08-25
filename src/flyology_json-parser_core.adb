package body Flyology_JSON.Parser_Core is

   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Count;
   use type Byte_Offset;
   use type Parser_Numbers.Transition_Result;
   use type Parser_Duplicates.Name_Classification;
   use type Parser_Duplicates.Operation_Status;
   use type Parser_UTF8.Blame_Position;
   use type Parser_UTF8.Feed_Status;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;

   subtype Octet is Ada.Streams.Stream_Element;
   subtype Count is Ada.Streams.Stream_Element_Count;

   Quote           : constant Octet := Character'Pos ('"');
   Minus           : constant Octet := Character'Pos ('-');
   Plus            : constant Octet := Character'Pos ('+');
   Decimal         : constant Octet := Character'Pos ('.');
   Lower_E         : constant Octet := Character'Pos ('e');
   Upper_E         : constant Octet := Character'Pos ('E');
   Zero            : constant Octet := Character'Pos ('0');
   Nine            : constant Octet := Character'Pos ('9');
   Left_Brace      : constant Octet := Character'Pos ('{');
   Right_Brace     : constant Octet := Character'Pos ('}');
   Left_Bracket    : constant Octet := Character'Pos ('[');
   Right_Bracket   : constant Octet := Character'Pos (']');
   Comma           : constant Octet := Character'Pos (',');
   Colon           : constant Octet := Character'Pos (':');
   Reverse_Solidus : constant Octet := Character'Pos ('\');

   Empty_Diagnostic : constant Diagnostic := (Code => No_Error, Offset => 0);

   Empty_Buffered_Event : constant Buffered_Event :=
     (Kind          => Document_Begin,
      Metadata      => 0,
      Scalar_Octets => [others => 0],
      Source        => (First => 0, Octet_Length => 0));

   Has_Raw_Bit           : constant Interfaces.Unsigned_16 := 2#0000_0000_0000_0001#;
   Decoded_Kind_Factor   : constant Interfaces.Unsigned_16 := 2#0000_0000_0000_0010#;
   Boolean_Bit           : constant Interfaces.Unsigned_16 := 2#0000_0000_0000_1000#;
   Scalar_Length_Factor  : constant Interfaces.Unsigned_16 := 2#0000_0000_0001_0000#;
   Decoded_Length_Factor : constant Interfaces.Unsigned_16 := 2#0000_0000_1000_0000#;

   type Engine_Result is record
      Outcome    : Next_Outcome;
      Consumed   : Count;
      Item       : Buffered_Event;
      Diagnostic : Parser_Core.Diagnostic;
   end record;

   function Is_Whitespace (Value : Octet) return Boolean
   is (Value = Character'Pos (' ')
       or else Value = Character'Pos (ASCII.HT)
       or else Value = Character'Pos (ASCII.LF)
       or else Value = Character'Pos (ASCII.CR));

   function Is_Number_Octet (Value : Octet) return Boolean
   is (Value in Zero .. Nine
       or else Value = Minus
       or else Value = Plus
       or else Value = Decimal
       or else Value = Lower_E
       or else Value = Upper_E);

   function Is_Token_Delimiter (Value : Octet) return Boolean
   is (Is_Whitespace (Value) or else Value = Comma or else Value = Right_Brace or else Value = Right_Bracket);

   function Input_Octet (Input : Ada.Streams.Stream_Element_Array; Position : Count) return Octet
   is (Input (Input'First + Ada.Streams.Stream_Element_Offset (Position)));

   procedure Clear_Result (Result : out Engine_Result) is
   begin
      Result :=
        (Outcome => Need_Input, Consumed => 0, Item => Empty_Buffered_Event, Diagnostic => Empty_Diagnostic);
   end Clear_Result;

   procedure Set_Event
     (Result         : in out Engine_Result;
      Kind           : Event_Kind;
      First          : Byte_Offset;
      Length         : Byte_Offset;
      Has_Raw_Slice  : Boolean := False;
      Raw_First      : Count := 0;
      Raw_Length     : Count := 0;
      Decoded_Kind   : Decoded_Fragment_Kind := No_Decoded_Fragment;
      Decoded_First  : Byte_Offset := 0;
      Decoded_Length : Byte_Offset := 0;
      Decoded        : Inline_Scalar := (Length => 0, Octets => [others => 0]);
      Boolean_Data   : Boolean := False)
   is
      Metadata : Interfaces.Unsigned_16 :=
        (if Has_Raw_Slice then Has_Raw_Bit else 0)
        + Interfaces.Unsigned_16 (Decoded_Fragment_Kind'Pos (Decoded_Kind)) * Decoded_Kind_Factor
        + (if Kind = Boolean_Value and then Boolean_Data then Boolean_Bit else 0);
   begin
      Result.Outcome := Event_Ready;
      pragma Unreferenced (Raw_First, Raw_Length, Decoded_First);
      if Decoded_Kind = Decoded_Inline_Scalar then
         Metadata :=
           Metadata
           + Interfaces.Unsigned_16 (Decoded.Length) * Scalar_Length_Factor
           + Interfaces.Unsigned_16 (Decoded_Length) * Decoded_Length_Factor;
      end if;
      Result.Item.Kind := Kind;
      Result.Item.Metadata := Metadata;
      Result.Item.Source := (First => First, Octet_Length => Length);
      if Decoded_Kind = Decoded_Inline_Scalar then
         Result.Item.Scalar_Octets := Decoded.Octets;
      end if;
      Result.Diagnostic := Empty_Diagnostic;
   end Set_Event;

   procedure Fail
     (Self : in out Parser; Result : in out Engine_Result; Code : Error_Code; Offset : Byte_Offset) is
   begin
      Self.Current_State := Failed;
      Self.Last_Diagnostic := (Code => Code, Offset => Offset);
      Result.Outcome := Parse_Failed;
      Result.Item := Empty_Buffered_Event;
      Result.Diagnostic := Self.Last_Diagnostic;
   end Fail;

   procedure Retain_Name_Octets
     (Self : in out Parser; Octets : Ada.Streams.Stream_Element_Array; Code : out Error_Code)
   is
      Status : Parser_Duplicates.Operation_Status;
   begin
      Parser_Duplicates.Append_Octets (Self.Duplicate_Names, Octets, Status);
      Code :=
        (case Status is
           when Parser_Duplicates.Operation_Succeeded     => No_Error,
           when Parser_Duplicates.Name_Storage_Exhausted  => Name_Storage_Exhausted,
           when Parser_Duplicates.Index_Storage_Exhausted => Duplicate_Index_Exhausted,
           when Parser_Duplicates.Invalid_Operation_Order => Invalid_State);
   end Retain_Name_Octets;

   procedure Retain_Name_Scalar (Self : in out Parser; Scalar : Inline_Scalar; Code : out Error_Code) is
      Octets : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Scalar.Length));
   begin
      for Position in 1 .. Scalar.Length loop
         Octets (Ada.Streams.Stream_Element_Offset (Position)) := Scalar.Octets (Position);
      end loop;
      Retain_Name_Octets (Self, Octets, Code);
   end Retain_Name_Scalar;

   procedure Defer_Failure (Self : in out Parser; Code : Error_Code; Offset : Byte_Offset) is
   begin
      Self.Current_State := Failure_Pending;
      Self.Last_Diagnostic := (Code => Code, Offset => Offset);
   end Defer_Failure;

   function Consume_One
     (Self : in out Parser; Consumed : in out Count; Result : in out Engine_Result) return Boolean is
   begin
      if Self.Next_Offset = Byte_Offset'Last then
         Fail (Self, Result, Offset_Exhausted, Self.Next_Offset);
         return False;
      end if;

      Consumed := Consumed + 1;
      Self.Next_Offset := Self.Next_Offset + 1;
      Result.Consumed := Consumed;
      return True;
   end Consume_One;

   function Literal_Length (Token : Token_Kind) return Natural
   is (case Token is
         when Null_Token | True_Token => 4,
         when False_Token             => 5,
         when others                  => 0);

   function Literal_Octet (Token : Token_Kind; Position : Positive) return Octet is
      Null_Text  : constant String := "null";
      True_Text  : constant String := "true";
      False_Text : constant String := "false";
   begin
      return
        (case Token is
           when Null_Token  => Character'Pos (Null_Text (Position)),
           when True_Token  => Character'Pos (True_Text (Position)),
           when False_Token => Character'Pos (False_Text (Position)),
           when others      => 0);
   end Literal_Octet;

   procedure Complete_Value (Self : in out Parser) is
   begin
      if Self.Depth = 0 then
         Self.Root_Complete := True;
      else
         case Self.Stack (Self.Depth).Phase is
            when Array_First_Or_End | Array_Value =>
               Self.Stack (Self.Depth).Phase := Array_Comma_Or_End;

            when Object_Value                     =>
               Self.Stack (Self.Depth).Phase := Object_Comma_Or_End;

            when others                           =>
               null;
         end case;
      end if;
   end Complete_Value;

   procedure Start_Container_Value (Self : in out Parser) is
   begin
      if Self.Depth = 0 then
         Self.Root_Started := True;
      else
         case Self.Stack (Self.Depth).Phase is
            when Array_First_Or_End | Array_Value =>
               Self.Stack (Self.Depth).Phase := Array_Comma_Or_End;

            when Object_Value                     =>
               Self.Stack (Self.Depth).Phase := Object_Comma_Or_End;

            when others                           =>
               null;
         end case;
      end if;
   end Start_Container_Value;

   procedure Begin_Scalar_Value (Self : in out Parser) is
   begin
      if Self.Depth = 0 then
         Self.Root_Started := True;
      end if;
   end Begin_Scalar_Value;

   function Value_Is_Expected (Self : Parser) return Boolean is
   begin
      if Self.Depth = 0 then
         return not Self.Root_Started;
      end if;

      return Self.Stack (Self.Depth).Phase in Array_First_Or_End | Array_Value | Object_Value;
   end Value_Is_Expected;

   procedure Start_Literal (Self : in out Parser; Token : Token_Kind; First_Count : Count) is
   begin
      Begin_Scalar_Value (Self);
      Self.Token := Token;
      Self.Token_Start := Self.Next_Offset;
      Self.Literal_Position := 0;
      Self.Literal_Can_Slice := True;
      Self.Literal_First_Count := First_Count;
   end Start_Literal;

   procedure Emit_Literal (Self : in out Parser; Result : in out Engine_Result) is
      Token  : constant Token_Kind := Self.Token;
      Length : constant Natural := Literal_Length (Token);
   begin
      Self.Token := No_Token;
      Complete_Value (Self);

      if Token = Null_Token then
         Set_Event
           (Result,
            Null_Value,
            Self.Token_Start,
            Byte_Offset (Length),
            Self.Literal_Can_Slice,
            Self.Literal_First_Count,
            Count (Length));
      else
         Set_Event
           (Result,
            Boolean_Value,
            Self.Token_Start,
            Byte_Offset (Length),
            Self.Literal_Can_Slice,
            Self.Literal_First_Count,
            Count (Length),
            Boolean_Data => Token = True_Token);
      end if;
   end Emit_Literal;

   pragma Inline_Always (Emit_Literal);

   function Hex_Digit (Value : Octet; Digit : out Interfaces.Unsigned_32) return Boolean is
   begin
      if Value in Character'Pos ('0') .. Character'Pos ('9') then
         Digit := Interfaces.Unsigned_32 (Value - Character'Pos ('0'));
      elsif Value in Character'Pos ('A') .. Character'Pos ('F') then
         Digit := Interfaces.Unsigned_32 (Value - Character'Pos ('A') + 10);
      elsif Value in Character'Pos ('a') .. Character'Pos ('f') then
         Digit := Interfaces.Unsigned_32 (Value - Character'Pos ('a') + 10);
      else
         Digit := 0;
         return False;
      end if;

      return True;
   end Hex_Digit;

   function Encode_UTF8 (Code_Point : Interfaces.Unsigned_32) return Inline_Scalar is
      Result : Inline_Scalar := (Length => 0, Octets => [others => 0]);
   begin
      if Code_Point <= 16#7F# then
         Result.Length := 1;
         Result.Octets (1) := Octet (Code_Point);
      elsif Code_Point <= 16#7FF# then
         Result.Length := 2;
         Result.Octets (1) := 16#C0# or Octet (Code_Point / 2**6);
         Result.Octets (2) := 16#80# or Octet (Code_Point and 16#3F#);
      elsif Code_Point <= 16#FFFF# then
         Result.Length := 3;
         Result.Octets (1) := 16#E0# or Octet (Code_Point / 2**12);
         Result.Octets (2) := 16#80# or Octet ((Code_Point / 2**6) and 16#3F#);
         Result.Octets (3) := 16#80# or Octet (Code_Point and 16#3F#);
      else
         Result.Length := 4;
         Result.Octets (1) := 16#F0# or Octet (Code_Point / 2**18);
         Result.Octets (2) := 16#80# or Octet ((Code_Point / 2**12) and 16#3F#);
         Result.Octets (3) := 16#80# or Octet ((Code_Point / 2**6) and 16#3F#);
         Result.Octets (4) := 16#80# or Octet (Code_Point and 16#3F#);
      end if;

      return Result;
   end Encode_UTF8;

   function Text_Fragment_Kind (Self : Parser) return Event_Kind
   is (if Self.Token = Name_Token then Name_Fragment else String_Fragment);

   procedure Emit_Inline_Text
     (Self             : Parser;
      Result           : in out Engine_Result;
      Raw_First        : Byte_Offset;
      Raw_Length       : Byte_Offset;
      Raw_First_Count  : Count;
      Raw_Count_Length : Count;
      Decoded_First    : Byte_Offset;
      Decoded_Length   : Byte_Offset;
      Scalar           : Inline_Scalar) is
   begin
      Set_Event
        (Result,
         Text_Fragment_Kind (Self),
         Raw_First,
         Raw_Length,
         Has_Raw_Slice  => True,
         Raw_First      => Raw_First_Count,
         Raw_Length     => Raw_Count_Length,
         Decoded_Kind   => Decoded_Inline_Scalar,
         Decoded_First  => Decoded_First,
         Decoded_Length => Decoded_Length,
         Decoded        => Scalar);
   end Emit_Inline_Text;

   procedure Emit_Raw_Only_Text
     (Self         : Parser;
      Result       : in out Engine_Result;
      First        : Byte_Offset;
      Length       : Byte_Offset;
      First_Count  : Count;
      Count_Length : Count) is
   begin
      Set_Event
        (Result,
         Text_Fragment_Kind (Self),
         First,
         Length,
         Has_Raw_Slice => True,
         Raw_First     => First_Count,
         Raw_Length    => Count_Length);
   end Emit_Raw_Only_Text;

   procedure Emit_Raw_Text
     (Self         : Parser;
      Result       : in out Engine_Result;
      First        : Byte_Offset;
      Length       : Byte_Offset;
      First_Count  : Count;
      Count_Length : Count) is
   begin
      Set_Event
        (Result,
         Text_Fragment_Kind (Self),
         First,
         Length,
         Has_Raw_Slice  => True,
         Raw_First      => First_Count,
         Raw_Length     => Count_Length,
         Decoded_Kind   => Decoded_Is_Raw_Range,
         Decoded_First  => First,
         Decoded_Length => Length);
   end Emit_Raw_Text;

   procedure Start_Text
     (Self : in out Parser; Token : Token_Kind; Result : in out Engine_Result; Consumed : in out Count)
   is
      Start  : constant Byte_Offset := Self.Next_Offset;
      Status : Parser_Duplicates.Operation_Status;
   begin
      if Token = String_Token then
         Begin_Scalar_Value (Self);
      else
         Parser_Duplicates.Begin_Name
           (Self.Duplicate_Names, Self.Stack (Self.Depth).Duplicate_Context, Status);
         if Status /= Parser_Duplicates.Operation_Succeeded then
            Fail
              (Self,
               Result,
               (if Status = Parser_Duplicates.Index_Storage_Exhausted
                then Duplicate_Index_Exhausted
                else Invalid_State),
               Start);
            return;
         end if;
      end if;

      if not Consume_One (Self, Consumed, Result) then
         return;
      end if;

      Self.Token := Token;
      Self.Token_Start := Start;
      Self.Text_State := Text_Content;
      Self.Text_Hex_Value := 0;
      Self.Text_Hex_Digits := 0;
      Self.Text_High_Surrogate := 0;
      Parser_UTF8.Reset (Self.UTF8);
      Set_Event
        (Result,
         (if Token = Name_Token then Name_Begin else String_Begin),
         Start,
         1,
         Has_Raw_Slice => True,
         Raw_First     => Consumed - 1,
         Raw_Length    => 1);
   end Start_Text;

   procedure Finish_Text (Self : in out Parser; Result : in out Engine_Result; Consumed : in out Count) is
      Start          : constant Byte_Offset := Self.Next_Offset;
      Token          : constant Token_Kind := Self.Token;
      Status         : Parser_Duplicates.Operation_Status;
      Classification : Parser_Duplicates.Name_Classification;
   begin
      if not Consume_One (Self, Consumed, Result) then
         return;
      end if;

      if Token = Name_Token then
         Parser_Duplicates.Complete_Name
           (Self.Duplicate_Names, Self.Stack (Self.Depth).Duplicate_Context, Status, Classification);
         if Status /= Parser_Duplicates.Operation_Succeeded then
            Fail
              (Self,
               Result,
               (if Status = Parser_Duplicates.Index_Storage_Exhausted
                then Duplicate_Index_Exhausted
                elsif Status = Parser_Duplicates.Name_Storage_Exhausted
                then Name_Storage_Exhausted
                else Invalid_State),
               Self.Token_Start);
            return;
         elsif Classification = Parser_Duplicates.Duplicate_Name then
            Fail (Self, Result, Duplicate_Name, Self.Token_Start);
            return;
         end if;

      end if;

      Self.Token := No_Token;
      if Token = Name_Token then
         Self.Stack (Self.Depth).Phase := Object_Colon;
      else
         Complete_Value (Self);
      end if;

      Set_Event
        (Result,
         (if Token = Name_Token then Name_End else String_End),
         Start,
         1,
         Has_Raw_Slice => True,
         Raw_First     => Consumed - 1,
         Raw_Length    => 1);
   end Finish_Text;

   generic
      Track_Name : Boolean;
   procedure Process_Pending_UTF8_Specialized
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Consumed     : in out Count;
      Result       : in out Engine_Result);

   procedure Process_Pending_UTF8_Specialized
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Consumed     : in out Count;
      Result       : in out Engine_Result)
   is
      Value           : Octet;
      Feed            : Parser_UTF8.Feed_Result;
      Candidate       : Parser_UTF8.Decoder;
      First_Count     : constant Count := Consumed;
      First_Offset    : constant Byte_Offset := Self.Next_Offset;
      Retention_Error : Error_Code;
   begin
      while Parser_UTF8.Has_Pending_Octets (Self.UTF8) and then Consumed < Input'Length loop
         Value := Input_Octet (Input, Consumed);
         Candidate := Self.UTF8;
         Parser_UTF8.Feed (Candidate, Value, Feed);

         if Feed.Status = Parser_UTF8.Invalid then
            if Consumed > First_Count then
               Emit_Raw_Only_Text
                 (Self,
                  Result,
                  First_Offset,
                  Self.Next_Offset - First_Offset,
                  First_Count,
                  Consumed - First_Count);
            elsif Consume_One (Self, Consumed, Result) then
               Fail
                 (Self,
                  Result,
                  Invalid_UTF8,
                  (if Feed.Blame = Parser_UTF8.Stored_Lead_Octet
                   then Self.UTF8_Lead_Offset
                   else Self.Next_Offset - 1));
            end if;
            return;
         end if;

         Self.UTF8 := Candidate;
         if not Consume_One (Self, Consumed, Result) then
            return;
         end if;

         if Feed.Status = Parser_UTF8.Scalar_Ready then
            if Track_Name then
               Retain_Name_Scalar
                 (Self, (Length => Feed.Value.Length, Octets => Feed.Value.Octets), Retention_Error);
               if Retention_Error /= No_Error then
                  Defer_Failure (Self, Retention_Error, Self.UTF8_Lead_Offset);
                  Emit_Raw_Only_Text
                    (Self,
                     Result,
                     First_Offset,
                     Self.Next_Offset - First_Offset,
                     First_Count,
                     Consumed - First_Count);
                  return;
               end if;
            end if;
            Emit_Inline_Text
              (Self,
               Result,
               First_Offset,
               Self.Next_Offset - First_Offset,
               First_Count,
               Consumed - First_Count,
               Self.UTF8_Lead_Offset,
               Self.Next_Offset - Self.UTF8_Lead_Offset,
               (Length => Feed.Value.Length, Octets => Feed.Value.Octets));
            return;
         end if;
      end loop;

      if Parser_UTF8.Has_Pending_Octets (Self.UTF8) then
         if Consumed > First_Count then
            Emit_Raw_Only_Text
              (Self,
               Result,
               First_Offset,
               Self.Next_Offset - First_Offset,
               First_Count,
               Consumed - First_Count);
         elsif End_Of_Input then
            Fail (Self, Result, Truncated_Input, Self.Next_Offset);
         else
            Result.Outcome := Need_Input;
         end if;
      end if;
   end Process_Pending_UTF8_Specialized;

   procedure Process_Pending_Name_UTF8 is new Process_Pending_UTF8_Specialized (Track_Name => True);

   procedure Process_Pending_String_UTF8 is new Process_Pending_UTF8_Specialized (Track_Name => False);

   generic
      Track_Name : Boolean;
   procedure Process_Text_Specialized
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Consumed     : in out Count;
      Result       : in out Engine_Result);

   procedure Process_Text_Specialized
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Consumed     : in out Count;
      Result       : in out Engine_Result)
   is
      Value               : Octet;
      Feed                : Parser_UTF8.Feed_Result;
      Candidate_UTF8      : Parser_UTF8.Decoder;
      Digit               : Interfaces.Unsigned_32;
      Code_Point          : Interfaces.Unsigned_32;
      Candidate_Hex       : Interfaces.Unsigned_32;
      First_Count         : Count;
      Complete_Count      : Count;
      First_Offset        : Byte_Offset;
      Complete_Offset     : Byte_Offset;
      Scalar_First_Count  : Count;
      Scalar_First_Offset : Byte_Offset;
      Piece_First_Count   : constant Count := Consumed;
      Piece_First_Offset  : constant Byte_Offset := Self.Next_Offset;
      Name_Octets_Left    : Natural :=
        (if Track_Name then Parser_Duplicates.Available_Name_Octets (Self.Duplicate_Names) else 0);
      Retention_Error     : Error_Code;

      procedure Emit_Complete_Raw_Span is
         First_Index : constant Ada.Streams.Stream_Element_Offset :=
           Input'First + Ada.Streams.Stream_Element_Offset (First_Count);
         Last_Index  : constant Ada.Streams.Stream_Element_Offset :=
           Input'First + Ada.Streams.Stream_Element_Offset (Complete_Count) - 1;
      begin
         if Track_Name then
            Retain_Name_Octets (Self, Input (First_Index .. Last_Index), Retention_Error);
            if Retention_Error /= No_Error then
               Fail (Self, Result, Invalid_State, First_Offset);
               return;
            end if;
         end if;
         Emit_Raw_Text
           (Self,
            Result,
            First_Offset,
            Complete_Offset - First_Offset,
            First_Count,
            Complete_Count - First_Count);
      end Emit_Complete_Raw_Span;

      procedure Emit_Completed_Scalar (Scalar : Inline_Scalar; Decoded_First : Byte_Offset) is
      begin
         if Track_Name then
            Retain_Name_Scalar (Self, Scalar, Retention_Error);
            if Retention_Error /= No_Error then
               Defer_Failure (Self, Retention_Error, Decoded_First);
               Emit_Raw_Only_Text
                 (Self,
                  Result,
                  Piece_First_Offset,
                  Self.Next_Offset - Piece_First_Offset,
                  Piece_First_Count,
                  Consumed - Piece_First_Count);
               return;
            end if;
         end if;
         Emit_Inline_Text
           (Self,
            Result,
            Piece_First_Offset,
            Self.Next_Offset - Piece_First_Offset,
            Piece_First_Count,
            Consumed - Piece_First_Count,
            Decoded_First,
            Self.Next_Offset - Decoded_First,
            Scalar);
      end Emit_Completed_Scalar;
   begin
      if Self.Text_State = Text_Content and then Parser_UTF8.Has_Pending_Octets (Self.UTF8) then
         if Track_Name then
            Process_Pending_Name_UTF8 (Self, Input, End_Of_Input, Consumed, Result);
         else
            Process_Pending_String_UTF8 (Self, Input, End_Of_Input, Consumed, Result);
         end if;
         return;
      end if;

      loop
         if Self.Text_State = Text_Content then
            First_Count := Consumed;
            Complete_Count := Consumed;
            First_Offset := Self.Next_Offset;
            Complete_Offset := Self.Next_Offset;
            Scalar_First_Count := Consumed;
            Scalar_First_Offset := Self.Next_Offset;

            while Consumed < Input'Length loop
               Value := Input_Octet (Input, Consumed);
               exit when
                 not Parser_UTF8.Has_Pending_Octets (Self.UTF8)
                 and then (Value = Quote or else Value = Reverse_Solidus or else Value < 16#20#);

               if Value <= 16#7F# and then not Parser_UTF8.Has_Pending_Octets (Self.UTF8) then
                  Scalar_First_Offset := Self.Next_Offset;
                  if Track_Name and then Name_Octets_Left = 0 then
                     if Complete_Count > First_Count then
                        Emit_Complete_Raw_Span;
                     elsif Consume_One (Self, Consumed, Result) then
                        Defer_Failure (Self, Name_Storage_Exhausted, Scalar_First_Offset);
                        Emit_Raw_Only_Text (Self, Result, First_Offset, 1, First_Count, 1);
                     end if;
                     return;
                  end if;
                  if not Consume_One (Self, Consumed, Result) then
                     return;
                  end if;
                  if Track_Name then
                     Name_Octets_Left := Name_Octets_Left - 1;
                  end if;
                  Complete_Count := Consumed;
                  Complete_Offset := Self.Next_Offset;
               else
                  if not Parser_UTF8.Has_Pending_Octets (Self.UTF8) then
                     Self.UTF8_Lead_Offset := Self.Next_Offset;
                     Scalar_First_Count := Consumed;
                     Scalar_First_Offset := Self.Next_Offset;
                  end if;

                  Candidate_UTF8 := Self.UTF8;
                  Parser_UTF8.Feed (Candidate_UTF8, Value, Feed);

                  if Feed.Status = Parser_UTF8.Invalid then
                     if Complete_Count > First_Count then
                        --  Nothing from this call is externally visible yet,
                        --  so roll the malformed scalar back to its lead and
                        --  publish the preceding valid bulk span.  Retrying
                        --  the suffix then exposes the malformed scalar's
                        --  valid raw prefix before the proving-bad octet.
                        Consumed := Scalar_First_Count;
                        Self.Next_Offset := Scalar_First_Offset;
                        Result.Consumed := Consumed;
                        Parser_UTF8.Reset (Self.UTF8);
                        Emit_Complete_Raw_Span;
                     elsif Consumed > First_Count then
                        Emit_Raw_Only_Text
                          (Self,
                           Result,
                           First_Offset,
                           Self.Next_Offset - First_Offset,
                           First_Count,
                           Consumed - First_Count);
                     elsif Consume_One (Self, Consumed, Result) then
                        Fail
                          (Self,
                           Result,
                           Invalid_UTF8,
                           (if Feed.Blame = Parser_UTF8.Stored_Lead_Octet
                            then Self.UTF8_Lead_Offset
                            else Self.Next_Offset - 1));
                     end if;
                     return;
                  end if;

                  Self.UTF8 := Candidate_UTF8;
                  if not Consume_One (Self, Consumed, Result) then
                     return;
                  end if;

                  if Feed.Status = Parser_UTF8.Scalar_Ready then
                     if Track_Name and then Feed.Value.Length > Name_Octets_Left then
                        if Complete_Count > First_Count then
                           Consumed := Scalar_First_Count;
                           Self.Next_Offset := Scalar_First_Offset;
                           Result.Consumed := Consumed;
                           Parser_UTF8.Reset (Self.UTF8);
                           Emit_Complete_Raw_Span;
                        else
                           Defer_Failure (Self, Name_Storage_Exhausted, Scalar_First_Offset);
                           Emit_Raw_Only_Text
                             (Self,
                              Result,
                              First_Offset,
                              Self.Next_Offset - First_Offset,
                              First_Count,
                              Consumed - First_Count);
                        end if;
                        return;
                     end if;
                     if Track_Name then
                        Name_Octets_Left := Name_Octets_Left - Feed.Value.Length;
                     end if;
                     Complete_Count := Consumed;
                     Complete_Offset := Self.Next_Offset;
                  end if;
               end if;
            end loop;

            if Complete_Count > First_Count then
               if Parser_UTF8.Has_Pending_Octets (Self.UTF8) then
                  --  The caller cannot recover a raw slice after advancing
                  --  past this call.  Retry a trailing partial scalar from
                  --  its lead after publishing the preceding complete span.
                  Consumed := Scalar_First_Count;
                  Self.Next_Offset := Scalar_First_Offset;
                  Result.Consumed := Consumed;
                  Parser_UTF8.Reset (Self.UTF8);
               end if;
               Emit_Complete_Raw_Span;
               return;
            end if;

            if Parser_UTF8.Has_Pending_Octets (Self.UTF8) then
               if Consumed > First_Count then
                  Emit_Raw_Only_Text
                    (Self,
                     Result,
                     First_Offset,
                     Self.Next_Offset - First_Offset,
                     First_Count,
                     Consumed - First_Count);
               elsif End_Of_Input then
                  Fail (Self, Result, Truncated_Input, Self.Next_Offset);
               else
                  Result.Outcome := Need_Input;
               end if;
               return;
            elsif Consumed = Input'Length then
               if End_Of_Input then
                  Fail (Self, Result, Truncated_Input, Self.Next_Offset);
               else
                  Result.Outcome := Need_Input;
               end if;
               return;
            end if;

            Value := Input_Octet (Input, Consumed);
            if Value = Quote then
               Finish_Text (Self, Result, Consumed);
               return;
            elsif Value < 16#20# then
               if Consume_One (Self, Consumed, Result) then
                  Fail (Self, Result, Raw_Control_Character, Self.Next_Offset - 1);
               end if;
               return;
            else
               Self.Text_Escape_Start := Self.Next_Offset;
               if not Consume_One (Self, Consumed, Result) then
                  return;
               end if;
               Self.Text_State := Text_After_Escape;
            end if;

         elsif Self.Text_State = Text_After_Escape then
            if Consumed = Input'Length then
               if Consumed > Piece_First_Count then
                  Emit_Raw_Only_Text
                    (Self,
                     Result,
                     Piece_First_Offset,
                     Self.Next_Offset - Piece_First_Offset,
                     Piece_First_Count,
                     Consumed - Piece_First_Count);
               elsif End_Of_Input then
                  Fail (Self, Result, Truncated_Input, Self.Next_Offset);
               else
                  Result.Outcome := Need_Input;
               end if;
               return;
            end if;

            Value := Input_Octet (Input, Consumed);
            case Value is
               when Character'Pos ('"') | Character'Pos ('\') | Character'Pos ('/') =>
                  Code_Point := Interfaces.Unsigned_32 (Value);

               when Character'Pos ('b')                                             =>
                  Code_Point := 16#08#;

               when Character'Pos ('f')                                             =>
                  Code_Point := 16#0C#;

               when Character'Pos ('n')                                             =>
                  Code_Point := 16#0A#;

               when Character'Pos ('r')                                             =>
                  Code_Point := 16#0D#;

               when Character'Pos ('t')                                             =>
                  Code_Point := 16#09#;

               when Character'Pos ('u')                                             =>
                  if not Consume_One (Self, Consumed, Result) then
                     return;
                  end if;
                  Self.Text_State := Text_Unicode_Digits;
                  Self.Text_Hex_Value := 0;
                  Self.Text_Hex_Digits := 0;
                  goto Continue_Text;

               when others                                                          =>
                  if Consumed > Piece_First_Count then
                     Emit_Raw_Only_Text
                       (Self,
                        Result,
                        Piece_First_Offset,
                        Self.Next_Offset - Piece_First_Offset,
                        Piece_First_Count,
                        Consumed - Piece_First_Count);
                  elsif Consume_One (Self, Consumed, Result) then
                     Fail (Self, Result, Invalid_Escape, Self.Next_Offset - 1);
                  end if;
                  return;
            end case;

            if not Consume_One (Self, Consumed, Result) then
               return;
            end if;
            Self.Text_State := Text_Content;
            Emit_Completed_Scalar (Encode_UTF8 (Code_Point), Self.Text_Escape_Start);
            return;

         elsif Self.Text_State in Text_Unicode_Digits | Text_Low_Digits then
            while Self.Text_Hex_Digits < 4 and then Consumed < Input'Length loop
               Value := Input_Octet (Input, Consumed);
               if not Hex_Digit (Value, Digit) then
                  if Consumed > Piece_First_Count then
                     Emit_Raw_Only_Text
                       (Self,
                        Result,
                        Piece_First_Offset,
                        Self.Next_Offset - Piece_First_Offset,
                        Piece_First_Count,
                        Consumed - Piece_First_Count);
                  elsif Consume_One (Self, Consumed, Result) then
                     Fail (Self, Result, Invalid_Escape, Self.Next_Offset - 1);
                  end if;
                  return;
               end if;

               Candidate_Hex := Self.Text_Hex_Value * 16 + Digit;

               if Self.Text_Hex_Digits = 3
                 and then ((Self.Text_State = Text_Unicode_Digits
                            and then Candidate_Hex in 16#DC00# .. 16#DFFF#)
                           or else (Self.Text_State = Text_Low_Digits
                                    and then Candidate_Hex not in 16#DC00# .. 16#DFFF#))
               then
                  if Consumed > Piece_First_Count then
                     Emit_Raw_Only_Text
                       (Self,
                        Result,
                        Piece_First_Offset,
                        Self.Next_Offset - Piece_First_Offset,
                        Piece_First_Count,
                        Consumed - Piece_First_Count);
                  elsif Consume_One (Self, Consumed, Result) then
                     Fail
                       (Self,
                        Result,
                        Invalid_Surrogate,
                        (if Self.Text_State = Text_Unicode_Digits
                         then Self.Text_Escape_Start
                         else Self.Text_High_Start));
                  end if;
                  return;
               end if;

               if not Consume_One (Self, Consumed, Result) then
                  return;
               end if;
               Self.Text_Hex_Value := Candidate_Hex;
               Self.Text_Hex_Digits := Self.Text_Hex_Digits + 1;
            end loop;

            if Self.Text_Hex_Digits < 4 then
               if Consumed > Piece_First_Count then
                  Emit_Raw_Only_Text
                    (Self,
                     Result,
                     Piece_First_Offset,
                     Self.Next_Offset - Piece_First_Offset,
                     Piece_First_Count,
                     Consumed - Piece_First_Count);
               elsif End_Of_Input then
                  Fail (Self, Result, Truncated_Input, Self.Next_Offset);
               else
                  Result.Outcome := Need_Input;
               end if;
               return;
            end if;

            Code_Point := Self.Text_Hex_Value;
            Self.Text_Hex_Value := 0;
            Self.Text_Hex_Digits := 0;

            if Self.Text_State = Text_Unicode_Digits then
               if Code_Point in 16#D800# .. 16#DBFF# then
                  Self.Text_High_Surrogate := Code_Point;
                  Self.Text_High_Start := Self.Text_Escape_Start;
                  Self.Text_State := Text_Low_Backslash;
                  goto Continue_Text;
               else
                  Self.Text_State := Text_Content;
                  Emit_Completed_Scalar (Encode_UTF8 (Code_Point), Self.Text_Escape_Start);
                  return;
               end if;
            else
               Code_Point :=
                 16#10000# + (Self.Text_High_Surrogate - 16#D800#) * 16#400# + (Code_Point - 16#DC00#);
               Self.Text_State := Text_Content;
               Emit_Completed_Scalar (Encode_UTF8 (Code_Point), Self.Text_High_Start);
               return;
            end if;

         elsif Self.Text_State = Text_Low_Backslash then
            if Consumed = Input'Length then
               if Consumed > Piece_First_Count then
                  Emit_Raw_Only_Text
                    (Self,
                     Result,
                     Piece_First_Offset,
                     Self.Next_Offset - Piece_First_Offset,
                     Piece_First_Count,
                     Consumed - Piece_First_Count);
               elsif End_Of_Input then
                  Fail (Self, Result, Truncated_Input, Self.Next_Offset);
               else
                  Result.Outcome := Need_Input;
               end if;
               return;
            end if;

            Value := Input_Octet (Input, Consumed);
            if Value /= Reverse_Solidus then
               if Consumed > Piece_First_Count then
                  Emit_Raw_Only_Text
                    (Self,
                     Result,
                     Piece_First_Offset,
                     Self.Next_Offset - Piece_First_Offset,
                     Piece_First_Count,
                     Consumed - Piece_First_Count);
               elsif Consume_One (Self, Consumed, Result) then
                  Fail (Self, Result, Invalid_Surrogate, Self.Text_High_Start);
               end if;
               return;
            end if;
            if not Consume_One (Self, Consumed, Result) then
               return;
            end if;
            Self.Text_State := Text_Low_U;

         else
            if Consumed = Input'Length then
               if Consumed > Piece_First_Count then
                  Emit_Raw_Only_Text
                    (Self,
                     Result,
                     Piece_First_Offset,
                     Self.Next_Offset - Piece_First_Offset,
                     Piece_First_Count,
                     Consumed - Piece_First_Count);
               elsif End_Of_Input then
                  Fail (Self, Result, Truncated_Input, Self.Next_Offset);
               else
                  Result.Outcome := Need_Input;
               end if;
               return;
            end if;

            Value := Input_Octet (Input, Consumed);
            if Value /= Character'Pos ('u') then
               if Consumed > Piece_First_Count then
                  Emit_Raw_Only_Text
                    (Self,
                     Result,
                     Piece_First_Offset,
                     Self.Next_Offset - Piece_First_Offset,
                     Piece_First_Count,
                     Consumed - Piece_First_Count);
               elsif Consume_One (Self, Consumed, Result) then
                  Fail (Self, Result, Invalid_Escape, Self.Next_Offset - 1);
               end if;
               return;
            end if;
            if not Consume_One (Self, Consumed, Result) then
               return;
            end if;
            Self.Text_Escape_Start := Self.Next_Offset - 2;
            Self.Text_State := Text_Low_Digits;
            Self.Text_Hex_Value := 0;
            Self.Text_Hex_Digits := 0;
         end if;

         <<Continue_Text>>
         null;
      end loop;
   end Process_Text_Specialized;

   procedure Process_Name_Text is new Process_Text_Specialized (Track_Name => True);

   procedure Process_String_Text is new Process_Text_Specialized (Track_Name => False);

   procedure Process_Literal
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Consumed     : in out Count;
      Result       : in out Engine_Result)
   is
      Token          : constant Token_Kind := Self.Token;
      Length         : constant Natural := Literal_Length (Token);
      Local_Consumed : Count := Consumed;
      Local_Offset   : Byte_Offset := Self.Next_Offset;
      Position       : Natural := Self.Literal_Position;
      Value          : Octet;

      procedure Commit_Position is
      begin
         Consumed := Local_Consumed;
         Self.Next_Offset := Local_Offset;
         Self.Literal_Position := Position;
      end Commit_Position;
   begin
      while Position < Length and then Local_Consumed < Input'Length loop
         if Local_Offset = Byte_Offset'Last then
            Commit_Position;
            Fail (Self, Result, Offset_Exhausted, Local_Offset);
            return;
         end if;

         Value := Input_Octet (Input, Local_Consumed);
         Local_Consumed := Local_Consumed + 1;
         Local_Offset := Local_Offset + 1;

         if Value /= Literal_Octet (Token, Position + 1) then
            Commit_Position;
            Fail (Self, Result, Invalid_Literal, Local_Offset - 1);
            return;
         end if;

         Position := Position + 1;
      end loop;
      Commit_Position;

      if Position < Length then
         if End_Of_Input then
            Fail (Self, Result, Truncated_Input, Self.Next_Offset);
         else
            Self.Literal_Can_Slice := False;
            Result.Outcome := Need_Input;
         end if;
         return;
      end if;

      if Consumed < Input'Length then
         Value := Input_Octet (Input, Consumed);
         if not Is_Token_Delimiter (Value) then
            if Consume_One (Self, Consumed, Result) then
               Fail (Self, Result, Invalid_Literal, Self.Next_Offset - 1);
            end if;
            return;
         end if;

         Emit_Literal (Self, Result);
      elsif End_Of_Input then
         Emit_Literal (Self, Result);
      else
         Self.Literal_Can_Slice := False;
         Result.Outcome := Need_Input;
      end if;
   end Process_Literal;

   procedure Process_Initial_Literal
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Consumed     : in out Count;
      Result       : in out Engine_Result;
      Token        : Token_Kind)
   is
      Length    : constant Natural := Literal_Length (Token);
      Available : constant Count := Input'Length - Consumed;
      Matches   : Boolean;
      Value     : Octet;
      Start     : constant Byte_Offset := Self.Next_Offset;
   begin
      --  A complete atom plus lookahead, or a final atom, can be checked
      --  without entering the resumable literal state machine.  Keep the
      --  state-machine path for every chunk-boundary and offset-boundary case.
      if Available < Count (Length)
        or else (Available = Count (Length) and then not End_Of_Input)
        or else Self.Next_Offset > Byte_Offset'Last - Byte_Offset (Length)
      then
         Start_Literal (Self, Token, Consumed);
         Process_Literal (Self, Input, End_Of_Input, Consumed, Result);
         return;
      end if;

      Matches :=
        (case Token is
           when Null_Token  =>
             Input_Octet (Input, Consumed + 1) = Character'Pos ('u')
             and Input_Octet (Input, Consumed + 2) = Character'Pos ('l')
             and Input_Octet (Input, Consumed + 3) = Character'Pos ('l'),
           when True_Token  =>
             Input_Octet (Input, Consumed + 1) = Character'Pos ('r')
             and Input_Octet (Input, Consumed + 2) = Character'Pos ('u')
             and Input_Octet (Input, Consumed + 3) = Character'Pos ('e'),
           when False_Token =>
             Input_Octet (Input, Consumed + 1) = Character'Pos ('a')
             and Input_Octet (Input, Consumed + 2) = Character'Pos ('l')
             and Input_Octet (Input, Consumed + 3) = Character'Pos ('s')
             and Input_Octet (Input, Consumed + 4) = Character'Pos ('e'),
           when others      => False);

      if not Matches then
         Start_Literal (Self, Token, Consumed);
         Process_Literal (Self, Input, End_Of_Input, Consumed, Result);
         return;
      end if;

      Consumed := Consumed + Count (Length);
      Self.Next_Offset := Self.Next_Offset + Byte_Offset (Length);
      Result.Consumed := Consumed;

      if Consumed < Input'Length then
         Value := Input_Octet (Input, Consumed);
         if not Is_Token_Delimiter (Value) then
            Begin_Scalar_Value (Self);
            if Consume_One (Self, Consumed, Result) then
               Fail (Self, Result, Invalid_Literal, Self.Next_Offset - 1);
            end if;
            return;
         end if;
      end if;

      Begin_Scalar_Value (Self);
      Complete_Value (Self);
      Set_Event
        (Result,
         (if Token = Null_Token then Null_Value else Boolean_Value),
         Start,
         Byte_Offset (Length),
         Has_Raw_Slice => True,
         Raw_First     => Consumed - Count (Length),
         Raw_Length    => Count (Length),
         Boolean_Data  => Token = True_Token);
   end Process_Initial_Literal;

   pragma Inline_Always (Process_Initial_Literal);

   procedure Process_Number
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Consumed     : in out Count;
      Result       : in out Engine_Result)
   is
      First_Count  : constant Count := Consumed;
      First_Offset : constant Byte_Offset := Self.Next_Offset;
      Value        : Octet;
      Transition   : Parser_Numbers.Transition_Result;
      Candidate    : Parser_Numbers.Number_State;
      Run_End      : Count;
      Run_Length   : Count;
      Offset_Room  : Byte_Offset;
   begin
      while Consumed < Input'Length loop
         if Parser_Numbers.Scanning_Integer_Digits (Self.Number)
           and then Input_Octet (Input, Consumed) in Zero .. Nine
         then
            Run_End := Consumed + 1;
            while Run_End < Input'Length and then Input_Octet (Input, Run_End) in Zero .. Nine loop
               Run_End := Run_End + 1;
            end loop;

            Run_Length := Run_End - Consumed;
            Offset_Room := Byte_Offset'Last - Self.Next_Offset;
            if Byte_Offset (Run_Length) > Offset_Room then
               Consumed := Consumed + Count (Offset_Room);
               Self.Next_Offset := Byte_Offset'Last;
               Result.Consumed := Consumed;
               Fail (Self, Result, Offset_Exhausted, Self.Next_Offset);
               return;
            end if;

            Consumed := Run_End;
            Self.Next_Offset := Self.Next_Offset + Byte_Offset (Run_Length);
            Result.Consumed := Consumed;
            exit when Consumed = Input'Length;
         end if;

         Value := Input_Octet (Input, Consumed);

         if Is_Number_Octet (Value) then
            Candidate := Self.Number;
            Parser_Numbers.Push (Candidate, Value, Transition);

            if Transition = Parser_Numbers.Transition_Invalid then
               if Consumed > First_Count then
                  Set_Event
                    (Result,
                     Number_Fragment,
                     First_Offset,
                     Byte_Offset (Consumed - First_Count),
                     True,
                     First_Count,
                     Consumed - First_Count);
               elsif Consume_One (Self, Consumed, Result) then
                  Fail (Self, Result, Invalid_Number, Self.Next_Offset - 1);
               end if;
               return;
            end if;

            Self.Number := Candidate;
            if not Consume_One (Self, Consumed, Result) then
               return;
            end if;
         elsif Is_Token_Delimiter (Value) then
            if not Parser_Numbers.Accepting_End (Self.Number) then
               if Consumed > First_Count then
                  Set_Event
                    (Result,
                     Number_Fragment,
                     First_Offset,
                     Byte_Offset (Consumed - First_Count),
                     True,
                     First_Count,
                     Consumed - First_Count);
               elsif Consume_One (Self, Consumed, Result) then
                  Fail (Self, Result, Invalid_Number, Self.Next_Offset - 1);
               end if;
               return;
            end if;
            exit;
         else
            if Consumed > First_Count then
               Set_Event
                 (Result,
                  Number_Fragment,
                  First_Offset,
                  Byte_Offset (Consumed - First_Count),
                  True,
                  First_Count,
                  Consumed - First_Count);
            elsif Consume_One (Self, Consumed, Result) then
               Fail (Self, Result, Invalid_Number, Self.Next_Offset - 1);
            end if;
            return;
         end if;
      end loop;

      if Consumed > First_Count then
         Set_Event
           (Result,
            Number_Fragment,
            First_Offset,
            Byte_Offset (Consumed - First_Count),
            True,
            First_Count,
            Consumed - First_Count);
         return;
      end if;

      if Consumed < Input'Length then
         Self.Token := No_Token;
         Complete_Value (Self);
         Set_Event (Result, Number_End, Self.Next_Offset, 0);
      elsif End_Of_Input then
         if Parser_Numbers.Accepting_End (Self.Number) then
            Self.Token := No_Token;
            Complete_Value (Self);
            Set_Event (Result, Number_End, Self.Next_Offset, 0);
         else
            Fail (Self, Result, Truncated_Input, Self.Next_Offset);
         end if;
      else
         Result.Outcome := Need_Input;
      end if;
   end Process_Number;

   pragma Inline_Always (Process_Number);

   procedure Start_Number (Self : in out Parser; Result : in out Engine_Result) is
   begin
      Begin_Scalar_Value (Self);
      Self.Token := Number_Token;
      Self.Token_Start := Self.Next_Offset;
      Parser_Numbers.Reset (Self.Number);
      Set_Event (Result, Number_Begin, Self.Next_Offset, 0);
   end Start_Number;

   procedure Push_Container
     (Self     : in out Parser;
      Kind     : Container_Kind;
      Phase    : Container_Phase;
      Result   : in out Engine_Result;
      Consumed : in out Count)
   is
      Start : constant Byte_Offset := Self.Next_Offset;
   begin
      if Self.Depth = Self.Maximum_Depth then
         Fail (Self, Result, Depth_Exhausted, Start);
         return;
      end if;

      Start_Container_Value (Self);
      if not Consume_One (Self, Consumed, Result) then
         return;
      end if;

      Self.Depth := Self.Depth + 1;
      Self.Stack (Self.Depth) := (Phase => Phase, Duplicate_Context => <>);
      if Kind = Object_Container then
         Parser_Duplicates.Begin_Object (Self.Duplicate_Names, Self.Stack (Self.Depth).Duplicate_Context);
      end if;
      Set_Event
        (Result,
         (if Kind = Array_Container then Array_Begin else Object_Begin),
         Start,
         1,
         True,
         Consumed - 1,
         1);
   end Push_Container;

   procedure Close_Container
     (Self : in out Parser; Kind : Container_Kind; Result : in out Engine_Result; Consumed : in out Count)
   is
      Start : constant Byte_Offset := Self.Next_Offset;
   begin
      if not Consume_One (Self, Consumed, Result) then
         return;
      end if;

      if Kind = Object_Container then
         Parser_Duplicates.End_Object (Self.Duplicate_Names, Self.Stack (Self.Depth).Duplicate_Context);
      end if;
      Self.Depth := Self.Depth - 1;
      if Self.Depth = 0 then
         Self.Root_Complete := True;
      end if;

      Set_Event
        (Result, (if Kind = Array_Container then Array_End else Object_End), Start, 1, True, Consumed - 1, 1);
   end Close_Container;

   procedure Initialize (Self : in out Parser) is
   begin
      if Self.Current_State = Uninitialized then
         Self.Current_State := Ready;
         Self.Last_Diagnostic := Empty_Diagnostic;
         Self.Next_Offset := 0;
         Self.Depth := 0;
         Self.Root_Started := False;
         Self.Root_Complete := False;
         Self.Document_End_Sent := False;
         Self.Token := No_Token;
         Self.Text_State := Text_Content;
         Self.Text_Hex_Value := 0;
         Self.Text_Hex_Digits := 0;
         Self.Text_High_Surrogate := 0;
         Self.Literal_Position := 0;
         Self.Literal_Can_Slice := False;
         Parser_Numbers.Reset (Self.Number);
         Parser_UTF8.Reset (Self.UTF8);
         Parser_Duplicates.Reset (Self.Duplicate_Names);
      end if;
   end Initialize;

   generic
      with procedure Publish (Item : Buffered_Event; Buffer_Full : out Boolean);
      --  True for Amount guarantees that the next Amount - 1 Publish
      --  operations cannot report full; the Amount-th may report full.
      with function Can_Publish (Amount : Count) return Boolean;
   procedure Run
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Result       : out Engine_Result);

   procedure Run
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Result       : out Engine_Result)
   is
      Consumed    : Count := 0;
      Value       : Octet;
      Buffer_Full : Boolean;

      procedure Process_Initial_Number_Burst (Stop_Run : out Boolean) is
         Published_Kind   : Event_Kind;
         Zero_Is_Complete : constant Boolean :=
           Input_Octet (Input, Consumed) = Zero
           and then Self.Next_Offset /= Byte_Offset'Last
           and then ((Consumed + 1 < Input'Length
                      and then Is_Token_Delimiter (Input_Octet (Input, Consumed + 1)))
                     or else (Consumed + 1 = Input'Length and then End_Of_Input));
         Zero_Start       : constant Byte_Offset := Self.Next_Offset;
         Zero_Transition  : Parser_Numbers.Transition_Result;
      begin
         Start_Number (Self, Result);
         if Zero_Is_Complete then
            Publish (Result.Item, Buffer_Full);
            if Buffer_Full then
               Stop_Run := True;
               return;
            end if;

            Parser_Numbers.Push (Self.Number, Zero, Zero_Transition);
            pragma Assert (Zero_Transition = Parser_Numbers.Transition_Accepted);
            if not Consume_One (Self, Consumed, Result) then
               Stop_Run := True;
               return;
            end if;
            Set_Event
              (Result,
               Number_Fragment,
               Zero_Start,
               1,
               Has_Raw_Slice => True,
               Raw_First     => Consumed - 1,
               Raw_Length    => 1);
            Publish (Result.Item, Buffer_Full);
            if Buffer_Full then
               Stop_Run := True;
               return;
            end if;

            Self.Token := No_Token;
            Complete_Value (Self);
            Set_Event (Result, Number_End, Self.Next_Offset, 0);
            Publish (Result.Item, Buffer_Full);
            Stop_Run := Buffer_Full;
            return;
         end if;

         loop
            Published_Kind := Result.Item.Kind;
            Publish (Result.Item, Buffer_Full);
            if Buffer_Full then
               Stop_Run := True;
               return;
            elsif Published_Kind = Number_End then
               Stop_Run := False;
               return;
            end if;

            Result.Outcome := Need_Input;
            Result.Diagnostic := Empty_Diagnostic;
            Process_Number (Self, Input, End_Of_Input, Consumed, Result);
            if Result.Outcome /= Event_Ready then
               Stop_Run := True;
               return;
            end if;
         end loop;
      end Process_Initial_Number_Burst;

      pragma Inline_Always (Process_Initial_Number_Burst);

      procedure Process_Dense_Array_Burst (Stop_Run : out Boolean) is
         Token          : Token_Kind;
         Length         : Natural;
         Matches        : Boolean;
         Complete_Limit : Count := 0;
         Scalar_Start   : Byte_Offset;
      begin
         loop
            Complete_Limit := 0;
            if Consumed = Input'Length or else Input_Octet (Input, Consumed) /= Comma then
               Stop_Run := False;
               return;
            end if;

            --  A complete literal after the comma leaves this array frame in
            --  Array_Comma_Or_End.  Validate the entire transition before any
            --  effect, then advance the comma and literal together without
            --  writing the transient Array_Value phase.
            if Consumed + 1 < Input'Length then
               Value := Input_Octet (Input, Consumed + 1);

               --  A complete zero has a fixed three-event transcript.  When
               --  the publisher can accept that whole transcript, finish it
               --  without materializing resumable number-token state.  Small
               --  buffers and Next retain the ordinary incremental path.
               --  Token stays No_Token; a later number resets the dormant DFA
               --  before use.
               if Value = Zero
                 and then Can_Publish (3)
                 and then Self.Next_Offset <= Byte_Offset'Last - 2
                 and then ((Consumed + 2 < Input'Length
                            and then Is_Token_Delimiter (Input_Octet (Input, Consumed + 2)))
                           or else (Consumed + 2 = Input'Length and then End_Of_Input))
               then
                  Scalar_Start := Self.Next_Offset + 1;
                  Consumed := Consumed + 2;
                  Self.Next_Offset := Self.Next_Offset + 2;
                  Result.Consumed := Consumed;

                  Set_Event (Result, Number_Begin, Scalar_Start, 0);
                  Publish (Result.Item, Buffer_Full);
                  pragma Assert (not Buffer_Full);

                  Set_Event
                    (Result,
                     Number_Fragment,
                     Scalar_Start,
                     1,
                     Has_Raw_Slice => True,
                     Raw_First     => Consumed - 1,
                     Raw_Length    => 1);
                  Publish (Result.Item, Buffer_Full);
                  pragma Assert (not Buffer_Full);

                  Set_Event (Result, Number_End, Self.Next_Offset, 0);
                  Publish (Result.Item, Buffer_Full);
                  if Buffer_Full then
                     Stop_Run := True;
                     return;
                  end if;
                  goto Continue_Dense_Array;
               end if;

               Token :=
                 (if Value = Character'Pos ('n')
                  then Null_Token
                  elsif Value = Character'Pos ('t')
                  then True_Token
                  elsif Value = Character'Pos ('f')
                  then False_Token
                  else No_Token);
               Length := (if Token = No_Token then 0 else Literal_Length (Token));
               if Token /= No_Token and then Count (Length + 1) <= Input'Length - Consumed then
                  Complete_Limit := Consumed + Count (Length + 1);
               end if;
               if Token /= No_Token
                 and then Complete_Limit /= 0
                 and then (Complete_Limit < Input'Length or else End_Of_Input)
                 and then Self.Next_Offset <= Byte_Offset'Last - Byte_Offset (Length + 1)
               then
                  Matches :=
                    (case Token is
                       when Null_Token  =>
                         Input_Octet (Input, Consumed + 2) = Character'Pos ('u')
                         and Input_Octet (Input, Consumed + 3) = Character'Pos ('l')
                         and Input_Octet (Input, Consumed + 4) = Character'Pos ('l'),
                       when True_Token  =>
                         Input_Octet (Input, Consumed + 2) = Character'Pos ('r')
                         and Input_Octet (Input, Consumed + 3) = Character'Pos ('u')
                         and Input_Octet (Input, Consumed + 4) = Character'Pos ('e'),
                       when False_Token =>
                         Input_Octet (Input, Consumed + 2) = Character'Pos ('a')
                         and Input_Octet (Input, Consumed + 3) = Character'Pos ('l')
                         and Input_Octet (Input, Consumed + 4) = Character'Pos ('s')
                         and Input_Octet (Input, Consumed + 5) = Character'Pos ('e'),
                       when others      => False);
                  if Matches
                    and then (Complete_Limit = Input'Length
                              or else Input_Octet (Input, Complete_Limit) = Comma
                              or else Is_Token_Delimiter (Input_Octet (Input, Complete_Limit)))
                  then
                     Scalar_Start := Self.Next_Offset + 1;
                     Consumed := Complete_Limit;
                     Self.Next_Offset := Self.Next_Offset + Byte_Offset (Length + 1);
                     Result.Consumed := Consumed;
                     Set_Event
                       (Result,
                        (if Token = Null_Token then Null_Value else Boolean_Value),
                        Scalar_Start,
                        Byte_Offset (Length),
                        Has_Raw_Slice => True,
                        Raw_First     => Consumed - Count (Length),
                        Raw_Length    => Count (Length),
                        Boolean_Data  => Token = True_Token);
                     Publish (Result.Item, Buffer_Full);
                     if Buffer_Full then
                        Stop_Run := True;
                        return;
                     end if;
                     goto Continue_Dense_Array;
                  end if;
               end if;
            end if;

            if not Consume_One (Self, Consumed, Result) then
               Stop_Run := True;
               return;
            end if;
            Self.Stack (Self.Depth).Phase := Array_Value;

            if Consumed = Input'Length then
               Stop_Run := False;
               return;
            end if;

            Value := Input_Octet (Input, Consumed);
            Token :=
              (if Value = Character'Pos ('n')
               then Null_Token
               elsif Value = Character'Pos ('t')
               then True_Token
               elsif Value = Character'Pos ('f')
               then False_Token
               else No_Token);

            if Token /= No_Token then
               Result.Outcome := Need_Input;
               Result.Diagnostic := Empty_Diagnostic;
               Process_Initial_Literal (Self, Input, End_Of_Input, Consumed, Result, Token);
               if Result.Outcome /= Event_Ready then
                  Stop_Run := True;
                  return;
               end if;

               Publish (Result.Item, Buffer_Full);
               if Buffer_Full then
                  Stop_Run := True;
                  return;
               end if;
            elsif Value = Minus or else Value in Zero .. Nine then
               Process_Initial_Number_Burst (Stop_Run);
               if Stop_Run then
                  return;
               end if;
            else
               Stop_Run := False;
               return;
            end if;

            <<Continue_Dense_Array>>
            null;
         end loop;
      end Process_Dense_Array_Burst;

      pragma Inline_Always (Process_Dense_Array_Burst);

      Stop_Run : Boolean;
   begin
      Clear_Result (Result);

      Engine_Loop :
      loop
         Result.Outcome := Need_Input;
         Result.Diagnostic := Empty_Diagnostic;

         One_Event :
         loop
            if Self.Current_State = Ready then
               Self.Current_State := Active;
               Set_Event (Result, Document_Begin, Self.Next_Offset, 0);
               exit One_Event;
            elsif Self.Current_State = Failure_Pending then
               Self.Current_State := Failed;
               Result.Outcome := Parse_Failed;
               Result.Diagnostic := Self.Last_Diagnostic;
               exit One_Event;
            elsif Self.Current_State /= Active then
               Result.Outcome := Call_Rejected;
               Result.Diagnostic := (Code => Invalid_State, Offset => Self.Next_Offset);
               exit One_Event;
            end if;

            if Self.Token = Number_Token then
               Process_Number (Self, Input, End_Of_Input, Consumed, Result);
               exit One_Event;
            elsif Self.Token in Null_Token | True_Token | False_Token then
               Process_Literal (Self, Input, End_Of_Input, Consumed, Result);
               exit One_Event;
            elsif Self.Token = Name_Token then
               Process_Name_Text (Self, Input, End_Of_Input, Consumed, Result);
               exit One_Event;
            elsif Self.Token = String_Token then
               Process_String_Text (Self, Input, End_Of_Input, Consumed, Result);
               exit One_Event;
            end if;

            if Self.Root_Complete and then not Self.Document_End_Sent then
               Self.Document_End_Sent := True;
               Set_Event (Result, Document_End, Self.Next_Offset, 0);
               exit One_Event;
            end if;

            Grammar_Loop :
            loop
               while Consumed < Input'Length and then Is_Whitespace (Input_Octet (Input, Consumed)) loop
                  exit when not Consume_One (Self, Consumed, Result);
               end loop;

               if Self.Current_State = Failed then
                  exit One_Event;
               end if;

               if Consumed = Input'Length then
                  if End_Of_Input then
                     if Self.Document_End_Sent then
                        Self.Current_State := Completed;
                        Result.Outcome := Document_Complete;
                     else
                        Fail (Self, Result, Truncated_Input, Self.Next_Offset);
                     end if;
                  else
                     Result.Outcome := Need_Input;
                  end if;
                  exit One_Event;
               end if;

               Value := Input_Octet (Input, Consumed);

               if Self.Document_End_Sent then
                  if Consume_One (Self, Consumed, Result) then
                     Fail (Self, Result, Trailing_Input, Self.Next_Offset - 1);
                  end if;
                  exit One_Event;
               end if;

               if Self.Depth > 0 then
                  case Self.Stack (Self.Depth).Phase is
                     when Array_Comma_Or_End          =>
                        if Value = Comma then
                           Process_Dense_Array_Burst (Stop_Run);
                           if Stop_Run then
                              Result.Consumed := Consumed;
                              return;
                           end if;
                           goto Continue_Parsing;
                        elsif Value = Right_Bracket then
                           Close_Container (Self, Array_Container, Result, Consumed);
                           exit One_Event;
                        else
                           if Consume_One (Self, Consumed, Result) then
                              Fail (Self, Result, Unexpected_Token, Self.Next_Offset - 1);
                           end if;
                           exit One_Event;
                        end if;

                     when Object_Comma_Or_End         =>
                        if Value = Comma then
                           if not Consume_One (Self, Consumed, Result) then
                              exit One_Event;
                           end if;
                           Self.Stack (Self.Depth).Phase := Object_Name;
                           goto Continue_Parsing;
                        elsif Value = Right_Brace then
                           Close_Container (Self, Object_Container, Result, Consumed);
                           exit One_Event;
                        else
                           if Consume_One (Self, Consumed, Result) then
                              Fail (Self, Result, Unexpected_Token, Self.Next_Offset - 1);
                           end if;
                           exit One_Event;
                        end if;

                     when Object_First_Or_End         =>
                        if Value = Right_Brace then
                           Close_Container (Self, Object_Container, Result, Consumed);
                           exit One_Event;
                        elsif Value = Quote then
                           Start_Text (Self, Name_Token, Result, Consumed);
                           exit One_Event;
                        else
                           if Consume_One (Self, Consumed, Result) then
                              Fail (Self, Result, Unexpected_Token, Self.Next_Offset - 1);
                           end if;
                           exit One_Event;
                        end if;

                     when Object_Name                 =>
                        if Value = Quote then
                           Start_Text (Self, Name_Token, Result, Consumed);
                        else
                           if Consume_One (Self, Consumed, Result) then
                              Fail (Self, Result, Unexpected_Token, Self.Next_Offset - 1);
                           end if;
                        end if;
                        exit One_Event;

                     when Object_Colon | Object_Value =>
                        if Self.Stack (Self.Depth).Phase = Object_Colon then
                           if Value = Colon then
                              if not Consume_One (Self, Consumed, Result) then
                                 exit One_Event;
                              end if;
                              Self.Stack (Self.Depth).Phase := Object_Value;
                              goto Continue_Parsing;
                           else
                              if Consume_One (Self, Consumed, Result) then
                                 Fail (Self, Result, Unexpected_Token, Self.Next_Offset - 1);
                              end if;
                              exit One_Event;
                           end if;
                        end if;

                     when Array_First_Or_End          =>
                        if Value = Right_Bracket then
                           Close_Container (Self, Array_Container, Result, Consumed);
                           exit One_Event;
                        end if;

                     when Array_Value                 =>
                        if Value = Right_Bracket then
                           if Consume_One (Self, Consumed, Result) then
                              Fail (Self, Result, Unexpected_Token, Self.Next_Offset - 1);
                           end if;
                           exit One_Event;
                        end if;
                  end case;
               end if;

               if not Value_Is_Expected (Self) then
                  if Consume_One (Self, Consumed, Result) then
                     Fail (Self, Result, Unexpected_Token, Self.Next_Offset - 1);
                  end if;
                  exit One_Event;
               end if;

               if Value = Left_Bracket then
                  Push_Container (Self, Array_Container, Array_First_Or_End, Result, Consumed);
                  exit One_Event;
               elsif Value = Left_Brace then
                  Push_Container (Self, Object_Container, Object_First_Or_End, Result, Consumed);
                  exit One_Event;
               elsif Value = Quote then
                  Start_Text (Self, String_Token, Result, Consumed);
                  exit One_Event;
               elsif Value = Character'Pos ('n') then
                  Process_Initial_Literal (Self, Input, End_Of_Input, Consumed, Result, Null_Token);
                  exit One_Event;
               elsif Value = Character'Pos ('t') then
                  Process_Initial_Literal (Self, Input, End_Of_Input, Consumed, Result, True_Token);
                  exit One_Event;
               elsif Value = Character'Pos ('f') then
                  Process_Initial_Literal (Self, Input, End_Of_Input, Consumed, Result, False_Token);
                  exit One_Event;
               elsif Value = Minus or else Value in Zero .. Nine then
                  Process_Initial_Number_Burst (Stop_Run);
                  if Stop_Run then
                     Result.Consumed := Consumed;
                     return;
                  end if;
                  goto Continue_Parsing;
               else
                  if Consume_One (Self, Consumed, Result) then
                     Fail (Self, Result, Unexpected_Token, Self.Next_Offset - 1);
                  end if;
                  exit One_Event;
               end if;

               <<Continue_Parsing>>
               null;
            end loop Grammar_Loop;
         end loop One_Event;

         Result.Consumed := Consumed;
         exit Engine_Loop when Result.Outcome /= Event_Ready;

         Publish (Result.Item, Buffer_Full);
         exit Engine_Loop when Buffer_Full;
      end loop Engine_Loop;
   end Run;

   function To_Event (Item : Buffered_Event; Input_First : Byte_Offset) return Event is
      Raw                   : Chunk_Range := (First_Count => 0, Octet_Length => 0);
      Decoded_Source        : Source_Range := (First => 0, Octet_Length => 0);
      Decoded_Value         : Inline_Scalar := (Length => 0, Octets => [others => 0]);
      Has_Raw               : constant Boolean := (Item.Metadata and Has_Raw_Bit) /= 0;
      Decoded_Kind_Position : constant Interfaces.Unsigned_16 :=
        (Item.Metadata / Decoded_Kind_Factor) and 2#11#;
      Decoded_Kind          : constant Decoded_Fragment_Kind :=
        Decoded_Fragment_Kind'Val (Natural (Decoded_Kind_Position));
      Scalar_Length         : constant Natural := Natural ((Item.Metadata / Scalar_Length_Factor) and 2#111#);
      Decoded_Length        : constant Byte_Offset :=
        Byte_Offset ((Item.Metadata / Decoded_Length_Factor) and 2#1111#);
   begin
      if Has_Raw then
         Raw :=
           (First_Count  => Count (Item.Source.First - Input_First),
            Octet_Length => Count (Item.Source.Octet_Length));
      end if;

      case Decoded_Kind is
         when No_Decoded_Fragment   =>
            null;

         when Decoded_Is_Raw_Range  =>
            Decoded_Source := Item.Source;

         when Decoded_Inline_Scalar =>
            Decoded_Source :=
              (First        => Item.Source.First + Item.Source.Octet_Length - Decoded_Length,
               Octet_Length => Decoded_Length);
            Decoded_Value := (Length => Scalar_Length, Octets => Item.Scalar_Octets);
      end case;

      return
        (Kind           => Item.Kind,
         Source         => Item.Source,
         Has_Raw_Slice  => Has_Raw,
         Raw_Slice      => Raw,
         Decoded_Kind   => Decoded_Kind,
         Decoded_Source => Decoded_Source,
         Decoded        => Decoded_Value,
         Boolean_Data   => (Item.Metadata and Boolean_Bit) /= 0);
   end To_Event;

   function Buffered_Kind (Item : Buffered_Event) return Event_Kind
   is (Item.Kind);

   function Buffered_Source (Item : Buffered_Event) return Source_Range
   is (Item.Source);

   procedure Publish_One (Item : Buffered_Event; Buffer_Full : out Boolean) is
   begin
      pragma Unreferenced (Item);
      Buffer_Full := True;
   end Publish_One;

   pragma Inline_Always (Publish_One);

   function Next_Can_Publish (Amount : Count) return Boolean
   is (Amount <= 1);

   pragma Inline_Always (Next_Can_Publish);

   procedure Run_Next is new Run (Publish => Publish_One, Can_Publish => Next_Can_Publish);

   procedure Next
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Result       : out Next_Result)
   is
      Input_First : constant Byte_Offset := Self.Next_Offset;
      Scratch     : Engine_Result;
   begin
      Run_Next (Self, Input, End_Of_Input, Scratch);
      Result :=
        (Outcome    => Scratch.Outcome,
         Consumed   => Scratch.Consumed,
         Item       => To_Event (Scratch.Item, Input_First),
         Diagnostic => Scratch.Diagnostic);
   end Next;

   procedure Drain
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Events       : out Event_Array;
      Result       : out Drain_Result)
   is
      Capacity    : constant Count := Count (Events'Length);
      First_Event : constant Ada.Streams.Stream_Element_Offset := Events'First;
      Input_First : constant Byte_Offset := Self.Next_Offset;
      Produced    : Count := 0;
      Scratch     : Engine_Result;

      procedure Publish_Many (Item : Buffered_Event; Buffer_Full : out Boolean) is
      begin
         Events (First_Event + Ada.Streams.Stream_Element_Offset (Produced)) := To_Event (Item, Input_First);
         Produced := Produced + 1;
         Buffer_Full := Produced = Capacity;
      end Publish_Many;

      pragma Inline_Always (Publish_Many);

      --  Publish_Many maintains Produced <= Capacity.
      function Many_Can_Publish (Amount : Count) return Boolean
      is (Amount <= Capacity - Produced);

      pragma Inline_Always (Many_Can_Publish);

      procedure Run_Many is new Run (Publish => Publish_Many, Can_Publish => Many_Can_Publish);
   begin
      if Capacity = 0 then
         Result := (Stop => Drain_Buffer_Full, Consumed => 0, Produced => 0, Diagnostic => Empty_Diagnostic);
         return;
      end if;

      Run_Many (Self, Input, End_Of_Input, Scratch);
      Result :=
        (Stop       =>
           (case Scratch.Outcome is
              when Event_Ready       => Drain_Buffer_Full,
              when Need_Input        => Drain_Need_Input,
              when Document_Complete => Drain_Document_Complete,
              when Parse_Failed      => Drain_Parse_Failed,
              when Call_Rejected     => Drain_Call_Rejected),
         Consumed   => Scratch.Consumed,
         Produced   => Produced,
         Diagnostic => Scratch.Diagnostic);
   end Drain;

   procedure Buffered_Drain
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Events       : out Buffered_Event_Array;
      Result       : out Buffered_Drain_Result)
   is
      Capacity    : constant Count := Count (Events'Length);
      First_Event : constant Ada.Streams.Stream_Element_Offset := Events'First;
      Input_First : constant Byte_Offset := Self.Next_Offset;
      Produced    : Count := 0;
      Scratch     : Engine_Result;

      procedure Publish_Buffered (Item : Buffered_Event; Buffer_Full : out Boolean) is
      begin
         Events (First_Event + Ada.Streams.Stream_Element_Offset (Produced)) := Item;
         Produced := Produced + 1;
         Buffer_Full := Produced = Capacity;
      end Publish_Buffered;

      pragma Inline_Always (Publish_Buffered);

      --  Publish_Buffered maintains Produced <= Capacity.
      function Buffered_Can_Publish (Amount : Count) return Boolean
      is (Amount <= Capacity - Produced);

      pragma Inline_Always (Buffered_Can_Publish);

      procedure Run_Buffered is new Run (Publish => Publish_Buffered, Can_Publish => Buffered_Can_Publish);
   begin
      if Capacity = 0 then
         Result :=
           (Stop        => Drain_Buffer_Full,
            Input_First => Input_First,
            Consumed    => 0,
            Produced    => 0,
            Diagnostic  => Empty_Diagnostic);
         return;
      end if;

      Run_Buffered (Self, Input, End_Of_Input, Scratch);
      Result :=
        (Stop        =>
           (case Scratch.Outcome is
              when Event_Ready       => Drain_Buffer_Full,
              when Need_Input        => Drain_Need_Input,
              when Document_Complete => Drain_Document_Complete,
              when Parse_Failed      => Drain_Parse_Failed,
              when Call_Rejected     => Drain_Call_Rejected),
         Input_First => Input_First,
         Consumed    => Scratch.Consumed,
         Produced    => Produced,
         Diagnostic  => Scratch.Diagnostic);
   end Buffered_Drain;

   procedure Abort_Document (Self : in out Parser) is
   begin
      case Self.Current_State is
         when Uninitialized | Aborted =>
            null;

         when Failure_Pending         =>
            Self.Current_State := Failed;

         when others                  =>
            Self.Current_State := Aborted;
      end case;
   end Abort_Document;

   procedure Reset (Self : in out Parser) is
   begin
      if Self.Current_State in Failure_Pending | Completed | Failed | Aborted then
         Self.Current_State := Uninitialized;
         Initialize (Self);
      end if;
   end Reset;

   function State (Self : Parser) return Parser_State
   is (Self.Current_State);

   function Terminal_Diagnostic (Self : Parser) return Diagnostic
   is (Self.Last_Diagnostic);

end Flyology_JSON.Parser_Core;
