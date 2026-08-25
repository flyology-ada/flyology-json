package body Flyology_JSON.Numbers.Unsigned_Integers is

   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Count;

   subtype Base is Value_Type'Base;
   subtype Count is Ada.Streams.Stream_Element_Count;
   subtype Offset is Ada.Streams.Stream_Element_Offset;

   Zero : constant Ada.Streams.Stream_Element := Character'Pos ('0');
   Nine : constant Ada.Streams.Stream_Element := Character'Pos ('9');
   Small_Modulus : constant Boolean := Value_Type'Modulus <= 10;
   Ten : constant Base := Base (10 mod Value_Type'Modulus);

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
      Range_Error : Boolean := False;
      Digits_Seen : Natural := 0;

      procedure Set_Failure (Status : Parse_Status) is
      begin
         Result := (Status => Status, Value => 0);
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

      while Position < Lexeme'Length loop
         declare
            Octet        : constant Ada.Streams.Stream_Element := Octet_At (Lexeme, Position);
            Digit_Number : Natural;
            Digit        : Base;
         begin
            if Octet not in Zero .. Nine then
               Set_Failure (Invalid_Syntax);
               return;
            end if;
            Digit_Number := Natural (Octet - Zero);
            Digit := Base'Mod (Digit_Number);

            if not Negative and then not Range_Error then
               if Natural (Digit) /= Digit_Number then
                  Range_Error := True;
               elsif Small_Modulus then
                  if Digits_Seen = 0 then
                     Accumulator := Digit;
                  else
                     Range_Error := True;
                  end if;
               else
                  if Accumulator > (Base (Value_Type'Last) - Digit) / Ten then
                     Range_Error := True;
                  else
                     Accumulator := Accumulator * Ten + Digit;
                  end if;
               end if;
            end if;
            Digits_Seen := Digits_Seen + 1;
         end;
         Position := Position + 1;
      end loop;

      if Negative then
         Set_Failure (Negative_Value);
      elsif Range_Error then
         Set_Failure (Above_Range);
      else
         Result := (Status => Converted, Value => Value_Type (Accumulator));
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
      elsif Small_Modulus then
         First := First - 1;
         Buffer (First) := Zero + Ada.Streams.Stream_Element (Work);
      else
         while Work /= 0 loop
            Digit := Work rem Ten;
            First := First - 1;
            Buffer (First) := Zero + Ada.Streams.Stream_Element (Digit);
            Work := Work / Ten;
         end loop;
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

end Flyology_JSON.Numbers.Unsigned_Integers;
