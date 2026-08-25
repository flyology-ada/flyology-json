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

   type Parser_State is
     (Uninitialized, Ready, Active, Failure_Pending, Completed, Failed, Aborted);

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

   --  RFC 3629 fixes four as the maximum UTF-8 scalar width.  This is a
   --  constrained subtype of the common octet-array type so callers can pass
   --  a decoded prefix directly to collector, writer, or numeric APIs.
   subtype Scalar_Octets is
     Ada.Streams.Stream_Element_Array
       (Ada.Streams.Stream_Element_Offset range 1 .. 4);

   type Inline_Scalar is record
      Length : Positive range 1 .. Scalar_Octets'Length;
      Octets : Scalar_Octets;
   end record;

   --  Event is a compact value with no public size, packing, layout, or ABI
   --  promise.  A copied event retains absolute source coordinates and inline
   --  scalar data, but never retains parser input.
   type Event is private;

   type Event_Array is array (Ada.Streams.Stream_Element_Offset range <>) of Event;

   function Kind (Item : Event) return Event_Kind
   with Inline;

   function Source (Item : Event) return Source_Range
   with Inline;

   function Has_Raw_Slice (Item : Event) return Boolean
   with Inline;

   type Slice_Status is (Slice_Resolved, No_Raw_Slice, Range_Outside_Window);

   --  Map Item's absolute raw coordinates into a caller-described input
   --  window.  This validates coordinate containment only; it does not and
   --  cannot authenticate an Ada array's identity or contents.  The caller
   --  supplies the exact unchanged Input actual from the producing Step/Drain
   --  call.  The result is a count from that Input's First.  A missing or
   --  outside range returns zero counts without raising.
   procedure Resolve_Raw_Range
     (Item         : Event;
      Window_Origin : Byte_Offset;
      Window_Length : Ada.Streams.Stream_Element_Count;
      Slice        : out Chunk_Range;
      Status       : out Slice_Status);

   function Decoded_Kind (Item : Event) return Decoded_Fragment_Kind
   with Inline;

   function Decoded_Source (Item : Event) return Source_Range
   with Pre => Decoded_Kind (Item) /= No_Decoded_Fragment,
        Inline;

   function Decoded_Scalar (Item : Event) return Inline_Scalar
   with Pre => Decoded_Kind (Item) = Decoded_Inline_Scalar,
        Inline;

   function Boolean_Data (Item : Event) return Boolean
   with Pre => Kind (Item) = Boolean_Value,
        Inline;

   type Step_Outcome is (Event_Ready, Need_Input, Document_Complete, Step_Failed, Call_Rejected);

   --  This result is definite: passing a constrained actual cannot raise when
   --  Step returns another outcome.  Item is eligible only for Event_Ready;
   --  Diagnostic only for Step_Failed or Call_Rejected.
   type Step_Result is record
      Outcome      : Step_Outcome;
      Input_Origin : Byte_Offset;
      Consumed     : Ada.Streams.Stream_Element_Count;
      Item         : Event;
      Diagnostic   : Errors.Diagnostic;
   end record;

   type Drain_Stop is (Output_Full, Drain_Need_Input, Drain_Document_Complete, Drain_Failed, Drain_Rejected);

   --  This result is definite.  Diagnostic is eligible only for Drain_Failed
   --  or Drain_Rejected; other fields are eligible for every stop.
   type Drain_Result is record
      Stop         : Drain_Stop;
      Input_Origin : Byte_Offset;
      Consumed     : Ada.Streams.Stream_Element_Count;
      Produced     : Ada.Streams.Stream_Element_Count;
      Diagnostic   : Errors.Diagnostic;
   end record;

   type Parser
     (Maximum_Depth       : Natural;
      Name_Octet_Capacity : Natural;
      Name_Capacity       : Natural)
   is limited private;

   --  Maximum_Depth counts simultaneously open object and array containers;
   --  a root container is depth one, while a scalar root needs depth zero.
   --  The two name capacities are ignored in Preserve_Unchecked and may be
   --  zero.  Their strict-mode storage units and release points are normative
   --  parts of the package contract.
   --
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
   with Pre => State (Self) in Failure_Pending | Failed | Aborted;

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
