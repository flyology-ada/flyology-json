with Ada.Exceptions;

package body Flyology_JSON.Writing is

   use type Errors.Error_Code;

   procedure Run_Profile_Boundary (Action : not null access procedure) is
      Saved  : Ada.Exceptions.Exception_Occurrence;
      Raised : Boolean := False;

      type Transfer_Guard is new Ada.Finalization.Limited_Controlled with record
         Armed : Boolean := False with Atomic;
      end record;

      overriding procedure Finalize (Guard : in out Transfer_Guard) is
      begin
         if Guard.Armed then
            Guard.Armed := False;
            begin
               Action.all;
            exception
               when Occurrence : others =>
                  Ada.Exceptions.Save_Occurrence (Saved, Occurrence);
                  Raised := True;
            end;
         end if;
      end Finalize;
   begin
      declare
         Transfer : Transfer_Guard;
         pragma Unreferenced (Transfer);
      begin
         Transfer.Armed := True;
      end;

      if Raised then
         Ada.Exceptions.Reraise_Occurrence (Saved);
      end if;
   end Run_Profile_Boundary;

   function State (Self : Writer) return Writer_State is
   begin
      case Engine_Writers.State (Self.Engine) is
         when Writer_Core.Uninitialized =>
            return Uninitialized;
         when Writer_Core.Ready =>
            return Ready;
         when Writer_Core.Active =>
            return Active;
         when Writer_Core.Interrupted =>
            return Interrupted;
         when Writer_Core.Completed =>
            return Completed;
         when Writer_Core.Failed =>
            return Failed;
         when Writer_Core.Aborted =>
            return Aborted;
      end case;
   end State;

   procedure Reject_State
     (Self : Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      if State (Self) in Interrupted | Failed | Aborted then
         Diagnostic := Engine_Writers.Terminal_Diagnostic (Self.Engine);
      else
         Diagnostic :=
           (Code                 => Errors.Invalid_State,
            Coordinate           => Errors.No_Coordinate,
            Offset               => 0,
            Secondary            => Errors.No_Error,
            Secondary_Coordinate => Errors.No_Coordinate,
            Secondary_Offset     => 0);
      end if;
   end Reject_State;

   procedure Apply_Profile
     (Self       : in out Writer;
      Profile    : Profiles.Writer_Profile;
      Is_Reset   : Boolean;
      Diagnostic : out Errors.Diagnostic)
   is
      Status : constant Profiles.Profile_Status := Profiles.Validate (Profile);
   begin
      Self.Profile_Is_Applied := False;

      case Status is
         when Profiles.Profile_Unsupported =>
            Engine_Writers.Reject_Profile
              (Self.Engine, Errors.Unsupported_Profile, Diagnostic);
         when Profiles.Profile_Incompatible =>
            Engine_Writers.Reject_Profile
              (Self.Engine, Errors.Incompatible_Profile, Diagnostic);
         when Profiles.Profile_Supported =>
            if Is_Reset then
               Engine_Writers.Reset (Self.Engine, Diagnostic);
            else
               Engine_Writers.Initialize (Self.Engine, Diagnostic);
            end if;
            if Diagnostic.Code = Errors.No_Error then
               Self.Applied_Profile_Data := Profile;
               Self.Profile_Is_Applied := True;
            end if;
      end case;
   end Apply_Profile;

   procedure Initialize
     (Self       : in out Writer;
      Profile    : Profiles.Writer_Profile;
      Diagnostic : out Errors.Diagnostic)
   is
      procedure Perform is
      begin
         Apply_Profile (Self, Profile, Is_Reset => False, Diagnostic => Diagnostic);
      end Perform;
   begin
      if State (Self) /= Uninitialized then
         Reject_State (Self, Diagnostic);
         return;
      end if;
      Run_Profile_Boundary (Perform'Access);
   end Initialize;

   procedure Begin_Document
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine_Writers.Begin_Document (Self.Engine, Diagnostic);
   end Begin_Document;

   procedure Begin_Object
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine_Writers.Begin_Object (Self.Engine, Diagnostic);
   end Begin_Object;

   procedure End_Object
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine_Writers.End_Object (Self.Engine, Diagnostic);
   end End_Object;

   procedure Begin_Array
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine_Writers.Begin_Array (Self.Engine, Diagnostic);
   end Begin_Array;

   procedure End_Array
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine_Writers.End_Array (Self.Engine, Diagnostic);
   end End_Array;

   procedure Begin_Name
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine_Writers.Begin_Name (Self.Engine, Diagnostic);
   end Begin_Name;

   procedure Put_Name_Fragment
     (Self       : in out Writer;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine_Writers.Put_Name_Fragment (Self.Engine, Value, Diagnostic);
   end Put_Name_Fragment;

   procedure End_Name
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine_Writers.End_Name (Self.Engine, Diagnostic);
   end End_Name;

   procedure Begin_String
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine_Writers.Begin_String (Self.Engine, Diagnostic);
   end Begin_String;

   procedure Put_String_Fragment
     (Self       : in out Writer;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine_Writers.Put_String_Fragment (Self.Engine, Value, Diagnostic);
   end Put_String_Fragment;

   procedure End_String
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine_Writers.End_String (Self.Engine, Diagnostic);
   end End_String;

   procedure Begin_Number
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine_Writers.Begin_Number (Self.Engine, Diagnostic);
   end Begin_Number;

   procedure Put_Number_Fragment
     (Self       : in out Writer;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine_Writers.Put_Number_Fragment (Self.Engine, Value, Diagnostic);
   end Put_Number_Fragment;

   procedure End_Number
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine_Writers.End_Number (Self.Engine, Diagnostic);
   end End_Number;

   procedure Put_Null
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine_Writers.Put_Null (Self.Engine, Diagnostic);
   end Put_Null;

   procedure Put_Boolean
     (Self       : in out Writer;
      Value      : Boolean;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine_Writers.Put_Boolean (Self.Engine, Value, Diagnostic);
   end Put_Boolean;

   procedure Finish_Document
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine_Writers.Finish_Document (Self.Engine, Diagnostic);
   end Finish_Document;

   procedure Abort_Document
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine_Writers.Abort_Document (Self.Engine, Diagnostic);
   end Abort_Document;

   procedure Reset
     (Self       : in out Writer;
      Profile    : Profiles.Writer_Profile;
      Diagnostic : out Errors.Diagnostic)
   is
      procedure Perform is
      begin
         Apply_Profile (Self, Profile, Is_Reset => True, Diagnostic => Diagnostic);
      end Perform;
   begin
      if State (Self) not in Completed | Failed | Aborted then
         Reject_State (Self, Diagnostic);
         return;
      end if;
      Run_Profile_Boundary (Perform'Access);
   end Reset;

   function Has_Applied_Profile (Self : Writer) return Boolean is
     (Self.Profile_Is_Applied);

   function Applied_Profile (Self : Writer) return Profiles.Writer_Profile is
     (Self.Applied_Profile_Data);

   function Terminal_Diagnostic (Self : Writer) return Errors.Diagnostic is
     (Engine_Writers.Terminal_Diagnostic (Self.Engine));

   overriding procedure Finalize (Self : in out Writer) is
   begin
      Engine_Writers.Cleanup (Self.Engine);
   end Finalize;

end Flyology_JSON.Writing;
