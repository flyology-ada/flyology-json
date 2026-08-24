with Ada.Streams;

--  Caller-owned resource charging shared by parser and writer core packages.

package Flyology_JSON.Budgets
  with Pure
is
   type Charge_Dimension is
     (Input_Octets,
      Syntax_Events,
      Values,
      Container_Items,
      Decoded_Scalars,
      Duplicate_Name_Octets,
      Duplicate_Index_Slots,
      Duplicate_Work,
      Writer_Input_Octets,
      Staged_Output_Octets);

   subtype Charge_Amount is Ada.Streams.Stream_Element_Count;
   subtype Counter_Value is Ada.Streams.Stream_Element_Count;

   type Charge_Decision is (Accept_Charge, Deny_Charge);

   type Work_Counters is record
      Maximum_Live_Depth           : Counter_Value;
      Step_Calls                   : Counter_Value;
      Need_Input_Count             : Counter_Value;
      Fragment_Deliveries          : Counter_Value;
      Writer_Calls                 : Counter_Value;
      Destination_Calls            : Counter_Value;
      Cleanup_Calls                : Counter_Value;
      Transport_Counter_Overflowed : Boolean;
   end record;
end Flyology_JSON.Budgets;
