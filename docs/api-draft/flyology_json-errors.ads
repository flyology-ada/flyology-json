with Flyology_JSON.Budgets;
with Interfaces;

--  Nonraising JSON diagnostics with explicit coordinate systems.

package Flyology_JSON.Errors
  with Pure
is
   subtype Byte_Offset is Interfaces.Unsigned_64;

   type Error_Code is
     (No_Error,
      Unsupported_Profile,
      Incompatible_Profile,
      Invalid_State,
      Invalid_Writer_Grammar,
      Unexpected_Token,
      Trailing_Input,
      Truncated_Input,
      Invalid_Literal,
      Invalid_Number,
      Invalid_Escape,
      Invalid_UTF8,
      Invalid_Surrogate,
      Raw_Control_Character,
      Duplicate_Name,
      Top_Level_Kind_Rejected,
      Budget_Denied,
      Depth_Exhausted,
      Name_Storage_Exhausted,
      Duplicate_Index_Exhausted,
      Offset_Exhausted,
      Counter_Exhausted,
      Destination_Exhausted,
      Destination_Failed,
      Commit_Failed,
      Abort_Failed);

   type Coordinate_Kind is
     (No_Coordinate,
      Source_Byte,
      Writer_Token_Byte,
      Staged_Output_Byte,
      JSON_Call_Ordinal,
      JSON_Event_Ordinal);

   type Destination_Outcome is (Stage_Accepted, Stage_Capacity_Denied, Stage_Error);

   type Diagnostic is record
      Code                     : Error_Code;
      Has_Coordinate           : Boolean;
      Coordinate               : Coordinate_Kind;
      Offset                   : Byte_Offset;
      Has_Denied_Dimension     : Boolean;
      Denied_Dimension         : Budgets.Charge_Dimension;
      Has_Secondary            : Boolean;
      Secondary                : Error_Code;
      Secondary_Has_Coordinate : Boolean;
      Secondary_Coordinate     : Coordinate_Kind;
      Secondary_Offset         : Byte_Offset;
   end record;

   procedure Clear (Item : out Diagnostic);
end Flyology_JSON.Errors;
