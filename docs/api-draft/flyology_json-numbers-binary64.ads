with Ada.Streams;
with Interfaces;

package Flyology_JSON.Numbers.Binary64 is
   subtype Value_Type is Interfaces.IEEE_Float_64;

   type Parse_Status is
     (Converted_Exact, Converted_Rounded, Invalid_Syntax, Underflow, Overflow);

   type Parse_Result (Status : Parse_Status := Invalid_Syntax) is record
      case Status is
         when Converted_Exact | Converted_Rounded =>
            Value : Value_Type;
         when Invalid_Syntax | Underflow | Overflow =>
            null;
      end case;
   end record;

   --  Parse strict JSON syntax using IEEE 754 round-to-nearest, ties-to-even.
   --  Exact lexical -0 is Converted_Exact and publishes negative zero.  A
   --  nonzero value rounded to signed zero is Underflow and publishes no Value;
   --  finite overflow is Overflow and never publishes infinity.
   procedure Parse
     (Lexeme : Ada.Streams.Stream_Element_Array; Result : out Parse_Result);

   --  Emit the shortest strict JSON decimal that round-trips to the same
   --  binary64 value.  Equal-length fixed/exponent spellings prefer fixed;
   --  otherwise scientific notation is normalized to one nonzero digit before
   --  the decimal point.  Equally short round-tripping coefficients choose the
   --  one closest to the exact binary value, with an even final retained digit
   --  on an exact distance tie.  The exponent marker is lowercase, a positive
   --  exponent has no plus sign, and negative zero renders as -0.  Nonfinite
   --  values are Unsupported_Value.  On either failure Produced is zero and
   --  Output is unchanged.
   procedure Render_Shortest
     (Value    : Value_Type;
      Output   : in out Ada.Streams.Stream_Element_Array;
      Produced : out Ada.Streams.Stream_Element_Count;
      Status   : out Numbers.Render_Status);
end Flyology_JSON.Numbers.Binary64;
