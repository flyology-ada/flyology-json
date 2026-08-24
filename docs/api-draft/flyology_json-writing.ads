with Ada.Finalization;
with Ada.Streams;
with Flyology_JSON.Budgets;
with Flyology_JSON.Errors;
with Flyology_JSON.Profiles;

generic
   type Budget_Type is limited private;
   with
     function Charge
       (Budget : in out Budget_Type; Dimension : Budgets.Charge_Dimension; Amount : Budgets.Charge_Amount)
        return Budgets.Charge_Decision;

   type Destination_Type is limited private;
   with
     procedure Destination_Begin (Target : in out Destination_Type; Outcome : out Errors.Destination_Outcome);
   with
     procedure Destination_Write
       (Target  : in out Destination_Type;
        Data    : Ada.Streams.Stream_Element_Array;
        Outcome : out Errors.Destination_Outcome);
   with
     procedure Destination_Commit
       (Target : in out Destination_Type; Outcome : out Errors.Destination_Outcome);
   with
     procedure Destination_Abort (Target : in out Destination_Type; Outcome : out Errors.Destination_Outcome);
package Flyology_JSON.Writing is
   type Writer_State is (Uninitialized, Ready, Active, Completed, Failed, Aborted);

   type Writer
     (Target        : not null access Destination_Type;
      Maximum_Depth : Natural)
   is
     limited private;

   procedure Initialize
     (Self : in out Writer; Profile : Profiles.Writer_Profile; Diagnostic : out Errors.Diagnostic);

   procedure Begin_Document (Self : in out Writer; Diagnostic : out Errors.Diagnostic);

   procedure Begin_Object
     (Self : in out Writer; Budget : in out Budget_Type; Diagnostic : out Errors.Diagnostic);

   procedure End_Object
     (Self : in out Writer; Budget : in out Budget_Type; Diagnostic : out Errors.Diagnostic);

   procedure Begin_Array
     (Self : in out Writer; Budget : in out Budget_Type; Diagnostic : out Errors.Diagnostic);

   procedure End_Array
     (Self : in out Writer; Budget : in out Budget_Type; Diagnostic : out Errors.Diagnostic);

   procedure Begin_Name
     (Self : in out Writer; Budget : in out Budget_Type; Diagnostic : out Errors.Diagnostic);

   procedure Put_Name_Fragment
     (Self       : in out Writer;
      Budget     : in out Budget_Type;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic);

   procedure End_Name (Self : in out Writer; Budget : in out Budget_Type; Diagnostic : out Errors.Diagnostic);

   procedure Begin_String
     (Self : in out Writer; Budget : in out Budget_Type; Diagnostic : out Errors.Diagnostic);

   procedure Put_String_Fragment
     (Self       : in out Writer;
      Budget     : in out Budget_Type;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic);

   procedure End_String
     (Self : in out Writer; Budget : in out Budget_Type; Diagnostic : out Errors.Diagnostic);

   procedure Begin_Number
     (Self : in out Writer; Budget : in out Budget_Type; Diagnostic : out Errors.Diagnostic);

   procedure Put_Number_Fragment
     (Self       : in out Writer;
      Budget     : in out Budget_Type;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic);

   procedure End_Number
     (Self : in out Writer; Budget : in out Budget_Type; Diagnostic : out Errors.Diagnostic);

   procedure Put_Null (Self : in out Writer; Budget : in out Budget_Type; Diagnostic : out Errors.Diagnostic);

   procedure Put_Boolean
     (Self : in out Writer; Budget : in out Budget_Type; Value : Boolean; Diagnostic : out Errors.Diagnostic);

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

   function Counters (Self : Writer) return Budgets.Work_Counters;

private
   type Container_Kind is (Array_Container, Object_Container);
   type Container_Phase is
     (Array_First_Or_End, Array_Value_Or_End, Object_First_Or_End, Object_Name_Or_End, Object_Value);

   type Container_Frame is record
      Kind  : Container_Kind;
      Phase : Container_Phase;
   end record;

   type Frame_Array is array (Natural range <>) of Container_Frame;
   type Lexical_State is (No_Lexical_Value, Writing_Name, Writing_String, Writing_Number);
   type Number_State is
     (Number_Start,
      After_Minus,
      Integer_Zero,
      Integer_Digits,
      Fraction_Start,
      Fraction_Digits,
      Exponent_Start,
      Exponent_Sign,
      Exponent_Digits);
   --  Four is the derived maximum UTF-8 scalar length.
   type UTF8_Octets is array (Natural range 1 .. 4) of Ada.Streams.Stream_Element;
   --  Six is the length of a complete JSON reverse-solidus-u escape.
   type Escape_Octets is array (Natural range 1 .. 6) of Ada.Streams.Stream_Element;

   type Writer
     (Target        : not null access Destination_Type;
      Maximum_Depth : Natural)
   is new Ada.Finalization.Limited_Controlled with record
      Current_State      : Writer_State := Uninitialized;
      Profile_Is_Applied : Boolean := False;
      Profile            : Profiles.Writer_Profile;
      Last_Diagnostic    : Errors.Diagnostic;
      Work               : Budgets.Work_Counters :=
        (Maximum_Live_Depth           => 0,
         Step_Calls                   => 0,
         Need_Input_Count             => 0,
         Fragment_Deliveries          => 0,
         Writer_Calls                 => 0,
         Destination_Calls            => 0,
         Cleanup_Calls                => 0,
         Transport_Counter_Overflowed => False);
      Stack              : Frame_Array (1 .. Maximum_Depth);
      Depth              : Natural;
      Lexical            : Lexical_State;
      Number             : Number_State;
      Token_Input_Offset : Errors.Byte_Offset;
      Staged_Offset      : Errors.Byte_Offset;
      Call_Ordinal       : Errors.Byte_Offset;
      UTF8_Carry         : UTF8_Octets;
      UTF8_Carry_Length  : Natural range 0 .. 4;
      Pending            : Escape_Octets;
      Pending_Length     : Natural range 0 .. 6;
      Root_Written       : Boolean;
      Owns_Transaction   : Boolean := False;
   end record;

   overriding
   procedure Finalize (Self : in out Writer);
end Flyology_JSON.Writing;
