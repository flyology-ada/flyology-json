with Ada.Streams;
with Flyology_JSON.Parser_Duplicates;
with Flyology_JSON.Parser_Numbers;
with Flyology_JSON.Parser_UTF8;
with Interfaces;

--  Bounded, allocation-free incremental parser mechanism.
--
--  This is the private engine boundary.  Duplicate handling is selected by a
--  parser discriminant so a public generic instance can statically select the
--  strict or preserve mechanism.  This package deliberately contains no
--  resource-accounting hooks.

private package Flyology_JSON.Parser_Core is

   subtype Byte_Offset is Interfaces.Unsigned_64;

   type Duplicate_Mode is (Reject_Duplicates, Preserve_Unchecked);

   type Root_Policy is (Accept_Any, Require_Object);

   --  Resolved compatibility policy used by the private parser engine.
   --  @enum No_Extensions Accept only RFC JSON syntax.
   --  @enum Comments Also accept line and non-nested block comments as trivia.
   --  @enum Trailing_Commas Also accept a trailing comma in a nonempty container.
   --  @enum Comments_And_Trailing_Commas Accept both documented extensions.
   type Compatibility_Mode is
     (No_Extensions, Comments, Trailing_Commas, Comments_And_Trailing_Commas);

   type Parser_State is (Uninitialized, Ready, Active, Failure_Pending, Completed, Failed, Aborted);

   type Event_Kind is
     (Document_Begin,
      Document_End,
      Object_Begin,
      Object_End,
      Array_Begin,
      Array_End,
      Name_Begin,
      Name_Fragment,
      Name_End,
      String_Begin,
      String_Fragment,
      String_End,
      Number_Begin,
      Number_Fragment,
      Number_End,
      Null_Value,
      Boolean_Value);

   type Chunk_Range is record
      First_Count  : Ada.Streams.Stream_Element_Count;
      Octet_Length : Ada.Streams.Stream_Element_Count;
   end record;

   type Source_Range is record
      First        : Byte_Offset;
      Octet_Length : Byte_Offset;
   end record;

   type Decoded_Fragment_Kind is (No_Decoded_Fragment, Decoded_Is_Raw_Range, Decoded_Inline_Scalar);

   --  No_Decoded_Fragment covers transport pieces that do not yet complete a
   --  scalar and a complete scalar whose caller-backed name storage was
   --  denied.  In the latter case State is Failure_Pending and the next Next
   --  reports the retained terminal diagnostic without consuming input.

   type Inline_Scalar is record
      Length : Natural range 0 .. Parser_UTF8.Scalar_Octets'Length;
      Octets : Parser_UTF8.Scalar_Octets;
   end record;

   type Event is record
      Kind           : Event_Kind;
      Source         : Source_Range;
      Has_Raw_Slice  : Boolean;
      --  Raw_Slice is meaningful only for the exact Input array passed to the
      --  parser call (Next or Drain) that returned this event.  The parser
      --  retains no Input.  Raw_Slice is meaningful only when Has_Raw_Slice.
      Raw_Slice      : Chunk_Range;
      Decoded_Kind   : Decoded_Fragment_Kind;
      --  Decoded_Source is meaningful for Decoded_Is_Raw_Range and
      --  Decoded_Inline_Scalar.  Decoded is meaningful only for
      --  Decoded_Inline_Scalar.  Ineligible fields are valid but unspecified
      --  and must not be observed by consumers.
      Decoded_Source : Source_Range;
      Decoded        : Inline_Scalar;
      --  Boolean_Data is meaningful only for Boolean_Value.
      Boolean_Data   : Boolean;
   end record;

   type Error_Code is
     (No_Error,
      Invalid_State,
      Unexpected_Token,
      Top_Level_Kind_Rejected,
      Trailing_Input,
      Truncated_Input,
      Invalid_Literal,
      Invalid_Number,
      Invalid_UTF8,
      Invalid_Escape,
      Invalid_Surrogate,
      Raw_Control_Character,
      Duplicate_Name,
      Depth_Exhausted,
      Name_Storage_Exhausted,
      Duplicate_Index_Exhausted,
      Offset_Exhausted,
      Final_Input_Retracted);

   type Diagnostic is record
      Code   : Error_Code;
      Offset : Byte_Offset;
   end record;

   type Next_Outcome is (Event_Ready, Need_Input, Document_Complete, Parse_Failed, Call_Rejected);

   type Next_Result is record
      Outcome    : Next_Outcome;
      Input_First : Byte_Offset;
      Consumed   : Ada.Streams.Stream_Element_Count;
      Item       : Event;
      Diagnostic : Parser_Core.Diagnostic;
   end record;

   type Event_Array is array (Ada.Streams.Stream_Element_Offset range <>) of Event;

   type Drain_Stop is
     (Drain_Buffer_Full, Drain_Need_Input, Drain_Document_Complete, Drain_Parse_Failed, Drain_Call_Rejected);

   type Drain_Result is record
      Stop       : Drain_Stop;
      Input_First : Byte_Offset;
      Consumed   : Ada.Streams.Stream_Element_Count;
      Produced   : Ada.Streams.Stream_Element_Count;
      Diagnostic : Parser_Core.Diagnostic;
   end record;

   type Parser
     (Maximum_Depth       : Natural;
      Name_Octet_Capacity : Natural;
      Name_Capacity       : Natural;
      Duplicate_Handling  : Duplicate_Mode)
   is
     limited private;

   --  Initialize changes an Uninitialized parser to Ready.  In another state
   --  it is a nonraising no-op.
   procedure Initialize (Self : in out Parser);

   --  Freeze the top-level policy for this operation.  Root-policy rejection
   --  occurs before consuming the first non-whitespace root octet.
   procedure Initialize (Self : in out Parser; Top_Level : Root_Policy);

   --  Freeze both root and nonstandard-input policies for this operation.
   --  @param Self Parser whose operation is initialized.
   --  @param Top_Level Required root shape.
   --  @param Compatibility Exact extension family admitted by the operation.
   procedure Initialize
     (Self : in out Parser; Top_Level : Root_Policy; Compatibility : Compatibility_Mode);

   --  Return exactly one event, Need_Input, completion, or failure.  Consumed
   --  is always a count from Input'First and never an Ada array index.  Item is
   --  meaningful only for Event_Ready.  A raw slice is borrowed from this
   --  exact call.  Inline decoded scalar data is stored in the returned event.
   procedure Next
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Result       : out Next_Result);

   --  Fill the caller's event array until it is full or parsing stops for
   --  input, completion, or failure.  Consumed is a count from Input'First,
   --  and every raw slice in the produced prefix refers to this exact Input.
   --  Only the first Produced components of Events are meaningful.
   --  Produced events remain provisional when the same call reports failure.
   --  A null Events array returns Drain_Buffer_Full without changing Self.
   procedure Drain
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Events       : out Event_Array;
      Result       : out Drain_Result);

   --  Unstable internal performance descriptor.  It makes no layout or ABI
   --  promise and is not a public parser event type.
   type Buffered_Event is private;

   type Buffered_Event_Array is array (Ada.Streams.Stream_Element_Offset range <>) of Buffered_Event;

   type Buffered_Drain_Result is record
      Stop        : Drain_Stop;
      Input_First : Byte_Offset;
      Consumed    : Ada.Streams.Stream_Element_Count;
      Produced    : Ada.Streams.Stream_Element_Count;
      Diagnostic  : Parser_Core.Diagnostic;
   end record;

   --  Buffered_Drain has the same parsing, stop, and consumed-count semantics
   --  as Drain.  Input_First is the parser's absolute byte offset before this
   --  call.  Only the first Produced components of Events are meaningful;
   --  their source ranges are absolute, while any raw text remains in this
   --  exact Input.  The descriptor retains no Input reference; source text may
   --  be resolved only against this exact actual while the caller keeps it
   --  alive and unchanged, and must be copied before that actual is released
   --  or reused.  A null Events array returns Drain_Buffer_Full without
   --  changing Self.
   procedure Buffered_Drain
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Events       : out Buffered_Event_Array;
      Result       : out Buffered_Drain_Result);

   generic
      type Output_Event is private;
      type Output_Event_Array is
        array (Ada.Streams.Stream_Element_Offset range <>) of Output_Event;
      with function Convert (Item : Buffered_Event) return Output_Event;
   procedure Generic_Drain
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Events       : out Output_Event_Array;
      Result       : out Buffered_Drain_Result);

   --  Generic_Drain invokes Convert exactly once for each published event and
   --  writes directly into Events through the same Run engine as Next and
   --  Buffered_Drain.  A null Events array is a nonmutating capacity stop.

   function Buffered_Kind (Item : Buffered_Event) return Event_Kind;

   function Empty_Buffered return Buffered_Event;

   function Buffered_Source (Item : Buffered_Event) return Source_Range;

   function Buffered_Has_Raw_Slice (Item : Buffered_Event) return Boolean;

   type Buffered_Slice_Status is (Slice_Resolved, No_Raw_Slice, Range_Outside_Window);

   --  Resolve a raw range only against the exact unchanged Input actual from
   --  the Buffered_Drain call that returned Item.  Input_First is that call's
   --  Buffered_Drain_Result.Input_First and Input_Length is Input'Length.  A
   --  noncontaining coordinate window returns zero counts without raising;
   --  coordinate containment cannot establish array identity or staleness.
   procedure Resolve_Buffered_Raw_Range
     (Item         : Buffered_Event;
      Input_First  : Byte_Offset;
      Input_Length : Ada.Streams.Stream_Element_Count;
      Slice        : out Chunk_Range;
      Status       : out Buffered_Slice_Status);

   function Buffered_Decoded_Kind (Item : Buffered_Event) return Decoded_Fragment_Kind;

   --  Eligible only when Buffered_Decoded_Kind is not No_Decoded_Fragment.
   function Buffered_Decoded_Source (Item : Buffered_Event) return Source_Range;

   --  Eligible only when Buffered_Decoded_Kind is Decoded_Inline_Scalar.
   function Buffered_Decoded_Scalar (Item : Buffered_Event) return Inline_Scalar;

   --  Eligible only when Buffered_Kind is Boolean_Value.
   function Buffered_Boolean_Data (Item : Buffered_Event) return Boolean;

   pragma Inline_Always (Buffered_Kind);
   pragma Inline_Always (Buffered_Source);
   pragma Inline_Always (Buffered_Has_Raw_Slice);
   pragma Inline_Always (Resolve_Buffered_Raw_Range);
   pragma Inline_Always (Buffered_Decoded_Kind);
   pragma Inline_Always (Buffered_Decoded_Source);
   pragma Inline_Always (Buffered_Decoded_Scalar);
   pragma Inline_Always (Buffered_Boolean_Data);

   procedure Abort_Document (Self : in out Parser);

   --  Reset creates a fresh Ready operation from Failure_Pending, Completed,
   --  Failed, or Aborted.  In another state it is a nonraising no-op.
   procedure Reset (Self : in out Parser);

   --  Reset a terminal parser and freeze a new top-level policy.  In another
   --  state it is a nonraising no-op.
   procedure Reset (Self : in out Parser; Top_Level : Root_Policy);

   --  Start a new operation with explicitly selected root and extension
   --  policies after a terminal parser state.
   --  @param Self Parser whose terminal operation is discarded.
   --  @param Top_Level Required root shape for the new operation.
   --  @param Compatibility Exact extension family for the new operation.
   procedure Reset
     (Self : in out Parser; Top_Level : Root_Policy; Compatibility : Compatibility_Mode);

   function State (Self : Parser) return Parser_State;

   function Terminal_Diagnostic (Self : Parser) return Diagnostic
   with Pre => State (Self) in Failure_Pending | Failed | Aborted;

