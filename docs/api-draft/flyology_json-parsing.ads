with Ada.Streams;
with Flyology_JSON.Budgets;
with Flyology_JSON.Errors;
with Flyology_JSON.Events;
with Flyology_JSON.Profiles;
with Interfaces;

generic
   type Budget_Type is limited private;
   with
     function Charge
       (Budget : in out Budget_Type; Dimension : Budgets.Charge_Dimension; Amount : Budgets.Charge_Amount)
        return Budgets.Charge_Decision;
package Flyology_JSON.Parsing is
   type Parser_State is (Uninitialized, Ready, Active, Completed, Failed, Aborted);

   type Step_Outcome is (Event_Ready, Need_Input, Document_Complete, Step_Failed, Call_Rejected);

   type Step_Result is record
      Outcome    : Step_Outcome;
      Consumed   : Ada.Streams.Stream_Element_Count;
      Item       : Events.Event;
      Diagnostic : Errors.Diagnostic;
   end record;

   type Parser
     (Maximum_Depth       : Natural;
      Name_Octet_Capacity : Natural;
      Name_Capacity       : Natural)
   is
     limited private;

   procedure Initialize
     (Self : in out Parser; Profile : Profiles.Parser_Profile; Diagnostic : out Errors.Diagnostic);

   procedure Step
     (Self         : in out Parser;
      Budget       : in out Budget_Type;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Result       : out Step_Result);

   procedure Abort_Document (Self : in out Parser);

   procedure Reset
     (Self : in out Parser; Profile : Profiles.Parser_Profile; Diagnostic : out Errors.Diagnostic);

   function State (Self : Parser) return Parser_State;

   function Has_Applied_Profile (Self : Parser) return Boolean;

   function Applied_Profile (Self : Parser) return Profiles.Parser_Profile
   with Pre => Has_Applied_Profile (Self);

   function Terminal_Diagnostic (Self : Parser) return Errors.Diagnostic
   with Pre => State (Self) in Failed | Aborted;

   function Counters (Self : Parser) return Budgets.Work_Counters;

private
   type Container_Kind is (Array_Container, Object_Container);
   type Container_Phase is
     (Array_First_Or_End,
      Array_Comma_Or_End,
      Object_First_Or_End,
      Object_Name,
      Object_Colon,
      Object_Value,
      Object_Comma_Or_End);

   type Container_Frame is record
      Kind            : Container_Kind;
      Phase           : Container_Phase;
      Source_Start    : Errors.Byte_Offset;
      Name_Octet_Mark : Natural;
      Leaf_Mark       : Natural;
      Node_Mark       : Natural;
      Duplicate_Root  : Natural;
   end record;

   type Frame_Array is array (Natural range <>) of Container_Frame;
   type Name_Octet_Array is array (Natural range <>) of Ada.Streams.Stream_Element;

   type Name_Leaf is record
      Offset : Natural;
      Length : Natural;
   end record;

   type Leaf_Array is array (Natural range <>) of Name_Leaf;

   type Entry_Kind is (No_Entry, Leaf_Entry, Node_Entry);
   type Entry_Reference is record
      Kind  : Entry_Kind;
      Index : Natural;
   end record;

   type Crit_Bit_Node is record
      Critical_Bit : Errors.Byte_Offset;
      Child_Zero   : Entry_Reference;
      Child_One    : Entry_Reference;
   end record;

   type Node_Array is array (Natural range <>) of Crit_Bit_Node;

   type Lexical_State is
     (Between_Tokens,
      In_String,
      In_Escape,
      In_Unicode_Escape,
      Awaiting_Low_Surrogate,
      In_Number,
      In_Literal,
      After_Root);

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

   type Parser
     (Maximum_Depth       : Natural;
      Name_Octet_Capacity : Natural;
      Name_Capacity       : Natural)
   is limited record
      Current_State      : Parser_State := Uninitialized;
      Profile_Is_Applied : Boolean := False;
      Profile            : Profiles.Parser_Profile;
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
      Next_Offset        : Errors.Byte_Offset;
      Event_Ordinal      : Errors.Byte_Offset;
      Depth              : Natural;
      Stack              : Frame_Array (1 .. Maximum_Depth);
      Name_Octets        : Name_Octet_Array (1 .. Name_Octet_Capacity);
      Leaves             : Leaf_Array (1 .. Name_Capacity);
      Nodes              : Node_Array (1 .. Name_Capacity);
      Name_Octets_Used   : Natural;
      Leaves_Used        : Natural;
      Nodes_Used         : Natural;
      Lexical            : Lexical_State;
      Number             : Number_State;
      Token_Start        : Errors.Byte_Offset;
      --  Derived maximum UTF-8 scalar length; this is not policy capacity.
      UTF8_Carry         : Events.Scalar_Octets;
      UTF8_Carry_Length  : Natural range 0 .. 4;
      --  JSON \u has exactly four hex digits encoding one 16-bit code unit.
      Escape_Value       : Interfaces.Unsigned_16;
      Escape_Digits      : Natural range 0 .. 4;
      High_Surrogate     : Interfaces.Unsigned_16;
      Literal_Position   : Natural;
      Root_Seen          : Boolean;
      Document_End_Sent  : Boolean;
   end record;
end Flyology_JSON.Parsing;
