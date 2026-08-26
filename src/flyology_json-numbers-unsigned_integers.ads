--  Checked conversion and deterministic rendering for a caller-selected modular integer type.

with Ada.Streams;

generic
   --  Modular integer type converted and rendered without wrapping or truncation.
   type Value_Type is mod <>;
package Flyology_JSON.Numbers.Unsigned_Integers is
   --  Converts and renders one modular integer type without allocation.
   --  @formal Value_Type Modular integer type converted and rendered without wrapping or truncation.

   --  Result category for conversion of one complete strict JSON integer lexeme.
   --  @enum Converted Conversion succeeded and the result value is eligible.
   --  @enum Invalid_Syntax The lexeme is not a complete strict JSON integer spelling.
   --  @enum Negative_Value The lexeme is syntactically valid but has a leading minus sign.
   --  @enum Above_Range The mathematical integer is greater than `Value_Type'Last`.
   type Parse_Status is (Converted, Invalid_Syntax, Negative_Value, Above_Range);

   --  Definite so a constrained out actual cannot fail copy-out.  Value is
   --  eligible only when Status = Converted; otherwise it remains a valid but
   --  unspecified Value_Type value.
   --  @field Status Conversion outcome that controls whether `Value` is eligible.
   --  @field Value Converted integer when `Status` is `Converted`; otherwise unspecified.
   type Parse_Result is record
      Status : Parse_Status;
      Value  : Value_Type;
   end record;

   --  Parse accepts only a complete strict JSON integer spelling.  Fractions
   --  and exponents are invalid syntax.  Every syntactically valid negative
   --  spelling, including -0, returns Negative_Value.  Range is detected
   --  before modular arithmetic can wrap.  No failure publishes a Value.
   --  @param Lexeme Complete exact number-token octets with arbitrary Ada array bounds.
   --  @param Result Definite conversion result; its value is eligible only after `Converted`.
   procedure Parse (Lexeme : Ada.Streams.Stream_Element_Array; Result : out Parse_Result);

   --  Render emits exact base ten without a leading zero, exponent, or plus.
   --  On insufficient capacity it returns Produced = 0 and leaves Output
   --  unchanged.  This integer operation never returns Unsupported_Value.
   --  @param Value Modular integer to render.
   --  @param Output Caller storage that receives the complete spelling on success.
   --  @param Produced Number of octets written from `Output'First`, or zero on failure.
   --  @param Status Rendering outcome that controls whether the output prefix is published.
   procedure Render
     (Value    : Value_Type;
      Output   : in out Ada.Streams.Stream_Element_Array;
      Produced : out Ada.Streams.Stream_Element_Count;
      Status   : out Numbers.Render_Status);
end Flyology_JSON.Numbers.Unsigned_Integers;
