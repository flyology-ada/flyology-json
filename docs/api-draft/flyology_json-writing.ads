with Ada.Finalization;
with Ada.Streams;
with Flyology_JSON.Destinations;
with Flyology_JSON.Errors;
with Flyology_JSON.Profiles;

--  Trusted transactional streaming writer.  The destination stages an entire
--  document and publishes only through Commit.  This package contains no
--  accounting state, hook, nullable budget, or accounting branch.

generic
   type Destination_Type is limited private;

   with procedure Destination_Begin
     (Target : in out Destination_Type; Status : out Destinations.Begin_Status);

   --  Write_Succeeded requires Written = Data'Length.  Write_Exhausted requires
   --  Written < Data'Length and makes that longest prefix the call's complete
   --  staging effect.  Write_Failed requires Written = 0 and no staging effect.
   --  Written is a count and never an Ada array index.
   with procedure Destination_Write
     (Target    : in out Destination_Type;
      Data      : Ada.Streams.Stream_Element_Array;
      Written   : out Ada.Streams.Stream_Element_Count;
      Status    : out Destinations.Write_Status);

   with procedure Destination_Commit
     (Target : in out Destination_Type; Status : out Destinations.Commit_Status);

   --  Abort must end an active unpublished transaction even when Status is
   --  Abort_Failed.  It never publishes staged bytes.
   with procedure Destination_Abort
     (Target : in out Destination_Type; Status : out Destinations.Abort_Status);
package Flyology_JSON.Writing is
   type Writer_State is (Uninitialized, Ready, Active, Completed, Failed, Aborted);

   type Writer
     (Target        : not null access Destination_Type;
      Maximum_Depth : Natural)
   is limited private;

   --  Profile must select Ordinary_Compact output.  Unsupported or
   --  incompatible profiles fail before Destination_Begin.
   procedure Initialize
     (Self : in out Writer; Profile : Profiles.Writer_Profile; Diagnostic : out Errors.Diagnostic);

   procedure Begin_Document (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   procedure Begin_Object (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   procedure End_Object (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   procedure Begin_Array (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   procedure End_Array (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   procedure Begin_Name (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   procedure Put_Name_Fragment
     (Self       : in out Writer;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic);

   procedure End_Name (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   procedure Begin_String (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   procedure Put_String_Fragment
     (Self       : in out Writer;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic);

   procedure End_String (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   procedure Begin_Number (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   procedure Put_Number_Fragment
     (Self       : in out Writer;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic);

   procedure End_Number (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   procedure Put_Null (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   procedure Put_Boolean
     (Self : in out Writer; Value : Boolean; Diagnostic : out Errors.Diagnostic);

   procedure Finish_Document (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   procedure Abort_Document (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   procedure Reset
     (Self : in out Writer; Profile : Profiles.Writer_Profile; Diagnostic : out Errors.Diagnostic);

   function State (Self : Writer) return Writer_State;

   function Has_Applied_Profile (Self : Writer) return Boolean;

   function Applied_Profile (Self : Writer) return Profiles.Writer_Profile
   with Pre => Has_Applied_Profile (Self);

   function Terminal_Diagnostic (Self : Writer) return Errors.Diagnostic
   with Pre => State (Self) in Failed | Aborted;

private
   type Writer
     (Target        : not null access Destination_Type;
      Maximum_Depth : Natural)
   is new Ada.Finalization.Limited_Controlled with record
      Placeholder : Boolean := False;
   end record;

   overriding procedure Finalize (Self : in out Writer);
end Flyology_JSON.Writing;
