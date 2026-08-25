with Ada.Streams;
with Interfaces;

package Flyology_JSON.Numbers.Binary64 is
   --  An always-valid IEEE 754 binary64 interchange encoding.  Bit zero is the
   --  least-significant bit: bit 63 is the sign, bits 62 .. 52 are the biased
   --  exponent, and bits 51 .. 0 are the fraction.  This numeric mapping is
   --  independent of host byte order and requires no unchecked conversion.
   --  Using bits at this boundary lets validity-checked builds classify every
   --  NaN/infinity encoding without first loading an invalid floating value.
   subtype Encoding is Interfaces.Unsigned_64;

   type Parse_Status is
     (Converted_Exact, Converted_Rounded, Invalid_Syntax, Underflow, Overflow);

   --  Definite so constrained out actuals cannot fail copy-out.  Value is
   --  eligible only for Converted_Exact or Converted_Rounded; otherwise it is
   --  a valid but unspecified Encoding value.
   type Parse_Result is record
      Status : Parse_Status;
      Value  : Encoding;
   end record;

   --  Parse strict JSON syntax using IEEE 754 round-to-nearest, ties-to-even.
   --  Exact lexical -0 is Converted_Exact and publishes negative zero.  A
   --  nonzero value rounded to signed zero is Underflow and publishes no Value;
   --  finite overflow is Overflow and never publishes infinity.
   procedure Parse
     (Lexeme : Ada.Streams.Stream_Element_Array; Result : out Parse_Result);

   --  Emit the shortest strict JSON decimal that round-trips to the same
   --  finite binary64 encoding.  Equal-length fixed/exponent spellings prefer fixed;
   --  otherwise scientific notation is normalized to one nonzero digit before
   --  the decimal point.  Equally short round-tripping coefficients choose the
   --  one closest to the exact binary value, with an even final retained digit
   --  on an exact distance tie.  The exponent marker is lowercase, a positive
   --  exponent has no plus sign, and negative zero renders as -0.  Nonfinite
   --  NaN and infinity encodings are Unsupported_Value without materializing
   --  an invalid float.  On either failure Produced is zero and Output is unchanged.
   procedure Render_Shortest
     (Value    : Encoding;
      Output   : in out Ada.Streams.Stream_Element_Array;
      Produced : out Ada.Streams.Stream_Element_Count;
      Status   : out Numbers.Render_Status);
end Flyology_JSON.Numbers.Binary64;
