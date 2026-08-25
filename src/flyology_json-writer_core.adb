with Ada.Exceptions;
with Ada.Finalization;

package body Flyology_JSON.Writer_Core is

   package body Destination_Writers is

      use type Ada.Streams.Stream_Element;
      use type Ada.Streams.Stream_Element_Count;
      use type Byte_Offset;
      use Flyology_JSON.Destinations;
      use Flyology_JSON.Errors;
      use type Parser_Numbers.Transition_Result;
      use type Parser_UTF8.Blame_Position;
      use type Parser_UTF8.Feed_Status;

      subtype Element is Ada.Streams.Stream_Element;
      subtype Count is Ada.Streams.Stream_Element_Count;
      subtype Offset is Ada.Streams.Stream_Element_Offset;

      Quote             : constant Element := Character'Pos ('"');
      Reverse_Solidus   : constant Element := Character'Pos ('\');
      Comma             : constant Element := Character'Pos (',');
      Colon             : constant Element := Character'Pos (':');
      Object_Open       : constant Element := Character'Pos ('{');
      Object_Close      : constant Element := Character'Pos ('}');
      Array_Open        : constant Element := Character'Pos ('[');
      Array_Close       : constant Element := Character'Pos (']');
      Control_Last      : constant Element := 16#1F#;

      function Clear_Diagnostic return Writer_Core.Diagnostic is
        (Code                 => No_Error,
         Coordinate           => No_Coordinate,
         Offset               => 0,
         Secondary            => No_Error,
         Secondary_Coordinate => No_Coordinate,
         Secondary_Offset     => 0);

      function Make_Diagnostic
        (Code : Error_Code; Coordinate : Coordinate_Kind; At_Offset : Byte_Offset)
         return Writer_Core.Diagnostic
      is
        (Code                 => Code,
         Coordinate           => Coordinate,
         Offset               => At_Offset,
         Secondary            => No_Error,
         Secondary_Coordinate => No_Coordinate,
         Secondary_Offset     => 0);

      function Interrupted_Diagnostic (Self : Writer) return Writer_Core.Diagnostic is
        (Make_Diagnostic
           (Writer_Interrupted, JSON_Call_Ordinal, Self.Interrupted_Ordinal));

      procedure Publish_Primary
        (Self : in out Writer; Item : Writer_Core.Diagnostic)
      is
      begin
         if not Self.Primary_Valid then
            Self.Last_Diagnostic := Item;
            Self.Primary_Valid := True;
         end if;
      end Publish_Primary;

      procedure Add_Abort_Secondary
        (Self : in out Writer; Unknown_Staged_Prefix : Boolean)
      is
      begin
         Self.Last_Diagnostic.Secondary := Abort_Failed;
         if Unknown_Staged_Prefix then
            Self.Last_Diagnostic.Secondary_Coordinate := No_Coordinate;
            Self.Last_Diagnostic.Secondary_Offset := 0;
         else
            Self.Last_Diagnostic.Secondary_Coordinate := Staged_Output_Byte;
            Self.Last_Diagnostic.Secondary_Offset := Self.Next_Staged_Offset;
         end if;
      end Add_Abort_Secondary;

      procedure Run_Boundary (Action : not null access procedure) is
         Saved  : Ada.Exceptions.Exception_Occurrence;
         Raised : Boolean := False;

         type Transfer_Guard is new Ada.Finalization.Limited_Controlled with record
            Armed : Boolean := False with Atomic;
         end record;

         overriding procedure Finalize (Guard : in out Transfer_Guard) is
         begin
            if Guard.Armed then
               Guard.Armed := False;
               begin
                  Action.all;
               exception
                  when Occurrence : others =>
                     Ada.Exceptions.Save_Occurrence (Saved, Occurrence);
                     Raised := True;
               end;
            end if;
         end Finalize;
      begin
         declare
            Transfer : Transfer_Guard;
            pragma Unreferenced (Transfer);
         begin
            --  Everything needed by Finalize is initialized before this first
            --  atomic effect. An abnormal transfer before it starts no
            --  boundary operation; one after it invokes Finalize.
            Transfer.Armed := True;
         end;

         if Raised then
            Ada.Exceptions.Reraise_Occurrence (Saved);
         end if;
      end Run_Boundary;

      procedure Abort_Owned_Transaction
        (Self                  : in out Writer;
         Final_State           : Writer_State;
         Unknown_Staged_Prefix : Boolean := False)
      is
         procedure Perform is
            Status : Abort_Status;
         begin
            Self.Abort_Attempted := True;
            Destination_Abort (Self.Target.all, Status);
            Self.Owns_Transaction := False;

            if Status = Abort_Failed then
               if not Self.Primary_Valid then
                  Publish_Primary
                    (Self,
                     Make_Diagnostic
                       (Abort_Failed, Staged_Output_Byte, Self.Next_Staged_Offset));
               else
                  Add_Abort_Secondary (Self, Unknown_Staged_Prefix);
               end if;
            end if;
            Self.Current_State := Final_State;
         end Perform;
      begin
         if not Self.Owns_Transaction or else Self.Abort_Attempted then
            Self.Current_State := Final_State;
            return;
         end if;

         Run_Boundary (Perform'Access);
      end Abort_Owned_Transaction;

      procedure Fail
        (Self : in out Writer; Item : Writer_Core.Diagnostic; Diagnostic : out Writer_Core.Diagnostic)
      is
      begin
         Publish_Primary (Self, Item);
         Abort_Owned_Transaction (Self, Failed);
         Diagnostic := Self.Last_Diagnostic;
      end Fail;

      procedure Reject_State (Self : Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         if Self.Primary_Valid then
            Diagnostic := Self.Last_Diagnostic;
         elsif Self.In_Call then
            Diagnostic := Interrupted_Diagnostic (Self);
         else
            Diagnostic := Make_Diagnostic (Invalid_State, No_Coordinate, 0);
         end if;
      end Reject_State;

      procedure Reserve_Call
        (Self       : in out Writer;
         Ordinal    : out Byte_Offset;
         Succeeded  : out Boolean;
         Diagnostic : out Writer_Core.Diagnostic)
      is
      begin
         --  Keep the maximum offset available as the exact coordinate of the
         --  first rejected call; admitting it would require an unrepresentable
         --  next ordinal after the call.
         if Self.Next_Call_Ordinal = Byte_Offset'Last then
            Ordinal := Self.Next_Call_Ordinal;
            Fail
              (Self,
               Make_Diagnostic (Offset_Exhausted, JSON_Call_Ordinal, Self.Next_Call_Ordinal),
               Diagnostic);
            Succeeded := False;
            return;
         end if;

         Ordinal := Self.Next_Call_Ordinal;
         Self.Next_Call_Ordinal := Self.Next_Call_Ordinal + 1;
         Succeeded := True;
         Diagnostic := Clear_Diagnostic;
      end Reserve_Call;

      procedure Grammar_Failure
        (Self : in out Writer; Ordinal : Byte_Offset; Diagnostic : out Writer_Core.Diagnostic)
      is
      begin
         Fail
           (Self,
            Make_Diagnostic (Invalid_Writer_Grammar, JSON_Call_Ordinal, Ordinal),
            Diagnostic);
      end Grammar_Failure;

      procedure Emit
        (Self       : in out Writer;
         Data       : Ada.Streams.Stream_Element_Array;
         Succeeded  : out Boolean;
         Diagnostic : out Writer_Core.Diagnostic)
      is
         Written  : Count;
         Status   : Write_Status;
         Old      : constant Byte_Offset := Self.Next_Staged_Offset;
         Length   : constant Byte_Offset := Byte_Offset (Data'Length);
         Room     : constant Byte_Offset := Byte_Offset'Last - Old;
         Offered  : Count;
         Accepted : Byte_Offset;
      begin
         if Data'Length = 0 then
            Succeeded := True;
            Diagnostic := Clear_Diagnostic;
            return;
         end if;

         if Room = 0 then
            Fail
              (Self,
               Make_Diagnostic (Offset_Exhausted, Staged_Output_Byte, Byte_Offset'Last),
               Diagnostic);
            Succeeded := False;
            return;
         end if;

         Offered :=
           (if Length <= Room then Data'Length else Count (Room));
         Destination_Write
           (Self.Target.all,
            Data (Data'First .. Data'First + Offset (Offered - 1)),
            Written,
            Status);

         if Written > Offered then
            Written := 0;
            Status := Write_Failed;
         end if;
         Accepted := Byte_Offset (Written);

         case Status is
            when Write_Succeeded =>
               if Written /= Offered then
                  Fail
                    (Self,
                     Make_Diagnostic (Destination_Failed, Staged_Output_Byte, Old),
                     Diagnostic);
                  Succeeded := False;
                  return;
               end if;
               Self.Next_Staged_Offset := Old + Byte_Offset (Offered);
               if Offered = Data'Length then
                  Succeeded := True;
                  Diagnostic := Clear_Diagnostic;
               else
                  Fail
                    (Self,
                     Make_Diagnostic
                       (Offset_Exhausted, Staged_Output_Byte, Byte_Offset'Last),
                     Diagnostic);
                  Succeeded := False;
               end if;

            when Write_Exhausted =>
               if Written = Offered then
                  Fail
                    (Self,
                     Make_Diagnostic (Destination_Failed, Staged_Output_Byte, Old),
                     Diagnostic);
               else
                  Self.Next_Staged_Offset := Old + Accepted;
                  Fail
                    (Self,
                     Make_Diagnostic
                       (Destination_Exhausted, Staged_Output_Byte, Self.Next_Staged_Offset),
                     Diagnostic);
               end if;
               Succeeded := False;

            when Write_Failed =>
               if Written /= 0 then
                  Self.Next_Staged_Offset := Old + Accepted;
               end if;
               Fail
                 (Self,
                  Make_Diagnostic (Destination_Failed, Staged_Output_Byte, Old),
                  Diagnostic);
               Succeeded := False;
         end case;
      end Emit;

      procedure Emit_Byte
        (Self       : in out Writer;
         Value      : Element;
         Succeeded  : out Boolean;
         Diagnostic : out Writer_Core.Diagnostic)
      is
         Data : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [1 => Value];
      begin
         Emit (Self, Data, Succeeded, Diagnostic);
      end Emit_Byte;

      function Value_Is_Allowed (Self : Writer) return Boolean is
      begin
         if Self.Token /= No_Token or else Self.Root_Complete then
            return False;
         elsif Self.Depth = 0 then
            return not Self.Root_Started;
         elsif Self.Stack (Self.Depth).Kind = Array_Container then
            return True;
         else
            return Self.Stack (Self.Depth).Phase = Value_Required;
         end if;
      end Value_Is_Allowed;

      procedure Prepare_Value
        (Self       : in out Writer;
         Succeeded  : out Boolean;
         Diagnostic : out Writer_Core.Diagnostic)
      is
      begin
         if Self.Depth = 0 then
            Self.Root_Started := True;
            Succeeded := True;
            Diagnostic := Clear_Diagnostic;
         elsif Self.Stack (Self.Depth).Kind = Array_Container
           and then Self.Stack (Self.Depth).Has_Items
         then
            Emit_Byte (Self, Comma, Succeeded, Diagnostic);
         else
            Succeeded := True;
            Diagnostic := Clear_Diagnostic;
         end if;
      end Prepare_Value;

      procedure Complete_Value (Self : in out Writer) is
      begin
         if Self.Depth = 0 then
            Self.Root_Complete := True;
         elsif Self.Stack (Self.Depth).Kind = Array_Container then
            Self.Stack (Self.Depth).Has_Items := True;
         else
            Self.Stack (Self.Depth).Has_Items := True;
            Self.Stack (Self.Depth).Phase := Name_Or_End;
         end if;
      end Complete_Value;

      function Needs_Escape (Value : Element) return Boolean is
        (Value = Quote or else Value = Reverse_Solidus or else Value <= Control_Last);

      function Hex_Digit (Nibble : Element) return Element is
        (if Nibble < 10
         then Character'Pos ('0') + Nibble
         else Character'Pos ('A') + Nibble - 10);

      procedure Emit_Text
        (Self       : in out Writer;
         Value      : Ada.Streams.Stream_Element_Array;
         Succeeded  : out Boolean;
         Diagnostic : out Writer_Core.Diagnostic)
      is
         Base_Token      : constant Byte_Offset := Self.Next_Token_Offset;
         Token_Room      : constant Byte_Offset := Byte_Offset'Last - Base_Token;
         Limit           : Count;
         Position        : Count := 0;
         Run_First_Count : Count := 0;
         Probe           : Parser_UTF8.Decoder := Self.UTF8;
         Probe_Lead      : Byte_Offset := Self.UTF8_Lead_Offset;
         Probe_Pending   : Boolean := Parser_UTF8.Has_Pending_Octets (Probe);
         Result          : Parser_UTF8.Feed_Result;
         --  Private implementation scratch, not a public destination or token
         --  capacity. Large raw spans bypass it; escape-heavy spans amortize
         --  destination calls without allocation.
         Escape_Batch_Octets : constant Count := 256;
         Scratch : Ada.Streams.Stream_Element_Array
           (1 .. Offset (Escape_Batch_Octets));
         Scratch_Length : Count := 0;

         procedure Flush_Scratch is
         begin
            if Scratch_Length > 0 then
               Emit
                 (Self,
                  Scratch (Scratch'First .. Scratch'First + Offset (Scratch_Length - 1)),
                  Succeeded,
                  Diagnostic);
               if Succeeded then
                  Scratch_Length := 0;
               end if;
            else
               Succeeded := True;
               Diagnostic := Clear_Diagnostic;
            end if;
         end Flush_Scratch;

         procedure Append_Run
           (First_Count : Count; Exclusive_Last : Count)
         is
            Cursor    : Count := First_Count;
            Remaining : Count;
            Available : Count;
            Copied    : Count;
         begin
            while Cursor < Exclusive_Last loop
               Remaining := Exclusive_Last - Cursor;
               if Scratch_Length = 0 and then Remaining >= Escape_Batch_Octets then
                  Emit
                    (Self,
                     Value
                       (Value'First + Offset (Cursor)
                        .. Value'First + Offset (Exclusive_Last - 1)),
                     Succeeded,
                     Diagnostic);
                  return;
               end if;

               Available := Escape_Batch_Octets - Scratch_Length;
               Copied := Count'Min (Remaining, Available);
               for Item in Count range 0 .. Copied - 1 loop
                  Scratch (Scratch'First + Offset (Scratch_Length + Item)) :=
                    Value (Value'First + Offset (Cursor + Item));
               end loop;
               Scratch_Length := Scratch_Length + Copied;
               Cursor := Cursor + Copied;

               if Scratch_Length = Escape_Batch_Octets then
                  Flush_Scratch;
                  if not Succeeded then
                     return;
                  end if;
               end if;
            end loop;
            Succeeded := True;
            Diagnostic := Clear_Diagnostic;
         end Append_Run;

         procedure Append_Escape (Value : Element) is
            Encoded_Length : Count := 2;
         begin
            if Value not in 16#08# | 16#09# | 16#0A# | 16#0C# | 16#0D#
              and then Value /= Quote
              and then Value /= Reverse_Solidus
            then
               Encoded_Length := 6;
            end if;

            if Escape_Batch_Octets - Scratch_Length < Encoded_Length then
               Flush_Scratch;
               if not Succeeded then
                  return;
               end if;
            end if;

            Scratch_Length := Scratch_Length + 1;
            Scratch (Scratch'First + Offset (Scratch_Length - 1)) := Reverse_Solidus;
            Scratch_Length := Scratch_Length + 1;
            case Value is
               when 16#08# =>
                  Scratch (Scratch'First + Offset (Scratch_Length - 1)) :=
                    Character'Pos ('b');
               when 16#09# =>
                  Scratch (Scratch'First + Offset (Scratch_Length - 1)) :=
                    Character'Pos ('t');
               when 16#0A# =>
                  Scratch (Scratch'First + Offset (Scratch_Length - 1)) :=
                    Character'Pos ('n');
               when 16#0C# =>
                  Scratch (Scratch'First + Offset (Scratch_Length - 1)) :=
                    Character'Pos ('f');
               when 16#0D# =>
                  Scratch (Scratch'First + Offset (Scratch_Length - 1)) :=
                    Character'Pos ('r');
               when Quote | Reverse_Solidus =>
                  Scratch (Scratch'First + Offset (Scratch_Length - 1)) := Value;
               when others =>
                  Scratch (Scratch'First + Offset (Scratch_Length - 1)) :=
                    Character'Pos ('u');
                  Scratch_Length := Scratch_Length + 1;
                  Scratch (Scratch'First + Offset (Scratch_Length - 1)) :=
                    Character'Pos ('0');
                  Scratch_Length := Scratch_Length + 1;
                  Scratch (Scratch'First + Offset (Scratch_Length - 1)) :=
                    Character'Pos ('0');
                  Scratch_Length := Scratch_Length + 1;
                  Scratch (Scratch'First + Offset (Scratch_Length - 1)) :=
                    Hex_Digit (Value / 16);
                  Scratch_Length := Scratch_Length + 1;
                  Scratch (Scratch'First + Offset (Scratch_Length - 1)) :=
                    Hex_Digit (Value mod 16);
            end case;
            if Scratch_Length = Escape_Batch_Octets then
               Flush_Scratch;
               return;
            end if;
            Succeeded := True;
            Diagnostic := Clear_Diagnostic;
         end Append_Escape;
      begin
         if Value'Length = 0 then
            Succeeded := True;
            Diagnostic := Clear_Diagnostic;
            return;
         elsif Token_Room = 0 then
            Fail
              (Self,
               Make_Diagnostic (Offset_Exhausted, Writer_Token_Byte, Byte_Offset'Last),
               Diagnostic);
            Succeeded := False;
            return;
         end if;

         Limit :=
           (if Byte_Offset (Value'Length) <= Token_Room
            then Value'Length
            else Count (Token_Room));

         while Position < Limit loop
            if not Probe_Pending then
               Probe_Lead := Base_Token + Byte_Offset (Position);
            end if;

            --  ASCII is already a complete Unicode scalar. Keep the common
            --  unescaped path inside this scanner instead of calling the
            --  incremental UTF-8 state machine for every octet.
            if Probe_Pending
              or else Value (Value'First + Offset (Position)) >= 16#80#
            then
               Parser_UTF8.Feed
                 (Probe, Value (Value'First + Offset (Position)), Result);
               Probe_Pending := Result.Status = Parser_UTF8.Need_More;
               if Result.Status = Parser_UTF8.Invalid then
                  Append_Run (Run_First_Count, Position);
                  if not Succeeded then
                     return;
                  end if;
                  Flush_Scratch;
                  if not Succeeded then
                     return;
                  end if;

                  Fail
                    (Self,
                     Make_Diagnostic
                       (Invalid_UTF8,
                        Writer_Token_Byte,
                        (if Result.Blame = Parser_UTF8.Stored_Lead_Octet
                         then Probe_Lead
                         else Base_Token + Byte_Offset (Position))),
                     Diagnostic);
                  Succeeded := False;
                  return;
               end if;
            end if;

            if Needs_Escape (Value (Value'First + Offset (Position))) then
               Append_Run (Run_First_Count, Position);
               if not Succeeded then
                  return;
               end if;

               Append_Escape (Value (Value'First + Offset (Position)));
               if not Succeeded then
                  return;
               end if;
               Run_First_Count := Position + 1;
            end if;
            Position := Position + 1;
         end loop;

         Append_Run (Run_First_Count, Position);
         if not Succeeded then
            return;
         end if;
         Flush_Scratch;
         if not Succeeded then
            return;
         elsif Position < Value'Length then
            Fail
              (Self,
               Make_Diagnostic (Offset_Exhausted, Writer_Token_Byte, Byte_Offset'Last),
               Diagnostic);
            Succeeded := False;
         else
            Self.UTF8 := Probe;
            Self.UTF8_Lead_Offset := Probe_Lead;
            Self.Next_Token_Offset := Base_Token + Byte_Offset (Position);
            Succeeded := True;
            Diagnostic := Clear_Diagnostic;
         end if;
      end Emit_Text;

      procedure Initialize_Impl (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         if Self.Current_State /= Uninitialized then
            Reject_State (Self, Diagnostic);
            return;
         end if;

         Self.Current_State := Ready;
         Self.Last_Diagnostic := Clear_Diagnostic;
         Self.Primary_Valid := False;
         Self.In_Call := False;
         Self.Interrupted_Ordinal := 0;
         Self.Owns_Transaction := False;
         Self.Abort_Attempted := False;
         Self.Next_Staged_Offset := 0;
         Self.Next_Token_Offset := 0;
         Self.Next_Call_Ordinal := 0;
         Self.Depth := 0;
         Self.Root_Started := False;
         Self.Root_Complete := False;
         Self.Token := No_Token;
         Parser_UTF8.Reset (Self.UTF8);
         Parser_Numbers.Reset (Self.Number);
         Diagnostic := Clear_Diagnostic;
      end Initialize_Impl;

      procedure Reject_Profile_Impl
        (Self       : in out Writer;
         Code       : Error_Code;
         Diagnostic : out Writer_Core.Diagnostic)
      is
      begin
         if Self.In_Call
           or else Self.Current_State not in Uninitialized | Completed | Failed | Aborted
         then
            Reject_State (Self, Diagnostic);
            return;
         end if;

         Self.Current_State := Failed;
         Self.Last_Diagnostic := Clear_Diagnostic;
         Self.Primary_Valid := False;
         Self.In_Call := False;
         Self.Interrupted_Ordinal := 0;
         Self.Owns_Transaction := False;
         Self.Abort_Attempted := False;
         Self.Next_Staged_Offset := 0;
         Self.Next_Token_Offset := 0;
         Self.Next_Call_Ordinal := 0;
         Self.Depth := 0;
         Self.Root_Started := False;
         Self.Root_Complete := False;
         Self.Token := No_Token;
         Parser_UTF8.Reset (Self.UTF8);
         Parser_Numbers.Reset (Self.Number);
         Publish_Primary (Self, Make_Diagnostic (Code, No_Coordinate, 0));
         Diagnostic := Self.Last_Diagnostic;
      end Reject_Profile_Impl;

      procedure Begin_Document_Impl (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
         Ordinal  : Byte_Offset;
         Reserved : Boolean;
         Status   : Begin_Status;
      begin
         if Self.Current_State not in Ready | Active then
            Reject_State (Self, Diagnostic);
            return;
         end if;

         Reserve_Call (Self, Ordinal, Reserved, Diagnostic);
         if not Reserved then
            return;
         end if;

         if Self.Current_State = Active then
            Grammar_Failure (Self, Ordinal, Diagnostic);
            return;
         end if;

         Destination_Begin (Self.Target.all, Status);
         if Status = Begin_Succeeded then
            Self.Current_State := Active;
            Self.Owns_Transaction := True;
            Self.Abort_Attempted := False;
            Diagnostic := Clear_Diagnostic;
         else
            Publish_Primary
              (Self, Make_Diagnostic (Destination_Failed, Staged_Output_Byte, 0));
            Self.Current_State := Failed;
            Diagnostic := Self.Last_Diagnostic;
         end if;
      end Begin_Document_Impl;

      procedure Begin_Container
        (Self       : in out Writer;
         Kind       : Container_Kind;
         Opener     : Element;
         Ordinal    : Byte_Offset;
         Diagnostic : out Writer_Core.Diagnostic)
      is
         Succeeded : Boolean;
      begin
         if not Value_Is_Allowed (Self) then
            Grammar_Failure (Self, Ordinal, Diagnostic);
            return;
         elsif Self.Depth = Self.Maximum_Depth then
            Fail
              (Self,
               Make_Diagnostic (Depth_Exhausted, JSON_Call_Ordinal, Ordinal),
               Diagnostic);
            return;
         end if;

         Prepare_Value (Self, Succeeded, Diagnostic);
         if not Succeeded then
            return;
         end if;
         Emit_Byte (Self, Opener, Succeeded, Diagnostic);
         if not Succeeded then
            return;
         end if;

         Self.Depth := Self.Depth + 1;
         Self.Stack (Self.Depth) :=
           (Kind => Kind, Phase => Name_Or_End, Has_Items => False);
         Diagnostic := Clear_Diagnostic;
      end Begin_Container;

      procedure Begin_Object_Impl (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
         Ordinal  : Byte_Offset;
         Reserved : Boolean;
      begin
         if Self.Current_State /= Active then
            Reject_State (Self, Diagnostic);
            return;
         end if;
         Reserve_Call (Self, Ordinal, Reserved, Diagnostic);
         if Reserved then
            Begin_Container (Self, Object_Container, Object_Open, Ordinal, Diagnostic);
         end if;
      end Begin_Object_Impl;

      procedure Begin_Array_Impl (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
         Ordinal  : Byte_Offset;
         Reserved : Boolean;
      begin
         if Self.Current_State /= Active then
            Reject_State (Self, Diagnostic);
            return;
         end if;
         Reserve_Call (Self, Ordinal, Reserved, Diagnostic);
         if Reserved then
            Begin_Container (Self, Array_Container, Array_Open, Ordinal, Diagnostic);
         end if;
      end Begin_Array_Impl;

      procedure End_Container
        (Self       : in out Writer;
         Kind       : Container_Kind;
         Closer     : Element;
         Ordinal    : Byte_Offset;
         Diagnostic : out Writer_Core.Diagnostic)
      is
         Succeeded : Boolean;
      begin
         if Self.Token /= No_Token
           or else Self.Depth = 0
           or else Self.Stack (Self.Depth).Kind /= Kind
           or else (Kind = Object_Container and then Self.Stack (Self.Depth).Phase /= Name_Or_End)
         then
            Grammar_Failure (Self, Ordinal, Diagnostic);
            return;
         end if;

         Emit_Byte (Self, Closer, Succeeded, Diagnostic);
         if not Succeeded then
            return;
         end if;
         Self.Depth := Self.Depth - 1;
         Complete_Value (Self);
         Diagnostic := Clear_Diagnostic;
      end End_Container;

      procedure End_Object_Impl (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
         Ordinal  : Byte_Offset;
         Reserved : Boolean;
      begin
         if Self.Current_State /= Active then
            Reject_State (Self, Diagnostic);
            return;
         end if;
         Reserve_Call (Self, Ordinal, Reserved, Diagnostic);
         if Reserved then
            End_Container (Self, Object_Container, Object_Close, Ordinal, Diagnostic);
         end if;
      end End_Object_Impl;

      procedure End_Array_Impl (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
         Ordinal  : Byte_Offset;
         Reserved : Boolean;
      begin
         if Self.Current_State /= Active then
            Reject_State (Self, Diagnostic);
            return;
         end if;
         Reserve_Call (Self, Ordinal, Reserved, Diagnostic);
         if Reserved then
            End_Container (Self, Array_Container, Array_Close, Ordinal, Diagnostic);
         end if;
      end End_Array_Impl;

      procedure Begin_Name_Impl (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
         Ordinal  : Byte_Offset;
         Reserved : Boolean;
         Succeeded : Boolean;
      begin
         if Self.Current_State /= Active then
            Reject_State (Self, Diagnostic);
            return;
         end if;
         Reserve_Call (Self, Ordinal, Reserved, Diagnostic);
         if not Reserved then
            return;
         end if;

         if Self.Token /= No_Token
           or else Self.Depth = 0
           or else Self.Stack (Self.Depth).Kind /= Object_Container
           or else Self.Stack (Self.Depth).Phase /= Name_Or_End
         then
            Grammar_Failure (Self, Ordinal, Diagnostic);
            return;
         end if;

         if Self.Stack (Self.Depth).Has_Items then
            Emit_Byte (Self, Comma, Succeeded, Diagnostic);
            if not Succeeded then
               return;
            end if;
         end if;
         Emit_Byte (Self, Quote, Succeeded, Diagnostic);
         if not Succeeded then
            return;
         end if;

         Self.Token := Name_Token;
         Parser_UTF8.Reset (Self.UTF8);
         Diagnostic := Clear_Diagnostic;
      end Begin_Name_Impl;

      procedure Put_Text_Fragment
        (Self       : in out Writer;
         Expected   : Token_Kind;
         Value      : Ada.Streams.Stream_Element_Array;
         Diagnostic : out Writer_Core.Diagnostic)
      is
         Ordinal   : Byte_Offset;
         Reserved  : Boolean;
         Succeeded : Boolean;
      begin
         if Self.Current_State /= Active then
            Reject_State (Self, Diagnostic);
            return;
         end if;
         Reserve_Call (Self, Ordinal, Reserved, Diagnostic);
         if not Reserved then
            return;
         elsif Self.Token /= Expected then
            Grammar_Failure (Self, Ordinal, Diagnostic);
            return;
         end if;

         Emit_Text (Self, Value, Succeeded, Diagnostic);
         if Succeeded then
            Diagnostic := Clear_Diagnostic;
         end if;
      end Put_Text_Fragment;

      procedure Put_Name_Fragment_Impl
        (Self       : in out Writer;
         Value      : Ada.Streams.Stream_Element_Array;
         Diagnostic : out Writer_Core.Diagnostic)
      is
      begin
         Put_Text_Fragment (Self, Name_Token, Value, Diagnostic);
      end Put_Name_Fragment_Impl;

      procedure End_Name_Impl (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
         Ordinal   : Byte_Offset;
         Reserved  : Boolean;
         Succeeded : Boolean;
         Ending    : constant Ada.Streams.Stream_Element_Array (1 .. 2) := [Quote, Colon];
      begin
         if Self.Current_State /= Active then
            Reject_State (Self, Diagnostic);
            return;
         end if;
         Reserve_Call (Self, Ordinal, Reserved, Diagnostic);
         if not Reserved then
            return;
         elsif Self.Token /= Name_Token then
            Grammar_Failure (Self, Ordinal, Diagnostic);
            return;
         elsif Parser_UTF8.Has_Pending_Octets (Self.UTF8) then
            Fail
              (Self,
               Make_Diagnostic (Invalid_UTF8, Writer_Token_Byte, Self.Next_Token_Offset),
               Diagnostic);
            return;
         end if;

         Emit (Self, Ending, Succeeded, Diagnostic);
         if Succeeded then
            Self.Token := No_Token;
            Self.Stack (Self.Depth).Phase := Value_Required;
            Diagnostic := Clear_Diagnostic;
         end if;
      end End_Name_Impl;

      procedure Begin_String_Impl (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
         Ordinal   : Byte_Offset;
         Reserved  : Boolean;
         Succeeded : Boolean;
      begin
         if Self.Current_State /= Active then
            Reject_State (Self, Diagnostic);
            return;
         end if;
         Reserve_Call (Self, Ordinal, Reserved, Diagnostic);
         if not Reserved then
            return;
         elsif not Value_Is_Allowed (Self) then
            Grammar_Failure (Self, Ordinal, Diagnostic);
            return;
         end if;

         Prepare_Value (Self, Succeeded, Diagnostic);
         if not Succeeded then
            return;
         end if;
         Emit_Byte (Self, Quote, Succeeded, Diagnostic);
         if Succeeded then
            Self.Token := String_Token;
            Parser_UTF8.Reset (Self.UTF8);
            Diagnostic := Clear_Diagnostic;
         end if;
      end Begin_String_Impl;

      procedure Put_String_Fragment_Impl
        (Self       : in out Writer;
         Value      : Ada.Streams.Stream_Element_Array;
         Diagnostic : out Writer_Core.Diagnostic)
      is
      begin
         Put_Text_Fragment (Self, String_Token, Value, Diagnostic);
      end Put_String_Fragment_Impl;

      procedure End_String_Impl (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
         Ordinal   : Byte_Offset;
         Reserved  : Boolean;
         Succeeded : Boolean;
      begin
         if Self.Current_State /= Active then
            Reject_State (Self, Diagnostic);
            return;
         end if;
         Reserve_Call (Self, Ordinal, Reserved, Diagnostic);
         if not Reserved then
            return;
         elsif Self.Token /= String_Token then
            Grammar_Failure (Self, Ordinal, Diagnostic);
            return;
         elsif Parser_UTF8.Has_Pending_Octets (Self.UTF8) then
            Fail
              (Self,
               Make_Diagnostic (Invalid_UTF8, Writer_Token_Byte, Self.Next_Token_Offset),
               Diagnostic);
            return;
         end if;

         Emit_Byte (Self, Quote, Succeeded, Diagnostic);
         if Succeeded then
            Self.Token := No_Token;
            Complete_Value (Self);
            Diagnostic := Clear_Diagnostic;
         end if;
      end End_String_Impl;

      procedure Begin_Number_Impl (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
         Ordinal   : Byte_Offset;
         Reserved  : Boolean;
         Succeeded : Boolean;
      begin
         if Self.Current_State /= Active then
            Reject_State (Self, Diagnostic);
            return;
         end if;
         Reserve_Call (Self, Ordinal, Reserved, Diagnostic);
         if not Reserved then
            return;
         elsif not Value_Is_Allowed (Self) then
            Grammar_Failure (Self, Ordinal, Diagnostic);
            return;
         end if;

         Prepare_Value (Self, Succeeded, Diagnostic);
         if Succeeded then
            Self.Token := Number_Token;
            Parser_Numbers.Reset (Self.Number);
            Diagnostic := Clear_Diagnostic;
         end if;
      end Begin_Number_Impl;

      procedure Put_Number_Fragment_Impl
        (Self       : in out Writer;
         Value      : Ada.Streams.Stream_Element_Array;
         Diagnostic : out Writer_Core.Diagnostic)
      is
         Ordinal    : Byte_Offset;
         Reserved   : Boolean;
         Succeeded  : Boolean;
         Probe      : Parser_Numbers.Number_State := Self.Number;
         Result     : Parser_Numbers.Transition_Result;
         Base_Token : constant Byte_Offset := Self.Next_Token_Offset;
         Token_Room : constant Byte_Offset := Byte_Offset'Last - Base_Token;
         Limit      : Count;
         Position   : Count := 0;

         procedure Emit_Prefix is
         begin
            if Position > 0 then
               Emit
                 (Self,
                  Value (Value'First .. Value'First + Offset (Position - 1)),
                  Succeeded,
                  Diagnostic);
            else
               Succeeded := True;
               Diagnostic := Clear_Diagnostic;
            end if;
         end Emit_Prefix;
      begin
         if Self.Current_State /= Active then
            Reject_State (Self, Diagnostic);
            return;
         end if;
         Reserve_Call (Self, Ordinal, Reserved, Diagnostic);
         if not Reserved then
            return;
         elsif Self.Token /= Number_Token then
            Grammar_Failure (Self, Ordinal, Diagnostic);
            return;
         end if;

         if Value'Length = 0 then
            Diagnostic := Clear_Diagnostic;
            return;
         elsif Token_Room = 0 then
            Fail
              (Self,
               Make_Diagnostic (Offset_Exhausted, Writer_Token_Byte, Byte_Offset'Last),
               Diagnostic);
            return;
         end if;

         Limit :=
           (if Byte_Offset (Value'Length) <= Token_Room
            then Value'Length
            else Count (Token_Room));

         while Position < Limit loop
            Parser_Numbers.Push
              (Probe, Value (Value'First + Offset (Position)), Result);
            if Result = Parser_Numbers.Transition_Invalid then
               Emit_Prefix;
               if not Succeeded then
                  return;
               end if;
               Fail
                 (Self,
                  Make_Diagnostic
                    (Invalid_Number,
                     Writer_Token_Byte,
                     Base_Token + Byte_Offset (Position)),
                  Diagnostic);
               return;
            end if;
            Position := Position + 1;
         end loop;

         Emit_Prefix;
         if not Succeeded then
            return;
         elsif Position < Value'Length then
            Fail
              (Self,
               Make_Diagnostic (Offset_Exhausted, Writer_Token_Byte, Byte_Offset'Last),
               Diagnostic);
         else
            Self.Number := Probe;
            Self.Next_Token_Offset := Base_Token + Byte_Offset (Position);
            Diagnostic := Clear_Diagnostic;
         end if;
      end Put_Number_Fragment_Impl;

      procedure End_Number_Impl (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
         Ordinal  : Byte_Offset;
         Reserved : Boolean;
      begin
         if Self.Current_State /= Active then
            Reject_State (Self, Diagnostic);
            return;
         end if;
         Reserve_Call (Self, Ordinal, Reserved, Diagnostic);
         if not Reserved then
            return;
         elsif Self.Token /= Number_Token then
            Grammar_Failure (Self, Ordinal, Diagnostic);
            return;
         elsif not Parser_Numbers.Accepting_End (Self.Number) then
            Fail
              (Self,
               Make_Diagnostic (Invalid_Number, Writer_Token_Byte, Self.Next_Token_Offset),
               Diagnostic);
            return;
         end if;

         Self.Token := No_Token;
         Complete_Value (Self);
         Diagnostic := Clear_Diagnostic;
      end End_Number_Impl;

      procedure Put_Literal
        (Self       : in out Writer;
         Value      : Ada.Streams.Stream_Element_Array;
         Ordinal    : Byte_Offset;
         Diagnostic : out Writer_Core.Diagnostic)
      is
         Succeeded : Boolean;
      begin
         if not Value_Is_Allowed (Self) then
            Grammar_Failure (Self, Ordinal, Diagnostic);
            return;
         end if;
         Prepare_Value (Self, Succeeded, Diagnostic);
         if not Succeeded then
            return;
         end if;
         Emit (Self, Value, Succeeded, Diagnostic);
         if Succeeded then
            Complete_Value (Self);
            Diagnostic := Clear_Diagnostic;
         end if;
      end Put_Literal;

      procedure Put_Null_Impl (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
         Ordinal  : Byte_Offset;
         Reserved : Boolean;
         Value    : constant Ada.Streams.Stream_Element_Array (1 .. 4) :=
           [Character'Pos ('n'), Character'Pos ('u'), Character'Pos ('l'), Character'Pos ('l')];
      begin
         if Self.Current_State /= Active then
            Reject_State (Self, Diagnostic);
            return;
         end if;
         Reserve_Call (Self, Ordinal, Reserved, Diagnostic);
         if Reserved then
            Put_Literal (Self, Value, Ordinal, Diagnostic);
         end if;
      end Put_Null_Impl;

      procedure Put_Boolean_Impl
        (Self : in out Writer; Value : Boolean; Diagnostic : out Writer_Core.Diagnostic)
      is
         Ordinal  : Byte_Offset;
         Reserved : Boolean;
         True_Text : constant Ada.Streams.Stream_Element_Array (1 .. 4) :=
           [Character'Pos ('t'), Character'Pos ('r'), Character'Pos ('u'), Character'Pos ('e')];
         False_Text : constant Ada.Streams.Stream_Element_Array (1 .. 5) :=
           [Character'Pos ('f'),
            Character'Pos ('a'),
            Character'Pos ('l'),
            Character'Pos ('s'),
            Character'Pos ('e')];
      begin
         if Self.Current_State /= Active then
            Reject_State (Self, Diagnostic);
            return;
         end if;
         Reserve_Call (Self, Ordinal, Reserved, Diagnostic);
         if Reserved then
            if Value then
               Put_Literal (Self, True_Text, Ordinal, Diagnostic);
            else
               Put_Literal (Self, False_Text, Ordinal, Diagnostic);
            end if;
         end if;
      end Put_Boolean_Impl;

      procedure Finish_Document_Impl
        (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic)
      is
         Ordinal  : Byte_Offset;
         Reserved : Boolean;
         Status   : Commit_Status;
      begin
         if Self.Current_State not in Ready | Active then
            Reject_State (Self, Diagnostic);
            return;
         end if;
         Reserve_Call (Self, Ordinal, Reserved, Diagnostic);
         if not Reserved then
            return;
         elsif Self.Current_State = Ready
           or else Self.Token /= No_Token
           or else Self.Depth /= 0
           or else not Self.Root_Complete
         then
            Grammar_Failure (Self, Ordinal, Diagnostic);
            return;
         end if;

         begin
            Destination_Commit (Self.Target.all, Status);
         exception
            when others =>
               --  A raising Commit violates the generic contract and leaves
               --  publication unknowable. Prevent finalization from issuing
               --  an abort against a transaction that may already be public;
               --  the caller must immediately unwind without reuse.
               Self.Owns_Transaction := False;
               raise;
         end;
         if Status = Commit_Succeeded then
            Self.Owns_Transaction := False;
            Self.Current_State := Completed;
            Diagnostic := Clear_Diagnostic;
         else
            Fail
              (Self,
               Make_Diagnostic
                 (Commit_Failed, Staged_Output_Byte, Self.Next_Staged_Offset),
               Diagnostic);
         end if;
      end Finish_Document_Impl;

      procedure Abort_Document_Impl
        (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic)
      is
      begin
         if Self.In_Call then
            if not Self.Primary_Valid then
               Publish_Primary (Self, Interrupted_Diagnostic (Self));
            end if;
            Abort_Owned_Transaction
              (Self, Aborted, Unknown_Staged_Prefix => True);
            Self.In_Call := False;
            Diagnostic := Self.Last_Diagnostic;
            return;
         end if;

         case Self.Current_State is
            when Ready =>
               Self.Current_State := Aborted;
               Diagnostic := Clear_Diagnostic;

            when Active =>
               Abort_Owned_Transaction (Self, Aborted);
               Diagnostic := Self.Last_Diagnostic;

            when Interrupted | Failed | Aborted =>
               Diagnostic := Self.Last_Diagnostic;

            when Uninitialized | Completed =>
               Diagnostic := Clear_Diagnostic;
         end case;
      end Abort_Document_Impl;

      procedure Reset_Impl (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         if Self.In_Call then
            Reject_State (Self, Diagnostic);
            return;
         end if;

         if Self.Current_State not in Completed | Failed | Aborted then
            Reject_State (Self, Diagnostic);
            return;
         end if;

         Self.Current_State := Uninitialized;
         Initialize_Impl (Self, Diagnostic);
      end Reset_Impl;

      procedure Enter_Hot_Call
        (Self       : in out Writer;
         Execute    : out Boolean;
         Diagnostic : out Writer_Core.Diagnostic)
      is
         Ordinal  : Byte_Offset;
         Reserved : Boolean;
      begin
         if Self.In_Call or else Self.Current_State not in Ready | Active then
            Reject_State (Self, Diagnostic);
            Execute := False;
            return;
         end if;

         Self.Interrupted_Ordinal := Self.Next_Call_Ordinal;
         Self.In_Call := True;

         if Self.Current_State = Ready then
            Reserve_Call (Self, Ordinal, Reserved, Diagnostic);
            if Reserved then
               Grammar_Failure (Self, Ordinal, Diagnostic);
            end if;
            Self.In_Call := False;
            Execute := False;
         else
            Execute := True;
         end if;
      end Enter_Hot_Call;

      generic
         with procedure Implementation
           (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic);
      procedure Hot_Simple_Call
        (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic);

      procedure Hot_Simple_Call
        (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic)
      is
         Execute : Boolean;
      begin
         Enter_Hot_Call (Self, Execute, Diagnostic);
         if Execute then
            Implementation (Self, Diagnostic);
            Self.In_Call := False;
         end if;
      end Hot_Simple_Call;

      generic
         with procedure Implementation
           (Self       : in out Writer;
            Value      : Ada.Streams.Stream_Element_Array;
            Diagnostic : out Writer_Core.Diagnostic);
      procedure Hot_Fragment_Call
        (Self       : in out Writer;
         Value      : Ada.Streams.Stream_Element_Array;
         Diagnostic : out Writer_Core.Diagnostic);

      procedure Hot_Fragment_Call
        (Self       : in out Writer;
         Value      : Ada.Streams.Stream_Element_Array;
         Diagnostic : out Writer_Core.Diagnostic)
      is
         Execute : Boolean;
      begin
         Enter_Hot_Call (Self, Execute, Diagnostic);
         if Execute then
            Implementation (Self, Value, Diagnostic);
            Self.In_Call := False;
         end if;
      end Hot_Fragment_Call;

      generic
         with procedure Implementation
           (Self : in out Writer; Value : Boolean; Diagnostic : out Writer_Core.Diagnostic);
      procedure Hot_Boolean_Call
        (Self : in out Writer; Value : Boolean; Diagnostic : out Writer_Core.Diagnostic);

      procedure Hot_Boolean_Call
        (Self : in out Writer; Value : Boolean; Diagnostic : out Writer_Core.Diagnostic)
      is
         Execute : Boolean;
      begin
         Enter_Hot_Call (Self, Execute, Diagnostic);
         if Execute then
            Implementation (Self, Value, Diagnostic);
            Self.In_Call := False;
         end if;
      end Hot_Boolean_Call;

      generic
         Allow_Interrupted : Boolean := False;
         with procedure Implementation
           (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic);
      procedure Boundary_Simple_Call
        (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic);

      procedure Boundary_Simple_Call
        (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic)
      is
         procedure Perform is
         begin
            Implementation (Self, Diagnostic);
         end Perform;
      begin
         if Self.In_Call and then not Allow_Interrupted then
            Reject_State (Self, Diagnostic);
            return;
         end if;
         Run_Boundary (Perform'Access);
      end Boundary_Simple_Call;

      procedure Boundary_Initialize is new Boundary_Simple_Call
        (Implementation => Initialize_Impl);
      procedure Boundary_Begin_Document is new Boundary_Simple_Call
        (Implementation => Begin_Document_Impl);
      procedure Hot_Begin_Object is new Hot_Simple_Call (Begin_Object_Impl);
      procedure Hot_End_Object is new Hot_Simple_Call (End_Object_Impl);
      procedure Hot_Begin_Array is new Hot_Simple_Call (Begin_Array_Impl);
      procedure Hot_End_Array is new Hot_Simple_Call (End_Array_Impl);
      procedure Hot_Begin_Name is new Hot_Simple_Call (Begin_Name_Impl);
      procedure Hot_Put_Name_Fragment is new Hot_Fragment_Call (Put_Name_Fragment_Impl);
      procedure Hot_End_Name is new Hot_Simple_Call (End_Name_Impl);
      procedure Hot_Begin_String is new Hot_Simple_Call (Begin_String_Impl);
      procedure Hot_Put_String_Fragment is new Hot_Fragment_Call (Put_String_Fragment_Impl);
      procedure Hot_End_String is new Hot_Simple_Call (End_String_Impl);
      procedure Hot_Begin_Number is new Hot_Simple_Call (Begin_Number_Impl);
      procedure Hot_Put_Number_Fragment is new Hot_Fragment_Call (Put_Number_Fragment_Impl);
      procedure Hot_End_Number is new Hot_Simple_Call (End_Number_Impl);
      procedure Hot_Put_Null is new Hot_Simple_Call (Put_Null_Impl);
      procedure Hot_Put_Boolean is new Hot_Boolean_Call (Put_Boolean_Impl);
      procedure Boundary_Finish_Document is new Boundary_Simple_Call
        (Implementation => Finish_Document_Impl);
      procedure Boundary_Abort_Document is new Boundary_Simple_Call
        (Allow_Interrupted => True, Implementation => Abort_Document_Impl);
      procedure Boundary_Reset is new Boundary_Simple_Call
        (Implementation => Reset_Impl);

      procedure Initialize (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Boundary_Initialize (Self, Diagnostic);
      end Initialize;

      procedure Reject_Profile
        (Self       : in out Writer;
         Code       : Error_Code;
         Diagnostic : out Writer_Core.Diagnostic)
      is
         procedure Perform is
         begin
            Reject_Profile_Impl (Self, Code, Diagnostic);
         end Perform;
      begin
         if Self.In_Call then
            Reject_State (Self, Diagnostic);
            return;
         end if;
         Run_Boundary (Perform'Access);
      end Reject_Profile;

      procedure Begin_Document (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Boundary_Begin_Document (Self, Diagnostic);
      end Begin_Document;

      procedure Begin_Object (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Hot_Begin_Object (Self, Diagnostic);
      end Begin_Object;

      procedure End_Object (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Hot_End_Object (Self, Diagnostic);
      end End_Object;

      procedure Begin_Array (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Hot_Begin_Array (Self, Diagnostic);
      end Begin_Array;

      procedure End_Array (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Hot_End_Array (Self, Diagnostic);
      end End_Array;

      procedure Begin_Name (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Hot_Begin_Name (Self, Diagnostic);
      end Begin_Name;

      procedure Put_Name_Fragment
        (Self       : in out Writer;
         Value      : Ada.Streams.Stream_Element_Array;
         Diagnostic : out Writer_Core.Diagnostic)
      is
      begin
         Hot_Put_Name_Fragment (Self, Value, Diagnostic);
      end Put_Name_Fragment;

      procedure End_Name (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Hot_End_Name (Self, Diagnostic);
      end End_Name;

      procedure Begin_String (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Hot_Begin_String (Self, Diagnostic);
      end Begin_String;

      procedure Put_String_Fragment
        (Self       : in out Writer;
         Value      : Ada.Streams.Stream_Element_Array;
         Diagnostic : out Writer_Core.Diagnostic)
      is
      begin
         Hot_Put_String_Fragment (Self, Value, Diagnostic);
      end Put_String_Fragment;

      procedure Put_String_Fragment_Unguarded_For_Test
        (Self       : in out Writer;
         Value      : Ada.Streams.Stream_Element_Array;
         Diagnostic : out Errors.Diagnostic)
      is
      begin
         Put_String_Fragment_Impl (Self, Value, Diagnostic);
      end Put_String_Fragment_Unguarded_For_Test;

      procedure End_String (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Hot_End_String (Self, Diagnostic);
      end End_String;

      procedure Begin_Number (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Hot_Begin_Number (Self, Diagnostic);
      end Begin_Number;

      procedure Put_Number_Fragment
        (Self       : in out Writer;
         Value      : Ada.Streams.Stream_Element_Array;
         Diagnostic : out Writer_Core.Diagnostic)
      is
      begin
         Hot_Put_Number_Fragment (Self, Value, Diagnostic);
      end Put_Number_Fragment;

      procedure End_Number (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Hot_End_Number (Self, Diagnostic);
      end End_Number;

      procedure Put_Null (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Hot_Put_Null (Self, Diagnostic);
      end Put_Null;

      procedure Put_Boolean
        (Self : in out Writer; Value : Boolean; Diagnostic : out Writer_Core.Diagnostic)
      is
      begin
         Hot_Put_Boolean (Self, Value, Diagnostic);
      end Put_Boolean;

      procedure Finish_Document (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Boundary_Finish_Document (Self, Diagnostic);
      end Finish_Document;

      procedure Abort_Document (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Boundary_Abort_Document (Self, Diagnostic);
      end Abort_Document;

      procedure Reset (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Boundary_Reset (Self, Diagnostic);
      end Reset;

      function State (Self : Writer) return Writer_State is
        (if Self.In_Call then Interrupted else Self.Current_State);

      function Terminal_Diagnostic (Self : Writer) return Writer_Core.Diagnostic is
        (if Self.Primary_Valid then Self.Last_Diagnostic
         elsif Self.In_Call then Interrupted_Diagnostic (Self)
         else Self.Last_Diagnostic);

      procedure Cleanup (Self : in out Writer) is
      begin
         if Self.In_Call and then not Self.Primary_Valid then
            Publish_Primary (Self, Interrupted_Diagnostic (Self));
         end if;

         if Self.Owns_Transaction then
            Abort_Owned_Transaction
              (Self,
               Aborted,
               Unknown_Staged_Prefix => Self.In_Call);
         elsif Self.In_Call then
            Self.Current_State := Aborted;
         end if;
         Self.In_Call := False;
      exception
         when others =>
            --  The destination violated its nonraising contract during scope
            --  cleanup. The sole public controlled owner suppresses it while
            --  unwinding and makes no recoverability claim.
            Self.In_Call := False;
            Self.Current_State := Aborted;
      end Cleanup;

      procedure Set_Offsets_For_Test
        (Self        : in out Writer;
         Next_Staged : Byte_Offset;
         Next_Token  : Byte_Offset)
      is
      begin
         Self.Next_Staged_Offset := Next_Staged;
         Self.Next_Token_Offset := Next_Token;
      end Set_Offsets_For_Test;

   end Destination_Writers;

end Flyology_JSON.Writer_Core;
