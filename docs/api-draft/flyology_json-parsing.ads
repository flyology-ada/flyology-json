with Ada.Streams;
with Flyology_JSON.Errors;
with Flyology_JSON.Profiles;
with Interfaces;

--  Trusted, allocation-free incremental parser.  Duplicate_Mode is a static
--  selection with no default.  This package contains no accounting state,
--  callback, hook, or observational counter.

generic
   Duplicate_Mode : Profiles.Duplicate_Policy;
package Flyology_JSON.Parsing is
   subtype Byte_Offset is Errors.Byte_Offset;

   type Parser_State is (Uninitialized, Ready, Active, Completed, Failed, Aborted);

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

   type Source_Range is record
      First        : Byte_Offset;
      Octet_Length : Byte_Offset;
   end record;

   type Chunk_Range is record
      First_Count  : Ada.Streams.Stream_Element_Count;
      Octet_Length : Ada.Streams.Stream_Element_Count;
   end record;

   type Decoded_Fragment_Kind is
     (No_Decoded_Fragment, Decoded_Is_Raw_Range, Decoded_Inline_Scalar);

   --  RFC 3629 fixes four as the maximum UTF-8 scalar width.
   type Scalar_Octets is array (Positive range 1 .. 4) of Ada.Streams.Stream_Element;

   type Inline_Scalar is record
      Length : Natural range 0 .. Scalar_Octets'Length;
      Octets : Scalar_Octets;
   end record;

   --  Event is a compact value with no public size, packing, layout, or ABI
   --  promise.  A copied event retains absolute source coordinates and inline
   --  scalar data, but never retains parser input.
   type Event is private;

   type Event_Array is array (Ada.Streams.Stream_Element_Offset range <>) of Event;

   function Kind (Item : Event) return Event_Kind;

   function Source (Item : Event) return Source_Range;

   function Has_Raw_Slice (Item : Event) return Boolean;

   type Slice_Status is (Slice_Resolved, No_Raw_Slice, Wrong_Input_Window);

   --  Resolve the borrowed raw range only against the exact unchanged Input
   --  actual from the call that returned Item.  Input_Origin is that call's
   --  absolute input position and Input_Length is Input'Length.  The result is
   --  a count from Input'First.  A wrong window returns status without raising
   --  and clears Slice to zero counts.
   procedure Resolve_Raw_Slice
     (Item         : Event;
      Input_Origin : Byte_Offset;
      Input_Length : Ada.Streams.Stream_Element_Count;
      Slice        : out Chunk_Range;
      Status       : out Slice_Status);

   function Decoded_Kind (Item : Event) return Decoded_Fragment_Kind;

   function Decoded_Source (Item : Event) return Source_Range
   with Pre => Decoded_Kind (Item) /= No_Decoded_Fragment;

   function Decoded_Scalar (Item : Event) return Inline_Scalar
   with Pre => Decoded_Kind (Item) = Decoded_Inline_Scalar;

   function Boolean_Data (Item : Event) return Boolean
   with Pre => Kind (Item) = Boolean_Value;

   type Step_Outcome is (Event_Ready, Need_Input, Document_Complete, Step_Failed, Call_Rejected);

   type Step_Result (Outcome : Step_Outcome := Need_Input) is record
      Input_Origin : Byte_Offset;
      Consumed     : Ada.Streams.Stream_Element_Count;
      case Outcome is
         when Event_Ready =>
            Item : Event;
         when Step_Failed | Call_Rejected =>
            Diagnostic : Errors.Diagnostic;
         when Need_Input | Document_Complete =>
            null;
      end case;
   end record;

   type Drain_Stop is (Output_Full, Drain_Need_Input, Drain_Document_Complete, Drain_Failed, Drain_Rejected);

   type Drain_Result (Stop : Drain_Stop := Drain_Need_Input) is record
      Input_Origin : Byte_Offset;
      Consumed     : Ada.Streams.Stream_Element_Count;
      Produced     : Ada.Streams.Stream_Element_Count;
      case Stop is
         when Drain_Failed | Drain_Rejected =>
            Diagnostic : Errors.Diagnostic;
         when Output_Full | Drain_Need_Input | Drain_Document_Complete =>
            null;
      end case;
   end record;

   type Parser
     (Maximum_Depth       : Natural;
      Name_Octet_Capacity : Natural;
      Name_Capacity       : Natural)
   is limited private;

   --  Profile must select the package's Duplicate_Mode.  Unsupported,
   --  mismatched, or incompatible profiles fail before byte zero.
   procedure Initialize
     (Self : in out Parser; Profile : Profiles.Parser_Profile; Diagnostic : out Errors.Diagnostic);

   procedure Step
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Result       : out Step_Result);

   --  Fill only the first Result.Produced components.  Every borrowed range
   --  refers to this exact Input.  A null Events array returns Output_Full,
   --  zero consumed/produced, and leaves Self unchanged.
   procedure Drain
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Events       : out Event_Array;
      Result       : out Drain_Result);

   procedure Abort_Document (Self : in out Parser);

   procedure Reset
     (Self : in out Parser; Profile : Profiles.Parser_Profile; Diagnostic : out Errors.Diagnostic);

   function State (Self : Parser) return Parser_State;

   function Has_Applied_Profile (Self : Parser) return Boolean;

   function Applied_Profile (Self : Parser) return Profiles.Parser_Profile
   with Pre => Has_Applied_Profile (Self);

   function Terminal_Diagnostic (Self : Parser) return Errors.Diagnostic
   with Pre => State (Self) in Failed | Aborted;

private
   type Event is record
      Event_Kind_Data : Event_Kind;
      Metadata        : Interfaces.Unsigned_16;
      Scalar_Data     : Scalar_Octets;
      Source_Data     : Source_Range;
   end record;

   type Parser
     (Maximum_Depth       : Natural;
      Name_Octet_Capacity : Natural;
      Name_Capacity       : Natural)
   is limited record
      Placeholder : Boolean := False;
   end record;
end Flyology_JSON.Parsing;
