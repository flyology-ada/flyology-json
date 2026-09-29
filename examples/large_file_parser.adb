--  Parse one JSON file through fixed-size input and event buffers. File size
--  does not change these buffers. The example uses Preserve_Unchecked so a
--  large object cannot exhaust duplicate-name storage; applications that must
--  reject duplicates instantiate the strict shape and size both name stores.

with Ada.Command_Line;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Flyology_JSON.Errors;
with Flyology_JSON.Parsing;
with Flyology_JSON.Profiles;

procedure Large_File_Parser is
   package Errors renames Flyology_JSON.Errors;
   package Profiles renames Flyology_JSON.Profiles;
   package Parsing is new Flyology_JSON.Parsing (Profiles.Preserve_Unchecked);
   package Stream_IO renames Ada.Streams.Stream_IO;

   subtype Count is Ada.Streams.Stream_Element_Count;
   subtype Offset is Ada.Streams.Stream_Element_Offset;

   use type Count;
   use type Errors.Byte_Offset;
   use type Errors.Error_Code;
   use type Parsing.Drain_Stop;
   use type Parsing.Slice_Status;

   --  BEGIN large-file-setup
   --  This profile accepts each decoded member name in source order. It does
   --  not detect or select among duplicate names.
   Profile : constant Profiles.Parser_Profile :=
     (Syntax        => (Family => Profiles.RFC_8259, Version => 1),
      Unicode       => (Family => Profiles.Unicode_Scalars, Version => 1),
      Compatibility => (Family => Profiles.No_Extensions, Version => 1),
      BOM           => Profiles.Reject_BOM,
      Duplicates    => Profiles.Preserve_Unchecked,
      Top_Level     => Profiles.Accept_Any_Value);

   --  Both buffer lengths and all three parser capacities are application
   --  choices. They are deliberately small so the maintained fixtures cross
   --  boundaries. They are not library defaults or recommendations.
   Input_Buffer : Ada.Streams.Stream_Element_Array (1 .. 32);
   Events       : Parsing.Event_Array (1 .. 8);
   Parser       : Parsing.Parser
     (Maximum_Depth       => 2,
      Name_Octet_Capacity => 0,
      Name_Capacity       => 0);
   --  END large-file-setup

   File           : Stream_IO.File_Type;
   Diagnostic     : Errors.Diagnostic;
   Result         : Parsing.Drain_Result;
   Decoded_Octets : Errors.Byte_Offset := 0;
   Number_Octets  : Errors.Byte_Offset := 0;
   Accepted       : Boolean := False;

   --  BEGIN large-file-events
   --  Resolve one raw fragment while the exact producing input window is
   --  still unchanged. A consumer that retains Fragment must copy it here.
   procedure Count_Raw_Fragment
     (Item   : Parsing.Event;
      Input  : Ada.Streams.Stream_Element_Array;
      Origin : Errors.Byte_Offset;
      Total  : in out Errors.Byte_Offset)
   is
      Slice  : Parsing.Chunk_Range;
      Status : Parsing.Slice_Status;
   begin
      Parsing.Resolve_Raw_Range (Item, Origin, Input'Length, Slice, Status);
      if Status /= Parsing.Slice_Resolved then
         raise Program_Error with "expected a raw range in the producing input window";
      end if;

      if Slice.Octet_Length > 0 then
         declare
            First    : constant Offset := Input'First + Offset (Slice.First_Count);
            Last     : constant Offset := First + Offset (Slice.Octet_Length) - 1;
            Fragment : Ada.Streams.Stream_Element_Array renames Input (First .. Last);
         begin
            Total := Total + Errors.Byte_Offset (Fragment'Length);
         end;
      end if;
   end Count_Raw_Fragment;

   procedure Handle_Events
     (Input    : Ada.Streams.Stream_Element_Array;
      Origin   : Errors.Byte_Offset;
      Items    : Parsing.Event_Array;
      Produced : Count)
   is
   begin
      if Produced = 0 then
         return;
      end if;

      for Published in Count range 0 .. Produced - 1 loop
         declare
            Item : Parsing.Event renames Items (Items'First + Offset (Published));
         begin
            case Parsing.Kind (Item) is
               when Parsing.Name_Fragment | Parsing.String_Fragment =>
                  --  Unescaped UTF-8 can borrow the current input. An escape
                  --  or surrogate pair carries one decoded scalar inline.
                  case Parsing.Decoded_Kind (Item) is
                     when Parsing.Decoded_Is_Raw_Range =>
                        Count_Raw_Fragment (Item, Input, Origin, Decoded_Octets);

                     when Parsing.Decoded_Inline_Scalar =>
                        declare
                           Scalar : constant Parsing.Inline_Scalar := Parsing.Decoded_Scalar (Item);
                        begin
                           Decoded_Octets := Decoded_Octets + Errors.Byte_Offset (Scalar.Length);
                        end;

                     when Parsing.No_Decoded_Fragment =>
                        null;
                  end case;

               when Parsing.Number_Fragment =>
                  --  Number fragments are exact source octets. If conversion
                  --  is needed, perform it separately after bounded collection.
                  Count_Raw_Fragment (Item, Input, Origin, Number_Octets);

               when others =>
                  --  The application handles structure, literals, and token
                  --  boundaries here. Container lengths are not precomputed.
                  null;
            end case;
         end;
      end loop;
   end Handle_Events;
   --  END large-file-events

begin
   if Ada.Command_Line.Argument_Count /= 1 then
      raise Program_Error with "usage: large_file_parser PATH";
   end if;

   Parsing.Initialize (Parser, Profile, Diagnostic);
   if Diagnostic.Code /= Errors.No_Error then
      raise Program_Error with "parser initialization failed";
   end if;

   Stream_IO.Open (File, Stream_IO.In_File, Ada.Command_Line.Argument (1));

   --  BEGIN large-file-loop
   File_Loop :
   loop
      declare
         Last  : Offset;
         Used  : Count := 0;
         Final : Boolean;
      begin
         if Stream_IO.End_Of_File (File) then
            --  A null final window is necessary for an empty file.
            Last := Input_Buffer'First - 1;
            Final := True;
         else
            Stream_IO.Read (File, Input_Buffer, Last);
            Final := Stream_IO.End_Of_File (File);
         end if;

         Drain_Window :
         loop
            declare
               --  Used is a count from Input_Buffer'First. Input is null if
               --  Drain consumed the complete window but the parser still has
               --  an event or terminal result to report. Input is also null
               --  after a final read that exactly fills Input_Buffer.
               Input : Ada.Streams.Stream_Element_Array renames
                 Input_Buffer (Input_Buffer'First + Offset (Used) .. Last);
            begin
               Parsing.Drain
                 (Self         => Parser,
                  Input        => Input,
                  End_Of_Input => Final,
                  Events       => Events,
                  Result       => Result);

               --  Handle borrowed ranges before the next read can overwrite
               --  Input_Buffer. Only the produced prefix of Events is valid.
               Handle_Events (Input, Result.Input_Origin, Events, Result.Produced);
            end;

            Used := Used + Result.Consumed;
            case Result.Stop is
               when Parsing.Output_Full =>
                  --  Drain filled Events. Call Drain again with the remaining
                  --  suffix, which can be null. Do not refill Input_Buffer yet.
                  null;

               when Parsing.Drain_Need_Input =>
                  --  Drain_Need_Input consumed this complete nonfinal window.
                  if Final or else Used /= Count (Last - Input_Buffer'First + 1) then
                     raise Program_Error with "invalid parser input request";
                  end if;
                  exit Drain_Window;

               when Parsing.Drain_Document_Complete =>
                  --  Drain_Document_Complete is the only complete-document
                  --  acceptance gate. Commit the provisional candidate now.
                  Accepted := True;
                  exit File_Loop;

               when Parsing.Drain_Failed =>
                  raise Program_Error
                    with "JSON parsing failed: " & Errors.Error_Code'Image (Result.Diagnostic.Code)
                    & " at source byte" & Errors.Byte_Offset'Image (Result.Diagnostic.Offset);

               when Parsing.Drain_Rejected =>
                  raise Program_Error
                    with "parser call was rejected: "
                    & Errors.Error_Code'Image (Result.Diagnostic.Code);
            end case;
         end loop Drain_Window;
      end;
   end loop File_Loop;
   --  END large-file-loop

   Stream_IO.Close (File);
   if not Accepted then
      raise Program_Error with "the parser did not accept the complete document";
   end if;

   Ada.Text_IO.Put_Line
     ("accepted; decoded octets:"
      & Errors.Byte_Offset'Image (Decoded_Octets)
      & "; number octets:"
      & Errors.Byte_Offset'Image (Number_Octets));
exception
   when others =>
      Parsing.Abort_Document (Parser);
      if Stream_IO.Is_Open (File) then
         Stream_IO.Close (File);
      end if;
      raise;
end Large_File_Parser;