private

   --  The packed metadata widths are derived from existing JSON/UTF-8
   --  mechanics, not caller policy: three decoded kinds need two bits, a
   --  UTF-8 scalar has at most four octets and needs three length bits, and
   --  the longest decoded JSON escape is a 12-octet surrogate pair and needs
   --  four length bits.  Source is kept naturally aligned; this currently
   --  yields a 24-octet native descriptor without making that size a contract.
   type Buffered_Event is record
      Kind          : Event_Kind;
      Metadata      : Interfaces.Unsigned_16;
      Scalar_Octets : Parser_UTF8.Scalar_Octets;
      Source        : Source_Range;
   end record;

   type Container_Kind is (Array_Container, Object_Container);

   type Container_Phase is
     (Array_First_Or_End,
      Array_Value,
      Array_Comma_Or_End,
      Object_First_Or_End,
      Object_Name,
      Object_Colon,
      Object_Value,
      Object_Comma_Or_End);

   type Phase_Array is array (Positive range <>) of Container_Phase;

   type Duplicate_Context_Array is
     array (Positive range <>) of Parser_Duplicates.Object_Context;

   type Token_Kind is (No_Token, Number_Token, Null_Token, True_Token, False_Token, Name_Token, String_Token);

   type Text_Scan_State is
     (Text_Content, Text_After_Escape, Text_Unicode_Digits, Text_Low_Backslash, Text_Low_U, Text_Low_Digits);

   type Trivia_State is
     (No_Comment, Comment_Opening, Line_Comment, Block_Comment, Block_After_Star);

   type Parser
     (Maximum_Depth       : Natural;
      Name_Octet_Capacity : Natural;
      Name_Capacity       : Natural;
      Duplicate_Handling  : Duplicate_Mode)
   is limited record
      Current_State         : Parser_State := Uninitialized;
      Last_Diagnostic       : Diagnostic := (Code => No_Error, Offset => 0);
      Next_Offset           : Byte_Offset := 0;
      Depth                 : Natural := 0;
      Stack                 : Phase_Array (1 .. Maximum_Depth);
      Applied_Root_Policy   : Root_Policy := Accept_Any;
      Applied_Compatibility : Compatibility_Mode := No_Extensions;
      Final_Input_Seen      : Boolean := False;
      Root_Started          : Boolean := False;
      Root_Complete         : Boolean := False;
      Document_End_Sent     : Boolean := False;
      Token                 : Token_Kind := No_Token;
      Token_Start           : Byte_Offset := 0;
      Number                : Parser_Numbers.Number_State;
      --  Text tokens and comments cannot overlap.  They therefore share one
      --  decoder, avoiding comment-only state in every strict parser object.
      UTF8                  : Parser_UTF8.Decoder;
      UTF8_Lead_Offset      : Byte_Offset := 0;
      Trivia                : Trivia_State := No_Comment;
      Text_State            : Text_Scan_State := Text_Content;
      Text_Escape_Start     : Byte_Offset := 0;
      Text_High_Start       : Byte_Offset := 0;
      Text_Hex_Value        : Interfaces.Unsigned_32 := 0;
      Text_Hex_Digits       : Natural range 0 .. 4 := 0;
      Text_High_Surrogate   : Interfaces.Unsigned_32 := 0;
      Literal_Position      : Natural := 0;
      Literal_Can_Slice     : Boolean := False;
      Literal_First_Count   : Ada.Streams.Stream_Element_Count := 0;
      case Duplicate_Handling is
         when Reject_Duplicates  =>
            Duplicate_Names    : Parser_Duplicates.Index (Name_Octet_Capacity, Name_Capacity);
            Duplicate_Contexts : Duplicate_Context_Array (1 .. Maximum_Depth);

         when Preserve_Unchecked =>
            null;
      end case;
   end record;

end Flyology_JSON.Parser_Core;
