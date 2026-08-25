with Ada.Streams;

generic
   type Value_Type is range <>;
package Flyology_JSON.Numbers.Signed_Integers is
   type Parse_Status is (Converted, Invalid_Syntax, Below_Range, Above_Range);

   --  Definite so a constrained out actual cannot fail copy-out.  Value is
   --  eligible only when Status = Converted; otherwise it remains a valid but
   --  unspecified Value_Type value.
   type Parse_Result is record
      Status : Parse_Status;
      Value  : Value_Type;
   end record;

   --  Parse accepts only a complete strict JSON integer spelling.  Fractions
   --  and exponents are invalid syntax, -0 converts to zero, and range is
   --  detected before arithmetic overflow.  No failure publishes a Value.
   procedure Parse
     (Lexeme : Ada.Streams.Stream_Element_Array; Result : out Parse_Result);

   --  Render emits exact base ten without a leading zero, exponent, or plus.
   --  On insufficient capacity it returns Produced = 0 and leaves Output
   --  unchanged.  This integer operation never returns Unsupported_Value.
   procedure Render
     (Value    : Value_Type;
      Output   : in out Ada.Streams.Stream_Element_Array;
      Produced : out Ada.Streams.Stream_Element_Count;
      Status   : out Numbers.Render_Status);
end Flyology_JSON.Numbers.Signed_Integers;
