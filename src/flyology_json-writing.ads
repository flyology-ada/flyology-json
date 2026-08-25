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
   type Destination_Type is limited private;

   --  Begin is synchronous, nonraising, finite, and nonreentrant. A successful
   --  return starts exactly one unpublished transaction. A failed return starts
   --  none. The writer protects this ownership boundary from task abort.
   with procedure Destination_Begin
     (Target : in out Destination_Type;
      Status : out Destinations.Begin_Status);

   --  Write is synchronous, finite, nonreentrant, retains no reference to Data,
   --  and does not access a writer alias. On normal return, Write_Succeeded
   --  accepts all Data; Write_Exhausted
   --  accepts the exact longest prefix; Write_Failed accepts none. Written is
   --  a count rather than an Ada index.
   --
   --  On abnormal completion, Write may have staged an in-order prefix of Data
   --  from zero through Data'Length. That prefix remains unpublished, Data is
   --  not retained, and one coherent transaction remains abortable.
   with procedure Destination_Write
     (Target  : in out Destination_Type;
      Data    : Ada.Streams.Stream_Element_Array;
      Written : out Ada.Streams.Stream_Element_Count;
      Status  : out Destinations.Write_Status);

   --  Commit is synchronous, nonraising, finite, and nonreentrant. Success is
   --  the only publication point. Failure publishes nothing and leaves the
   --  transaction abortable. The writer protects publication and its ownership
   --  transition from task abort.
   with procedure Destination_Commit
     (Target : in out Destination_Type;
      Status : out Destinations.Commit_Status);

   --  Abort is synchronous, nonraising, finite, and nonreentrant. It ends the
   --  active unpublished transaction and never publishes, even when Status is
   --  Abort_Failed. The writer protects abort and exactly-once bookkeeping from
   --  task abort.
   with procedure Destination_Abort
     (Target : in out Destination_Type;
      Status : out Destinations.Abort_Status);
package Flyology_JSON.Writing is

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
   package Engine_Writers is new Writer_Core.Destination_Writers
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

   overriding procedure Finalize (Self : in out Writer);
end Flyology_JSON.Writing;
