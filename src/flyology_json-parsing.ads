with Ada.Streams;
with Flyology_JSON.Errors;
private with Flyology_JSON.Parser_Core;
with Flyology_JSON.Profiles;

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

   --  The event grammar is:
   --
   --    Document_Begin, value, Document_End
   --    value = object | array | string | number | Null_Value | Boolean_Value
   --    object = Object_Begin,
   --             {Name_Begin, Name_Fragment*, Name_End, value}*,
   --             Object_End
   --    array  = Array_Begin, value*, Array_End
   --    string = String_Begin, String_Fragment*, String_End
   --    number = Number_Begin, Number_Fragment*, Number_End
   --
   --  Events never imply container lengths or Serde semantics.  Every event is
   --  provisional until Document_Complete.  Number fragments preserve exact
   --  input octets; conversion is a separate checked operation.

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
     (Item          : Event;
      Window_Origin : Byte_Offset;
      Window_Length : Ada.Streams.Stream_Element_Count;
      Slice         : out Chunk_Range;
      Status        : out Slice_Status);

   --  Source is the complete lexical provenance of the event.  Has_Raw_Slice
   --  means that Source is wholly contained in the exact producing input
   --  window.  It is always true for structural punctuation, name/string
   --  begin and end events, and number fragments.  It is conditional for a
   --  null or Boolean literal that crossed calls, and false for document
   --  begin/end and zero-length number begin/end events.

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

   --  Decoded_Kind is meaningful only for Name_Fragment and String_Fragment.
   --  No_Decoded_Fragment carries no decoded payload.  Decoded_Is_Raw_Range
   --  identifies exactly Source and must be observed against the producing
   --  input.  Decoded_Inline_Scalar carries exactly one complete Unicode
   --  scalar in Octets (1 .. Length); the remaining octets are unspecified.
   --  Decoded_Source is the complete source range of that decoded fragment and
   --  may begin in an earlier input call.

   --  These unguarded hot accessors can be forced inline on every supported
   --  GNAT.  Guarded payload accessors retain enforceable preconditions and
   --  therefore use regular Inline for GNAT 13 compatibility.
   pragma Inline_Always (Kind);
   pragma Inline_Always (Source);
   pragma Inline_Always (Has_Raw_Slice);
   pragma Inline_Always (Resolve_Raw_Range);
   pragma Inline_Always (Decoded_Kind);

   type Step_Outcome is
     (Event_Ready, Need_Input, Document_Complete, Step_Failed, Call_Rejected);

   --  This result is definite: passing a constrained actual cannot raise when
   --  Step returns another outcome.  Item is eligible only for Event_Ready;
   --  Diagnostic only for Step_Failed or Call_Rejected.  Input_Origin is the
   --  operation's absolute next byte before the call and Consumed is a count
   --  from Input'First.  Need_Input consumes all supplied input.  Every
   --  rejected call consumes zero.
   type Step_Result is record
      Outcome      : Step_Outcome;
      Input_Origin : Byte_Offset;
      Consumed     : Ada.Streams.Stream_Element_Count;
      Item         : Event;
      Diagnostic   : Errors.Diagnostic;
   end record;

   type Drain_Stop is
     (Output_Full, Drain_Need_Input, Drain_Document_Complete, Drain_Failed, Drain_Rejected);

   --  This result is definite.  Diagnostic is eligible only for Drain_Failed
   --  or Drain_Rejected; other fields are eligible for every stop.
   --  Input_Origin is the operation's absolute next byte before the call,
   --  Consumed is a count from Input'First, and Produced is a count from
   --  Events'First.  A nonnull Output_Full result publishes exactly
   --  Events'Length events.  Every rejected call consumes and produces zero.
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
   --  a root container is depth one, nested containers add one, and a scalar
   --  root needs depth zero.  A denied opener is neither consumed nor
   --  published and is reported at that opener.
   --
   --  The two name capacities are ignored in Preserve_Unchecked and may be
   --  zero.  Preserve_Unchecked publishes every member in source order and
   --  performs no duplicate storage, comparison, or selection.  In
   --  Reject_Duplicates, Name_Octet_Capacity bounds the total decoded
   --  UTF-8 octets of unique names retained by all simultaneously open objects
   --  plus the active candidate.  Closing an object releases storage acquired
   --  since its opener.  A duplicate candidate is reclaimed at detection.
   --  Storage denial consumes and publishes the completed scalar's final
   --  raw-only provisional source piece or pieces, publishes no decoded scalar,
   --  and enters Failure_Pending.  An underfull Drain reports
   --  Name_Storage_Exhausted in that call while retaining its provisional
   --  prefix and prior consumption.  If Step returned the raw-only piece or a
   --  Drain filled its output, the next admitted call reports the failure with
   --  zero consumption and publication.  The active name's opening quote is
   --  blamed.
   --
   --  Name_Capacity independently bounds retained crit-bit leaves and internal
   --  nodes across simultaneously open objects.  One unique name consumes one
   --  leaf and, unless first in that object, one node.  The active candidate
   --  consumes neither until Name_End.  Capacity zero denies a strict name
   --  before its opening quote is consumed or published.  An exact-fit unique
   --  name succeeds.  The next unique name needing an unavailable leaf or node
   --  consumes the closing quote, fails at Name_End, publishes no Name_End,
   --  and reports Duplicate_Index_Exhausted at its opening quote.  Exact
   --  duplicates are detected before unique-name index reservation and
   --  therefore win over an otherwise simultaneous index denial.  Detection
   --  occurs at Name_End; no Name_End event is published and the later opening
   --  quote is blamed.
   --  For decoded candidate length L, retained-node count K, and compared leaf
   --  length E, completion performs at most two K-node bit-probe descents, one
   --  comparison of the eight-octet length prefix plus max (L, E) content
   --  octets, and eight bit tests in the first differing octet.  Appending the
   --  candidate performs exactly L octet stores.  K is at most Name_Capacity;
   --  L and E are at most Name_Octet_Capacity.  There is no scan over all prior
   --  names and no collision-only or quadratic fallback.
   --
   --  Profile must select the package's Duplicate_Mode.  Unsupported,
   --  mismatched, or incompatible profiles fail before byte zero.  Under
   --  Require_Object, a recognized array, string, number, Boolean, or null root
   --  leader is rejected before that leader is consumed or its token contents
   --  are validated.  A byte that cannot lead any JSON value remains
   --  Unexpected_Token rather than a top-level-kind rejection.
   procedure Initialize
     (Self : in out Parser; Profile : Profiles.Parser_Profile; Diagnostic : out Errors.Diagnostic);

   procedure Step
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Result       : out Step_Result);

   --  An admitted true End_Of_Input is latched even when Step returns an event
   --  before reaching the terminal result.  Every later suffix call must keep
   --  it true.  Retraction is rejected with Final_Input_Retracted at the
   --  current source byte and zero consumption.

   --  Fill only the first Result.Produced components.  Every borrowed range
   --  refers to this exact Input.  A null Events array returns Output_Full,
   --  zero consumed/produced, and leaves Self unchanged, before lifecycle or
   --  finality checks.  Otherwise Drain shares Step's engine and finality
   --  latch.  Filling Events takes precedence over a later pending terminal
   --  result; the next call reports that result.
   procedure Drain
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Events       : out Event_Array;
      Result       : out Drain_Result);

   procedure Abort_Document (Self : in out Parser);

   procedure Reset
     (Self : in out Parser; Profile : Profiles.Parser_Profile; Diagnostic : out Errors.Diagnostic);

   --  Closed lifecycle:
   --
   --  * Initialize is admitted only in Uninitialized.  A valid matching
   --    profile enters Ready; rejection enters Failed without an applied
   --    profile and before byte zero.  Elsewhere it is nonmutating and reports
   --    Invalid_State, except that a retained failure remains primary.
   --  * Step and nonnull Drain are admitted only in Ready, Active, or
   --    Failure_Pending.  The first call enters Active.  Failure_Pending
   --    reports the retained primary with zero publication and enters Failed.
   --    Other states reject without effects; Failed returns its retained
   --    primary while the other rejected states return Invalid_State.
   --  * Document_Complete follows Document_End, enters Completed, and is the
   --    only complete-document acceptance gate.
   --  * Abort_Document maps Ready or Active to clean Aborted; maps
   --    Failure_Pending to Failed while retaining its primary; and is an
   --    idempotent no-op in Uninitialized, Completed, Failed, or Aborted.
   --  * Reset is admitted only in Failure_Pending, Completed, Failed, or
   --    Aborted.  A valid matching profile starts a fresh Ready operation at
   --    byte zero.  An invalid profile enters Failed without an applied
   --    profile, also at byte zero.  Other states reject without mutation and
   --    cannot replace a retained primary.
   --
   --  Has_Applied_Profile remains true after successful initialization through
   --  Active, Failure_Pending, Completed, Failed, and Aborted.  A clean abort
   --  has a cleared terminal diagnostic.  Reset never changes caller-owned
   --  storage capacities.

   function State (Self : Parser) return Parser_State;

   function Has_Applied_Profile (Self : Parser) return Boolean;

   function Applied_Profile (Self : Parser) return Profiles.Parser_Profile
   with Pre => Has_Applied_Profile (Self);

   function Terminal_Diagnostic (Self : Parser) return Errors.Diagnostic
   with Pre => State (Self) in Failure_Pending | Failed | Aborted;

private
   type Event is new Parser_Core.Buffered_Event;

   type Parser
     (Maximum_Depth       : Natural;
      Name_Octet_Capacity : Natural;
      Name_Capacity       : Natural)
   is limited record
      Core_Data :
        Parser_Core.Parser
          (Maximum_Depth,
           Name_Octet_Capacity,
           Name_Capacity,
           (case Duplicate_Mode is
              when Profiles.Reject_Duplicates  => Parser_Core.Reject_Duplicates,
              when Profiles.Preserve_Unchecked => Parser_Core.Preserve_Unchecked));
      Current_State        : Parser_State := Uninitialized;
      Has_Profile          : Boolean := False;
      Core_Initialized     : Boolean := False;
      Next_Origin          : Byte_Offset := 0;
      Applied_Profile_Data : Profiles.Parser_Profile;
      Last_Diagnostic      : Errors.Diagnostic :=
        (Code                 => Errors.No_Error,
         Coordinate           => Errors.No_Coordinate,
         Offset               => 0,
         Secondary            => Errors.No_Error,
         Secondary_Coordinate => Errors.No_Coordinate,
         Secondary_Offset     => 0);
   end record;
end Flyology_JSON.Parsing;
