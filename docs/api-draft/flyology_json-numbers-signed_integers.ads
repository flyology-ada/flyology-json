with Ada.Streams;

generic
   type Value_Type is range <>;
package Flyology_JSON.Numbers.Signed_Integers is
   type Parse_Status is (Converted, Invalid_Syntax, Below_Range, Above_Range);

   type Parse_Result (Status : Parse_Status := Invalid_Syntax) is record
      case Status is
         when Converted =>
            Value : Value_Type;
         when Invalid_Syntax | Below_Range | Above_Range =>
            null;
      end case;
   end record;

   procedure Parse
     (Lexeme : Ada.Streams.Stream_Element_Array; Result : out Parse_Result);

   --  This integer operation never returns Unsupported_Value.
   procedure Render
     (Value    : Value_Type;
      Output   : in out Ada.Streams.Stream_Element_Array;
      Produced : out Ada.Streams.Stream_Element_Count;
      Status   : out Numbers.Render_Status);
end Flyology_JSON.Numbers.Signed_Integers;
