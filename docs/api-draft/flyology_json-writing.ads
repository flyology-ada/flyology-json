with Ada.Finalization;
with Ada.Streams;
with Flyology_JSON.Destinations;
with Flyology_JSON.Errors;
with Flyology_JSON.Profiles;

--  Trusted transactional streaming writer. The destination stages one whole
--  document and publishes only through Commit. There is no accounting state,
--  hook, nullable budget, accounting branch, or public capacity default.

generic
   type Destination_Type is limited private;

   --  Begin is synchronous, nonraising, finite, and nonreentrant. A successful
   --  return starts exactly one unpublished transaction. A failed return starts
   --  none. The writer makes this ownership transfer abort-deferred.
   with procedure Destination_Begin
     (Target : in out Destination_Type;
      Status : out Destinations.Begin_Status);

   --  On normal return, Write_Succeeded accepts all Data; Write_Exhausted
   --  accepts the exact longest prefix; Write_Failed accepts none. Written is a
   --  count, never an Ada index, and is respectively Data'Length, less than
   --  Data'Length, or zero.
   --
   --  Write is synchronous, finite, nonreentrant, and retains no reference to
   --  Data. If task abort, ATC, or a contract-violating exception makes Write
   --  complete abnormally, it may have staged any prefix but must leave one
   --  coherent active unpublished transaction that Destination_Abort can end.
   --  The effect is an in-order prefix of Data from zero through Data'Length,
   --  remains unpublished, and is not retained. No Written value or exact
   --  accepted-prefix coordinate then exists.
   with procedure Destination_Write
     (Target  : in out Destination_Type;
      Data    : Ada.Streams.Stream_Element_Array;
      Written : out Ada.Streams.Stream_Element_Count;
      Status  : out Destinations.Write_Status);

   --  Commit is synchronous, nonraising, finite, and nonreentrant. Success is
   --  the only publication point. Failure publishes nothing and leaves the
   --  transaction abortable. The writer makes publication and its ownership
   --  transition abort-deferred.
   with procedure Destination_Commit
     (Target : in out Destination_Type;
      Status : out Destinations.Commit_Status);

   --  Abort is synchronous, nonraising, finite, and nonreentrant. It ends the
   --  active unpublished transaction and never publishes, even when Status is
   --  Abort_Failed. The writer makes abort and exactly-once bookkeeping
   --  abort-deferred.
   with procedure Destination_Abort
     (Target : in out Destination_Type;
      Status : out Destinations.Abort_Status);
package Flyology_JSON.Writing is

   type Writer_State is
     (Uninitialized,
      Ready,
      Active,
      Interrupted,
      Completed,
      Failed,
      Aborted);

   type Writer
     (Target        : not null access Destination_Type;
      Maximum_Depth : Natural)
   is limited private;

   --  Maximum_Depth counts simultaneously open object and array containers. A
   --  root container is depth one; a scalar root needs depth zero.

   procedure Initialize
     (Self       : in out Writer;
      Profile    : Profiles.Writer_Profile;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Document
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Object
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure End_Object
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Array
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure End_Array
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Name
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Name_Fragment
     (Self       : in out Writer;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic);

   procedure End_Name
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_String
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_String_Fragment
     (Self       : in out Writer;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic);

   procedure End_String
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Number
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Number_Fragment
     (Self       : in out Writer;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic);

   procedure End_Number
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Null
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Boolean
     (Self       : in out Writer;
      Value      : Boolean;
      Diagnostic : out Errors.Diagnostic);

   procedure Finish_Document
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Abort_Document
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Reset
     (Self       : in out Writer;
      Profile    : Profiles.Writer_Profile;
      Diagnostic : out Errors.Diagnostic);

   function State (Self : Writer) return Writer_State;

   function Has_Applied_Profile (Self : Writer) return Boolean;

   function Applied_Profile (Self : Writer) return Profiles.Writer_Profile
   with Pre => Has_Applied_Profile (Self);

   function Terminal_Diagnostic (Self : Writer) return Errors.Diagnostic
   with Pre => State (Self) in Interrupted | Failed | Aborted;

private
   --  The implementation uses an Atomic elementary in-call marker and an
   --  Atomic elementary primary-diagnostic-valid flag. Candidate diagnostic
   --  storage is eligible only after the validity flag is set.
   type Writer
     (Target        : not null access Destination_Type;
      Maximum_Depth : Natural)
   is new Ada.Finalization.Limited_Controlled with record
      Placeholder : Boolean := False;
   end record;

   --  Finalize attempts an owned transaction abort at most once and suppresses
   --  every internal or destination exception. It never publishes and never
   --  propagates during scope exit, exception unwinding, ATC, or task abort.
   overriding procedure Finalize (Self : in out Writer);
end Flyology_JSON.Writing;
