with Ada.Streams;

private package Flyology_JSON.Parser_Numbers
  with Pure
is

   type Number_State is private;

   type Transition_Result is (Transition_Accepted, Transition_Continues, Transition_Invalid);
   --  Accepted means that the prefix may end at the pushed octet; it may still
   --  accept more number octets. Continues means that a further number octet
   --  is required before the lexeme may end.

   procedure Reset (State : out Number_State);

   procedure Push
     (State : in out Number_State; Octet : Ada.Streams.Stream_Element; Result : out Transition_Result);
   --  Push one number-lexeme octet. The caller recognizes token delimiters and
   --  does not push them. An invalid transition returns Transition_Invalid and
   --  remains invalid until Reset; malformed lexemes do not raise an exception.

   function Accepting_End (State : Number_State) return Boolean;
   --  Whether the octets pushed since Reset form a complete strict JSON number.

private

   type Machine_State is
     (At_Start,
      After_Minus,
      At_Zero,
      In_Integer,
      After_Decimal_Point,
      In_Fraction,
      After_Exponent_Marker,
      After_Exponent_Sign,
      In_Exponent,
      Invalid_State);

   type Number_State is record
      Current : Machine_State := At_Start;
   end record;

end Flyology_JSON.Parser_Numbers;
