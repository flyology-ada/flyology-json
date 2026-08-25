with Ada.Streams;
with Ada.Text_IO;
with Flyology_JSON.Errors;
with Flyology_JSON.Parsing;
with Flyology_JSON.Profiles;

procedure Streaming_Parser is
   package Errors renames Flyology_JSON.Errors;
   package Profiles renames Flyology_JSON.Profiles;
   package Parsing is new Flyology_JSON.Parsing (Profiles.Reject_Duplicates);

   subtype Count is Ada.Streams.Stream_Element_Count;
   subtype Offset is Ada.Streams.Stream_Element_Offset;

   use type Count;
   use type Errors.Error_Code;
   use type Parsing.Drain_Stop;

   function To_Octets
     (Text  : String;
      First : Offset) return Ada.Streams.Stream_Element_Array
   is
      Result : Ada.Streams.Stream_Element_Array
        (First .. First + Offset (Text'Length) - 1);
   begin
      for Position in Text'Range loop
         Result (First + Offset (Position - Text'First)) := Character'Pos (Text (Position));
      end loop;
      return Result;
   end To_Octets;

   --  BEGIN parser-setup
   Profile : constant Profiles.Parser_Profile :=
     (Syntax        => (Family => Profiles.RFC_8259, Version => 1),
      Unicode       => (Family => Profiles.Unicode_Scalars, Version => 1),
      Compatibility => (Family => Profiles.No_Extensions, Version => 1),
      BOM           => Profiles.Reject_BOM,
      Duplicates    => Profiles.Reject_Duplicates,
      Top_Level     => Profiles.Accept_Any_Value);

   --  These capacities are application choices for this example. They are not
   --  Flyology JSON defaults. The root object needs depth one. The name limits
   --  retain the two decoded names while that object is open.
   Parser : Parsing.Parser
     (Maximum_Depth       => 1,
      Name_Octet_Capacity => 12,
      Name_Capacity       => 3);

   --  Drain writes events into caller storage. The lower bound can be any
   --  Stream_Element_Offset value.
   Events     : Parsing.Event_Array (-4 .. 3);
   Diagnostic : Errors.Diagnostic;
   Accepted   : Boolean := False;
   --  END parser-setup

   --  BEGIN parser-loop
   procedure Feed
     (Chunk        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean)
   is
      Used   : Count := 0;
      Result : Parsing.Drain_Result;
   begin
      loop
         declare
            First : constant Offset := Chunk'First + Offset (Used);
         begin
            if Used < Chunk'Length then
               Parsing.Drain
                 (Parser,
                  Chunk (First .. Chunk'Last),
                  End_Of_Input,
                  Events,
                  Result);
            else
               declare
                  Empty : constant Ada.Streams.Stream_Element_Array (First .. First - 1) :=
                    [others => 0];
               begin
                  Parsing.Drain (Parser, Empty, End_Of_Input, Events, Result);
               end;
            end if;
         end;

         --  The caller can observe these events now, but it must keep any
         --  derived application value provisional until Document_Complete.
         if Result.Produced > 0 then
            for Published in Count range 0 .. Result.Produced - 1 loop
               Ada.Text_IO.Put_Line
                 (Parsing.Event_Kind'Image
                    (Parsing.Kind (Events (Events'First + Offset (Published)))));
            end loop;
         end if;

         Used := Used + Result.Consumed;
         case Result.Stop is
            when Parsing.Output_Full =>
               null;

            when Parsing.Drain_Need_Input =>
               if End_Of_Input or else Used /= Chunk'Length then
                  raise Program_Error with "parser requested input at an invalid boundary";
               end if;
               return;

            when Parsing.Drain_Document_Complete =>
               if not End_Of_Input or else Used /= Chunk'Length then
                  raise Program_Error with "parser completed before the final chunk ended";
               end if;
               Accepted := True;
               return;

            when Parsing.Drain_Failed | Parsing.Drain_Rejected =>
               raise Program_Error with
                 "JSON parsing failed: " & Errors.Error_Code'Image (Result.Diagnostic.Code);
         end case;
      end loop;
   end Feed;
   --  END parser-loop

   First_Chunk : constant Ada.Streams.Stream_Element_Array :=
     To_Octets ("{""message"":""A", -20);
   Final_Chunk : constant Ada.Streams.Stream_Element_Array :=
     To_Octets ("da"",""count"":2}", 50);
begin
   Parsing.Initialize (Parser, Profile, Diagnostic);
   if Diagnostic.Code /= Errors.No_Error then
      raise Program_Error with "parser initialization failed";
   end if;

   --  The split is inside the string. Any other byte boundary is also valid.
   Feed (First_Chunk, End_Of_Input => False);
   Feed (Final_Chunk, End_Of_Input => True);

   if not Accepted then
      raise Program_Error with "the parser did not accept the complete document";
   end if;
   Ada.Text_IO.Put_Line ("accepted complete document");
end Streaming_Parser;
