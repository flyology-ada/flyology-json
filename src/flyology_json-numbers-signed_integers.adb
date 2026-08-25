package body Flyology_JSON.Numbers.Signed_Integers is

   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Count;

   subtype Base is Value_Type'Base;
   subtype Count is Ada.Streams.Stream_Element_Count;
   subtype Offset is Ada.Streams.Stream_Element_Offset;

   Zero : constant Ada.Streams.Stream_Element := Character'Pos ('0');
   Nine : constant Ada.Streams.Stream_Element := Character'Pos ('9');

   function Octet_At
     (Value : Ada.Streams.Stream_Element_Array; Position : Count)
      return Ada.Streams.Stream_Element
   is (Value (Value'First + Offset (Position)));

   procedure Parse
     (Lexeme : Ada.Streams.Stream_Element_Array; Result : out Parse_Result)
   is
      Negative    : Boolean := False;
      Position    : Count := 0;
      Accumulator : Base := 0;
      Limit       : Base := 0;
      Range_Error : Parse_Status := Converted;
      Candidate   : Base := 0;

      procedure Set_Failure (Status : Parse_Status) is
      begin
         Result := (Status => Status, Value => Value_Type'First);
      end Set_Failure;
   begin
      if Lexeme'Length = 0 then
         Set_Failure (Invalid_Syntax);
         return;
      end if;

      if Octet_At (Lexeme, Position) = Character'Pos ('-') then
         Negative := True;
         Position := Position + 1;
         if Position = Lexeme'Length then
            Set_Failure (Invalid_Syntax);
            return;
         end if;
      end if;

      if Octet_At (Lexeme, Position) not in Zero .. Nine then
         Set_Failure (Invalid_Syntax);
         return;
      elsif Octet_At (Lexeme, Position) = Zero
        and then Lexeme'Length - Position > 1
      then
         Set_Failure (Invalid_Syntax);
         return;
      end if;

      --  Accumulate negatively so Value_Type'First remains representable for
      --  an asymmetric two's-complement base range.  Sign-incompatible
      --  subtypes still scan the complete spelling before reporting range.
      if Negative then
         if Value_Type'First > 0 then
            Range_Error := Below_Range;
         else
            Limit := Base (Value_Type'First);
         end if;
      elsif Value_Type'Last < 0 then
         Range_Error := Above_Range;
      else
         Limit := -Base (Value_Type'Last);
      end if;

      while Position < Lexeme'Length loop
         declare
            Octet : constant Ada.Streams.Stream_Element := Octet_At (Lexeme, Position);
            Digit : Base;
         begin
            if Octet not in Zero .. Nine then
               Set_Failure (Invalid_Syntax);
               return;
            end if;
            Digit := Base (Octet - Zero);

            if Range_Error = Converted then
               if Accumulator < Limit / 10 then
                  Range_Error := (if Negative then Below_Range else Above_Range);
               else
                  Accumulator := Accumulator * 10;
                  if Accumulator < Limit + Digit then
                     Range_Error := (if Negative then Below_Range else Above_Range);
                  else
                     Accumulator := Accumulator - Digit;
                  end if;
               end if;
            end if;
         end;
         Position := Position + 1;
      end loop;

      if Range_Error /= Converted then
         case Range_Error is
            when Below_Range =>
               Set_Failure (Below_Range);
            when Above_Range =>
               Set_Failure (Above_Range);
            when Converted | Invalid_Syntax =>
               raise Program_Error;
         end case;
      else
         Candidate := (if Negative then Accumulator else -Accumulator);
         if Candidate < Base (Value_Type'First) then
            Set_Failure (Below_Range);
         elsif Candidate > Base (Value_Type'Last) then
            Set_Failure (Above_Range);
         else
            Result := (Status => Converted, Value => Value_Type (Candidate));
         end if;
      end if;
   end Parse;

   procedure Render
     (Value    : Value_Type;
      Output   : in out Ada.Streams.Stream_Element_Array;
      Produced : out Ada.Streams.Stream_Element_Count;
      Status   : out Numbers.Render_Status)
   is
      Buffer : Ada.Streams.Stream_Element_Array (1 .. Offset (Value_Type'Size + 1));
      First  : Offset := Buffer'Last + 1;
      Work   : Base := Base (Value);
      Digit  : Base;
   begin
      if Work = 0 then
         First := First - 1;
         Buffer (First) := Zero;
      else
         while Work /= 0 loop
            Digit := Work rem 10;
            if Digit < 0 then
               Digit := -Digit;
            end if;
            First := First - 1;
            Buffer (First) := Zero + Ada.Streams.Stream_Element (Digit);
            Work := Work / 10;
         end loop;
         if Value < 0 then
            First := First - 1;
            Buffer (First) := Character'Pos ('-');
         end if;
      end if;

      Produced := Buffer'Last - First + 1;
      if Output'Length < Produced then
         Produced := 0;
         Status := Numbers.Output_Too_Small;
         return;
      end if;

      for Position in Count range 0 .. Produced - 1 loop
         Output (Output'First + Offset (Position)) := Buffer (First + Offset (Position));
      end loop;
      Status := Numbers.Rendered;
   end Render;

end Flyology_JSON.Numbers.Signed_Integers;
