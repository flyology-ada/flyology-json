with Ada.Finalization;
with Ada.Streams;
with Flyology_JSON.Destinations;
with Flyology_JSON.Errors;
with Flyology_JSON.Parser_Numbers;
with Flyology_JSON.Parser_UTF8;

--  Allocation-free trusted transactional writer mechanism.
--
--  This private unit contains the ordinary compact JSON state machine.  It
--  deliberately has no profile selection, accounting hook, allocation, or C
--  dependency.  A reviewed public wrapper owns profile validation and public
--  type translation.

private package Flyology_JSON.Writer_Core is

   subtype Byte_Offset is Errors.Byte_Offset;
   subtype Begin_Status is Destinations.Begin_Status;
   subtype Write_Status is Destinations.Write_Status;
   subtype Commit_Status is Destinations.Commit_Status;
   subtype Abort_Status is Destinations.Abort_Status;
   subtype Error_Code is Errors.Error_Code;
   subtype Coordinate_Kind is Errors.Coordinate_Kind;
   subtype Diagnostic is Errors.Diagnostic;

   type Writer_State is (Uninitialized, Ready, Active, Completed, Failed, Aborted);

   generic
      type Destination_Type is limited private;

      with procedure Destination_Begin
        (Target : in out Destination_Type; Status : out Destinations.Begin_Status);

      --  Success accepts all Data. Exhaustion accepts its longest prefix.
      --  Failure accepts none. Written is always a count, never an index.
      with procedure Destination_Write
        (Target  : in out Destination_Type;
         Data    : Ada.Streams.Stream_Element_Array;
         Written : out Ada.Streams.Stream_Element_Count;
         Status  : out Destinations.Write_Status);

      with procedure Destination_Commit
        (Target : in out Destination_Type; Status : out Destinations.Commit_Status);

      --  Abort ends an unpublished transaction even when it reports failure.
      with procedure Destination_Abort
        (Target : in out Destination_Type; Status : out Destinations.Abort_Status);
   package Destination_Writers is

      type Writer
        (Target        : not null access Destination_Type;
         Maximum_Depth : Natural)
      is limited private;

      procedure Initialize (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

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
      procedure Reset (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

      function State (Self : Writer) return Writer_State;

      function Terminal_Diagnostic (Self : Writer) return Errors.Diagnostic
      with Pre => State (Self) in Failed | Aborted;

      --  Private-parent test seam for otherwise unreachable 64-bit boundary
      --  fixtures. It is never re-exported by the public writer.
      procedure Set_Offsets_For_Test
        (Self        : in out Writer;
         Next_Staged : Byte_Offset;
         Next_Token  : Byte_Offset)
      with Pre => State (Self) = Active;

      --  Benchmark-only baseline for measuring the call guard around the
      --  unchanged hot scanner. It is private to this private parent and is
      --  never re-exported.
      procedure Put_String_Fragment_Unguarded_For_Test
        (Self       : in out Writer;
         Value      : Ada.Streams.Stream_Element_Array;
         Diagnostic : out Errors.Diagnostic)
      with Pre => State (Self) = Active;

   private

      type Container_Kind is (Object_Container, Array_Container);
      type Object_Phase is (Name_Or_End, Value_Required);

      type Container_Frame is record
         Kind      : Container_Kind := Array_Container;
         Phase     : Object_Phase := Name_Or_End;
         Has_Items : Boolean := False;
      end record;

      type Frame_Array is array (Natural range <>) of Container_Frame;
      type Token_Kind is (No_Token, Name_Token, String_Token, Number_Token);

      type Writer
        (Target        : not null access Destination_Type;
         Maximum_Depth : Natural)
      is new Ada.Finalization.Limited_Controlled with record
         Current_State         : Writer_State := Uninitialized;
         --  Keep this valid from object elaboration onward.  An abnormal
         --  transfer can finalize the per-call cleanup guard before the
         --  deferred action reaches Initialize or Reset.
         Last_Diagnostic       : Errors.Diagnostic :=
           (Code                 => Errors.No_Error,
            Coordinate           => Errors.No_Coordinate,
            Offset               => 0,
            Secondary            => Errors.No_Error,
            Secondary_Coordinate => Errors.No_Coordinate,
            Secondary_Offset     => 0);
         Owns_Transaction      : Boolean := False;
         Abort_Attempted       : Boolean := False;
         Next_Staged_Offset     : Byte_Offset := 0;
         Next_Token_Offset      : Byte_Offset := 0;
         Next_Call_Ordinal      : Byte_Offset := 0;
         Depth                  : Natural := 0;
         Stack                 : Frame_Array (1 .. Maximum_Depth);
         Root_Started          : Boolean := False;
         Root_Complete         : Boolean := False;
         Token                 : Token_Kind := No_Token;
         UTF8                  : Parser_UTF8.Decoder;
         UTF8_Lead_Offset      : Byte_Offset := 0;
         Number                : Parser_Numbers.Number_State;
      end record;

      overriding procedure Finalize (Self : in out Writer);

   end Destination_Writers;

end Flyology_JSON.Writer_Core;
