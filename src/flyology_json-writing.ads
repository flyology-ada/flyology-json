with Ada.Finalization;
with Ada.Streams;
with Flyology_JSON.Destinations;
with Flyology_JSON.Errors;
with Flyology_JSON.Profiles;
private with Flyology_JSON.Writer_Core;

--  Trusted transactional streaming writer. The destination stages one whole
--  document and publishes only through Commit. There is no accounting state,
--  hook, nullable budget, accounting branch, or public capacity default.

generic
   --  Caller-owned staging destination type. The destination object outlives
   --  the writer bound to it.
   type Destination_Type is limited private;

   --  Begin is synchronous, nonraising, finite, and nonreentrant. A successful
   --  return starts exactly one unpublished transaction. A failed return starts
   --  none. The writer protects this ownership boundary from task abort.
   --  @param Target Caller-owned destination that starts staging.
   --  @param Status Whether a transaction was started and is now owned by the writer.
   with
     procedure Destination_Begin (Target : in out Destination_Type; Status : out Destinations.Begin_Status);

   --  Write is synchronous, finite, nonreentrant, retains no reference to Data,
   --  and does not access a writer alias. On normal return, Write_Succeeded
   --  accepts all Data; Write_Exhausted
   --  accepts the exact longest prefix; Write_Failed accepts none. Written is
   --  a count rather than an Ada index.
   --
   --  On abnormal completion, Write may have staged an in-order prefix of Data
   --  from zero through Data'Length. That prefix remains unpublished, Data is
   --  not retained, and one coherent transaction remains abortable.
   --  @param Target Destination whose active transaction receives the span.
   --  @param Data Arbitrary-bound octet span retained only for this call.
   --  @param Written Count of accepted components beginning at `Data'First`.
   --  @param Status Complete acceptance, exact-prefix exhaustion, or no-prefix failure.
   with
     procedure Destination_Write
       (Target  : in out Destination_Type;
        Data    : Ada.Streams.Stream_Element_Array;
        Written : out Ada.Streams.Stream_Element_Count;
        Status  : out Destinations.Write_Status);

   --  Commit is synchronous, nonraising, finite, and nonreentrant. Success is
   --  the only publication point. Failure publishes nothing and leaves the
   --  transaction abortable. The writer protects publication and its ownership
   --  transition from task abort.
   --  @param Target Destination whose complete staged document may be published.
   --  @param Status Whether the whole document was published.
   with
     procedure Destination_Commit (Target : in out Destination_Type; Status : out Destinations.Commit_Status);

   --  Abort is synchronous, nonraising, finite, and nonreentrant. It ends the
   --  active unpublished transaction and never publishes, even when Status is
   --  Abort_Failed. The writer protects abort and exactly-once bookkeeping from
   --  task abort.
   --  @param Target Destination whose unpublished transaction must end.
   --  @param Status Cleanup result; the transaction ends for either value.
   with
     procedure Destination_Abort (Target : in out Destination_Type; Status : out Destinations.Abort_Status);
