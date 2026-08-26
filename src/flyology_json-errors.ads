with Interfaces;

--  Nonraising JSON diagnostics with explicit coordinate systems.

package Flyology_JSON.Errors
  with Pure
is
   --  Absolute JSON streams and writer counters use a zero-based unsigned
   --  64-bit coordinate space.  This is the reviewed public format boundary;
   --  changing its width is source- and diagnostic-contract-incompatible.
   subtype Byte_Offset is Interfaces.Unsigned_64;

   --  Machine-readable reason for a failed or rejected parser or writer operation.
   --  @enum No_Error The operation has no error.
   --  @enum Unsupported_Profile A profile family or version is not implemented.
   --  @enum Incompatible_Profile The selected profile fields cannot be combined.
   --  @enum Invalid_State The operation is not legal in the current lifecycle state.
   --  @enum Final_Input_Retracted A later parser call changed latched final input from true to false.
   --  @enum Invalid_Writer_Grammar A writer call violates the JSON event grammar.
   --  @enum Writer_Interrupted An abnormal transfer interrupted an active writer call.
   --  @enum Unexpected_Token An input octet cannot begin or continue the required JSON construct.
   --  @enum Trailing_Input A complete root value is followed by a non-whitespace octet.
   --  @enum Truncated_Input Final input ended before the current JSON construct completed.
   --  @enum Invalid_Literal A `null`, `true`, or `false` spelling is invalid.
   --  @enum Invalid_Number A numeric lexeme violates strict JSON number syntax.
   --  @enum Invalid_Escape A string escape is not one of the JSON escape forms.
   --  @enum Invalid_UTF8 Input contains an invalid UTF-8 sequence.
   --  @enum Invalid_Surrogate A Unicode escape contains an unpaired or misordered surrogate.
   --  @enum Raw_Control_Character A string contains an unescaped control character.
   --  @enum Duplicate_Name A later object member repeats an earlier decoded member name.
   --  @enum Top_Level_Kind_Rejected The selected profile rejects the recognized root value kind.
   --  @enum Depth_Exhausted Opening another container would exceed the parser or writer depth.
   --  @enum Name_Storage_Exhausted Decoded duplicate-name storage cannot hold the active name.
   --  @enum Duplicate_Index_Exhausted The duplicate-name index cannot add another unique name.
   --  @enum Offset_Exhausted A zero-based source or writer counter cannot represent the next octet.
   --  @enum Destination_Exhausted The writer destination cannot stage all required output.
   --  @enum Destination_Failed The writer destination rejected a begin or write operation.
   --  @enum Commit_Failed The destination did not publish the completed document.
   --  @enum Abort_Failed The destination reported failure while ending unpublished staging.
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

   --  Coordinate system used by a diagnostic offset.
   --  @enum No_Coordinate The associated offset is ineligible and must not be observed.
   --  @enum Source_Byte A zero-based byte offset in the complete parser input stream.
   --  @enum Writer_Token_Byte A zero-based byte offset in the active writer token.
   --  @enum Staged_Output_Byte A zero-based byte offset in the unpublished destination output.
   --  @enum JSON_Call_Ordinal A zero-based ordinal for a semantic writer call.
   type Coordinate_Kind is
     (No_Coordinate, Source_Byte, Writer_Token_Byte, Staged_Output_Byte, JSON_Call_Ordinal);

   --  Primary failure and optional cleanup failure retained by an operation.
   --  @field Code Primary error code, or `No_Error` when the operation succeeded.
   --  @field Coordinate Coordinate system for `Offset`.
   --  @field Offset Primary zero-based position; eligible only when `Coordinate` is not
   --    `No_Coordinate`.
   --  @field Secondary Cleanup error code, or `No_Error` when cleanup did not add a failure.
   --  @field Secondary_Coordinate Coordinate system for `Secondary_Offset`.
   --  @field Secondary_Offset Cleanup-failure position; eligible only when `Secondary` is not
   --    `No_Error`.
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
   --  @param Item Diagnostic value to replace with the cleared representation.
   procedure Clear (Item : out Diagnostic);
end Flyology_JSON.Errors;
