with Interfaces;

--  Nonraising JSON diagnostics with explicit coordinate systems.

package Flyology_JSON.Errors
  with Pure
is
   --  Absolute JSON streams and writer counters use a zero-based unsigned
   --  64-bit coordinate space.  This is the reviewed public format boundary;
   --  changing its width is source- and diagnostic-contract-incompatible.
   subtype Byte_Offset is Interfaces.Unsigned_64;

   type Error_Code is
     (No_Error,
      Unsupported_Profile,
      Incompatible_Profile,
      Invalid_State,
      Final_Input_Retracted,
      Invalid_Writer_Grammar,
      Writer_Interrupted,
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
      Depth_Exhausted,
      Name_Storage_Exhausted,
      Duplicate_Index_Exhausted,
      Offset_Exhausted,
      Destination_Exhausted,
      Destination_Failed,
      Commit_Failed,
      Abort_Failed);

   type Coordinate_Kind is
     (No_Coordinate, Source_Byte, Writer_Token_Byte, Staged_Output_Byte, JSON_Call_Ordinal);

   type Diagnostic is record
      Code                 : Error_Code;
      Coordinate           : Coordinate_Kind;
      Offset               : Byte_Offset;
      Secondary            : Error_Code;
      Secondary_Coordinate : Coordinate_Kind;
      Secondary_Offset     : Byte_Offset;
   end record;

   --  Clear sets both codes to No_Error, both coordinates to No_Coordinate,
   --  and both offsets to zero.  A primary offset is eligible only when its
   --  coordinate is not No_Coordinate.  Secondary coordinate and offset are
   --  eligible only when Secondary /= No_Error.
   procedure Clear (Item : out Diagnostic);
end Flyology_JSON.Errors;