package Flyology_JSON.Writing is
   --  Emits ordinary compact JSON through one caller-owned destination transaction.
   --  @formal Destination_Type Caller-owned whole-document staging destination.
   --  @formal Destination_Begin Starts one unpublished whole-document transaction.
   --  @formal Destination_Write Stages a complete span or its exact longest available prefix.
   --  @formal Destination_Commit Publishes the complete staged document.
   --  @formal Destination_Abort Ends unpublished staging without publication.

   --  Initialize freezes one explicit validated profile before destination
   --  begin. Begin_Document starts one transaction. The JSON calls then emit
   --  exactly one balanced root; Finish_Document is the only commit request.
   --  Calls in Ready are ordinal-bearing grammar failures except
   --  Begin_Document. Calls rejected only for lifecycle state have no output or
   --  ordinal effect. Reset accepts only Completed, Failed, or Aborted.
   --
   --  Name and string fragments are decoded UTF-8 octets and may split inside
   --  a UTF-8 sequence. Number fragments preserve and validate exact JSON
   --  lexeme octets. Their array bounds are arbitrary. Token, staged-output,
   --  and call-ordinal diagnostics are zero-based aggregates across fragments.
   --
   --  An abnormal escape from a hot JSON call exposes Interrupted after the
   --  borrowed call has joined. The owner must call Abort_Document or leave the
   --  writer scope before any other use, even if asynchronous transfer won at
   --  a return edge and State appears coherent. Terminal_Diagnostic is eligible
   --  only in Interrupted, Failed, or Aborted. A boundary formal that violates
   --  its nonraising contract is re-raised; the caller immediately unwinds the
   --  writer scope without querying or reusing it.

   --  Lifecycle state of one transactional writer operation.
   --  @enum Uninitialized No writer profile has been validated or applied.
   --  @enum Ready A profile is frozen and no destination transaction is active.
   --  @enum Active One unpublished destination transaction is active.
   --  @enum Interrupted An abnormal transfer escaped a writer call; abort is required.
   --  @enum Completed The destination published one complete document.
   --  @enum Failed The operation ended with a retained primary diagnostic.
   --  @enum Aborted The unpublished transaction ended without publication.
   type Writer_State is (Uninitialized, Ready, Active, Interrupted, Completed, Failed, Aborted);

   --  Allocation-free writer state bound to one caller-owned destination.
   --  @field Target Nonnull destination object that outlives the writer.
   --  @field Maximum_Depth Maximum simultaneously open object and array containers.
   type Writer
     (Target        : not null access Destination_Type;
      Maximum_Depth : Natural)
   is
     limited private;

   --  Validate and freeze one explicit output profile without beginning the destination.
   --  Maximum depth counts simultaneously open containers. A root container is depth one;
   --  a scalar root needs depth zero.
   --  @param Self Uninitialized writer to prepare.
   --  @param Profile Complete explicit writer profile to validate and freeze.
   --  @param Diagnostic Cleared on success or set to the nonraising rejection reason.
   procedure Initialize
     (Self : in out Writer; Profile : Profiles.Writer_Profile; Diagnostic : out Errors.Diagnostic);

   --  Start one unpublished whole-document destination transaction.
   --  @param Self Ready writer whose profile is already frozen.
   --  @param Diagnostic Cleared on success or set to begin or lifecycle failure.
   procedure Begin_Document (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   --  Emit an object opener and push one container frame.
   --  @param Self Active writer at a position that accepts a JSON value.
   --  @param Diagnostic Cleared on success or set to grammar, depth, or destination failure.
   procedure Begin_Object (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   --  Emit an object closer after every member has a complete value.
   --  @param Self Active writer whose current container is a closable object.
   --  @param Diagnostic Cleared on success or set to grammar or destination failure.
   procedure End_Object (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   --  Emit an array opener and push one container frame.
   --  @param Self Active writer at a position that accepts a JSON value.
   --  @param Diagnostic Cleared on success or set to grammar, depth, or destination failure.
   procedure Begin_Array (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   --  Emit an array closer after its last complete value.
   --  @param Self Active writer whose current container is a closable array.
   --  @param Diagnostic Cleared on success or set to grammar or destination failure.
   procedure End_Array (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   --  Start one object member name and emit its opening quotation mark.
   --  @param Self Active writer whose current object expects a member name.
   --  @param Diagnostic Cleared on success or set to grammar or destination failure.
   procedure Begin_Name (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   --  Validate and escape one decoded UTF-8 member-name fragment.
   --  Fragments can split inside a UTF-8 sequence, and `Value` can have arbitrary bounds.
   --  @param Self Active writer with an open member-name token.
   --  @param Value Next decoded UTF-8 octets; the writer retains no array reference.
   --  @param Diagnostic Cleared on success or set to UTF-8, offset, or destination failure.
   procedure Put_Name_Fragment
     (Self : in out Writer; Value : Ada.Streams.Stream_Element_Array; Diagnostic : out Errors.Diagnostic);

   --  Finish the member name and emit the name/value separator.
   --  @param Self Active writer with a complete UTF-8 member-name token.
   --  @param Diagnostic Cleared on success or set to grammar, UTF-8, or destination failure.
   procedure End_Name (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   --  Start one JSON string value and emit its opening quotation mark.
   --  @param Self Active writer at a position that accepts a JSON value.
   --  @param Diagnostic Cleared on success or set to grammar or destination failure.
   procedure Begin_String (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   --  Validate and escape one decoded UTF-8 string fragment.
   --  Fragments can split inside a UTF-8 sequence, and `Value` can have arbitrary bounds.
   --  @param Self Active writer with an open string token.
   --  @param Value Next decoded UTF-8 octets; the writer retains no array reference.
   --  @param Diagnostic Cleared on success or set to UTF-8, offset, or destination failure.
   procedure Put_String_Fragment
     (Self : in out Writer; Value : Ada.Streams.Stream_Element_Array; Diagnostic : out Errors.Diagnostic);

   --  Finish a complete decoded UTF-8 string and emit its closing quotation mark.
   --  @param Self Active writer with an open string token.
   --  @param Diagnostic Cleared on success or set to grammar, UTF-8, or destination failure.
   procedure End_String (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   --  Start one exact JSON number lexeme without emitting a number-lexeme octet.
   --  @param Self Active writer at a position that accepts a JSON value.
   --  @param Diagnostic Cleared on success or set to a grammar failure.
   procedure Begin_Number (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   --  Validate and stage one exact number-lexeme fragment without normalization.
   --  @param Self Active writer with an open number token.
   --  @param Value Next exact lexeme octets with arbitrary array bounds.
   --  @param Diagnostic Cleared on success or set to number, offset, or destination failure.
   procedure Put_Number_Fragment
     (Self : in out Writer; Value : Ada.Streams.Stream_Element_Array; Diagnostic : out Errors.Diagnostic);

   --  Finish the number only when all staged lexeme octets form strict JSON syntax.
   --  @param Self Active writer with an open number token.
   --  @param Diagnostic Cleared on success or set to grammar or number failure.
   procedure End_Number (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   --  Emit one `null` value.
   --  @param Self Active writer at a position that accepts a JSON value.
   --  @param Diagnostic Cleared on success or set to grammar or destination failure.
   procedure Put_Null (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   --  Emit one `true` or `false` value.
   --  @param Self Active writer at a position that accepts a JSON value.
   --  @param Value Boolean value whose JSON literal is emitted.
   --  @param Diagnostic Cleared on success or set to grammar or destination failure.
   procedure Put_Boolean (Self : in out Writer; Value : Boolean; Diagnostic : out Errors.Diagnostic);

   --  Validate the balanced document and request the only destination commit.
   --  Commit failure publishes nothing and leaves cleanup to the writer transaction.
   --  @param Self Active writer after one complete balanced root value.
   --  @param Diagnostic Cleared after publication or set to grammar or commit failure.
   procedure Finish_Document (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   --  End unpublished staging without publication. Ready enters clean Aborted
   --  without a destination call. Active or Interrupted aborts its owned
   --  transaction once. Failed and Aborted are idempotent and retain their
   --  diagnostic; Uninitialized and Completed are nonmutating clean no-ops.
   --  An earlier primary remains primary if destination abort also fails.
   --  @param Self Writer in any lifecycle state; the state rules above control cleanup.
   --  @param Diagnostic Cleared or retained result prescribed by the current state.
   procedure Abort_Document (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   --  Prepare a completed, failed, or aborted writer for a new operation.
   --  The destination target and depth capacity remain fixed.
   --  @param Self Terminal writer to reset.
   --  @param Profile Complete explicit writer profile to validate and freeze.
   --  @param Diagnostic Cleared on success or set to profile or lifecycle failure.
   procedure Reset
     (Self : in out Writer; Profile : Profiles.Writer_Profile; Diagnostic : out Errors.Diagnostic);

   --  Report the writer lifecycle state.
   --  @param Self Writer to inspect.
   --  @return Current state without changing destination or writer data.
   function State (Self : Writer) return Writer_State;

   --  Test whether initialization or reset froze a validated profile.
   --  @param Self Writer to inspect.
   --  @return True when `Applied_Profile` is eligible.
   function Has_Applied_Profile (Self : Writer) return Boolean;

   --  Read the exact profile frozen before destination begin.
   --  @param Self Writer with an applied profile.
   --  @return Copy of the complete applied writer profile.
   function Applied_Profile (Self : Writer) return Profiles.Writer_Profile
   with Pre => Has_Applied_Profile (Self);

   --  Read the retained terminal diagnostic.
   --  @param Self Interrupted, failed, or aborted writer.
   --  @return Final diagnostic; an earlier primary remains primary if abort cleanup also fails.
   function Terminal_Diagnostic (Self : Writer) return Errors.Diagnostic
   with Pre => State (Self) in Interrupted | Failed | Aborted;

private
   package Engine_Writers is new
     Writer_Core.Destination_Writers
       (Destination_Type   => Destination_Type,
        Destination_Begin  => Destination_Begin,
        Destination_Write  => Destination_Write,
        Destination_Commit => Destination_Commit,
        Destination_Abort  => Destination_Abort);

   type Writer
     (Target        : not null access Destination_Type;
      Maximum_Depth : Natural)
   is new Ada.Finalization.Limited_Controlled with record
      Engine               : Engine_Writers.Writer (Target, Maximum_Depth);
      Profile_Is_Applied   : Boolean := False;
      Applied_Profile_Data : Profiles.Writer_Profile;
   end record;

   --  Abort one owned unpublished transaction during scope exit.
   --  @param Self Writer being finalized.
   overriding
   procedure Finalize (Self : in out Writer);
end Flyology_JSON.Writing;
