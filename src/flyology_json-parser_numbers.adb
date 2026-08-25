package body Flyology_JSON.Parser_Numbers is

   use type Ada.Streams.Stream_Element;

   Minus         : constant Ada.Streams.Stream_Element := Character'Pos ('-');
   Plus          : constant Ada.Streams.Stream_Element := Character'Pos ('+');
   Decimal_Point : constant Ada.Streams.Stream_Element := Character'Pos ('.');
   Lower_E       : constant Ada.Streams.Stream_Element := Character'Pos ('e');
   Upper_E       : constant Ada.Streams.Stream_Element := Character'Pos ('E');
   Zero          : constant Ada.Streams.Stream_Element := Character'Pos ('0');
   Nine          : constant Ada.Streams.Stream_Element := Character'Pos ('9');

   function Is_Digit (Octet : Ada.Streams.Stream_Element) return Boolean
   is (Octet in Zero .. Nine);

   function Is_Nonzero_Digit (Octet : Ada.Streams.Stream_Element) return Boolean
   is (Octet in Zero + 1 .. Nine);

   function Is_Exponent_Marker (Octet : Ada.Streams.Stream_Element) return Boolean
   is (Octet = Lower_E or else Octet = Upper_E);

   function Accepting_End (State : Number_State) return Boolean
   is (State.Current in At_Zero | In_Integer | In_Fraction | In_Exponent);

   function Scanning_Integer_Digits (State : Number_State) return Boolean
   is (State.Current = In_Integer);

   procedure Reset (State : out Number_State) is
   begin
      State.Current := At_Start;
   end Reset;

   procedure Push
     (State : in out Number_State; Octet : Ada.Streams.Stream_Element; Result : out Transition_Result) is
   begin
      case State.Current is
         when At_Start              =>
            if Octet = Minus then
               State.Current := After_Minus;
            elsif Octet = Zero then
               State.Current := At_Zero;
            elsif Is_Nonzero_Digit (Octet) then
               State.Current := In_Integer;
            else
               State.Current := Invalid_State;
            end if;

         when After_Minus           =>
            if Octet = Zero then
               State.Current := At_Zero;
            elsif Is_Nonzero_Digit (Octet) then
               State.Current := In_Integer;
            else
               State.Current := Invalid_State;
            end if;

         when At_Zero               =>
            if Octet = Decimal_Point then
               State.Current := After_Decimal_Point;
            elsif Is_Exponent_Marker (Octet) then
               State.Current := After_Exponent_Marker;
            else
               State.Current := Invalid_State;
            end if;

         when In_Integer            =>
            if Is_Digit (Octet) then
               null;
            elsif Octet = Decimal_Point then
               State.Current := After_Decimal_Point;
            elsif Is_Exponent_Marker (Octet) then
               State.Current := After_Exponent_Marker;
            else
               State.Current := Invalid_State;
            end if;

         when After_Decimal_Point   =>
            if Is_Digit (Octet) then
               State.Current := In_Fraction;
            else
               State.Current := Invalid_State;
            end if;

         when In_Fraction           =>
            if Is_Digit (Octet) then
               null;
            elsif Is_Exponent_Marker (Octet) then
               State.Current := After_Exponent_Marker;
            else
               State.Current := Invalid_State;
            end if;

         when After_Exponent_Marker =>
            if Octet = Plus or else Octet = Minus then
               State.Current := After_Exponent_Sign;
            elsif Is_Digit (Octet) then
               State.Current := In_Exponent;
            else
               State.Current := Invalid_State;
            end if;

         when After_Exponent_Sign   =>
            if Is_Digit (Octet) then
               State.Current := In_Exponent;
            else
               State.Current := Invalid_State;
            end if;

         when In_Exponent           =>
            if not Is_Digit (Octet) then
               State.Current := Invalid_State;
            end if;

         when Invalid_State         =>
            null;
      end case;

      if State.Current = Invalid_State then
         Result := Transition_Invalid;
      elsif Accepting_End (State) then
         Result := Transition_Accepted;
      else
         Result := Transition_Continues;
      end if;
   end Push;

end Flyology_JSON.Parser_Numbers;
