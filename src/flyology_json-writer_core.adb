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

      procedure Add_Abort_Secondary (Self : in out Writer) is
      begin
         Self.Last_Diagnostic.Secondary := Abort_Failed;
         Self.Last_Diagnostic.Secondary_Coordinate := Staged_Output_Byte;
         Self.Last_Diagnostic.Secondary_Offset := Self.Next_Staged_Offset;
      end Add_Abort_Secondary;

      procedure Abort_Owned_Transaction
        (Self : in out Writer; Final_State : Writer_State)
      is
      begin
         if not Self.Owns_Transaction or else Self.Abort_Attempted then
            Self.Current_State := Final_State;
            return;
         end if;

         declare
            --  Ada RM 9.8 makes Initialize abort-deferred. Keep the destination
            --  call and both ownership transitions inside that portable
            --  language-defined region; there is no tasking check on writes.
            type Abort_Transfer is new Ada.Finalization.Limited_Controlled with null record;

            overriding procedure Initialize (Guard : in out Abort_Transfer) is
               pragma Unreferenced (Guard);
               Status : Abort_Status;
            begin
               Self.Abort_Attempted := True;
               Destination_Abort (Self.Target.all, Status);
               Self.Owns_Transaction := False;

               if Status = Abort_Failed then
                  if Self.Last_Diagnostic.Code = No_Error then
                     Self.Last_Diagnostic :=
                       Make_Diagnostic
                         (Abort_Failed, Staged_Output_Byte, Self.Next_Staged_Offset);
                  else
                     Add_Abort_Secondary (Self);
                  end if;
               end if;
               Self.Current_State := Final_State;
            end Initialize;

            Transfer : Abort_Transfer;
            pragma Unreferenced (Transfer);
         begin
            null;
         end;
      end Abort_Owned_Transaction;

      procedure Fail
        (Self : in out Writer; Item : Writer_Core.Diagnostic; Diagnostic : out Writer_Core.Diagnostic)
      is
      begin
         if Self.Last_Diagnostic.Code = No_Error then
            Self.Last_Diagnostic := Item;
         end if;
         Abort_Owned_Transaction (Self, Failed);
         Diagnostic := Self.Last_Diagnostic;
      end Fail;

      procedure Run_Abort_Deferred
        (Self : in out Writer; Action : not null access procedure)
      is
         Completed_Normally : Boolean := False with Volatile;

         type Cleanup_Guard is new Ada.Finalization.Limited_Controlled with null record;

         overriding procedure Finalize (Guard : in out Cleanup_Guard) is
            pragma Unreferenced (Guard);
         begin
            if not Completed_Normally
              and then Self.Current_State not in Completed | Aborted
            then
               --  Finalize is abort-deferred by Ada RM 9.8. Preserve any
               --  established primary diagnostic while making continuation
               --  and later commit impossible.
               Abort_Owned_Transaction (Self, Aborted);
            end if;
         end Finalize;

         Cleanup : Cleanup_Guard;
         pragma Unreferenced (Cleanup);

         type Call_Transfer is new Ada.Finalization.Limited_Controlled with null record;

         overriding procedure Initialize (Transfer : in out Call_Transfer) is
            pragma Unreferenced (Transfer);
         begin
            --  This is the complete admitted operation. Abort deferral adds no
            --  check or dispatch inside its scanner or destination-write loop.
            Action.all;
         end Initialize;

         Transfer : Call_Transfer;
         pragma Unreferenced (Transfer);
      begin
         --  A task abort requested during Action is delivered when its
         --  abort-deferred Initialize ends, before this marker can execute.
         Completed_Normally := True;
      end Run_Abort_Deferred;

      procedure Reject_State (Self : Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         if Self.Current_State in Failed | Aborted and then Self.Last_Diagnostic.Code /= No_Error then
            Diagnostic := Self.Last_Diagnostic;
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
            Data (Data'First .. Data'First + Offset (Offered) - 1),
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

      procedure Emit_Escape
        (Self       : in out Writer;
         Value      : Element;
         Succeeded  : out Boolean;
         Diagnostic : out Writer_Core.Diagnostic)
      is
         Buffer : Ada.Streams.Stream_Element_Array (1 .. 6);
         Length : Offset;

         function Hex_Digit (Nibble : Element) return Element is
           (if Nibble < 10
            then Character'Pos ('0') + Nibble
            else Character'Pos ('A') + Nibble - 10);
      begin
         Buffer (1) := Reverse_Solidus;
         Length := 2;

         case Value is
            when 16#08# => Buffer (2) := Character'Pos ('b');
            when 16#09# => Buffer (2) := Character'Pos ('t');
            when 16#0A# => Buffer (2) := Character'Pos ('n');
            when 16#0C# => Buffer (2) := Character'Pos ('f');
            when 16#0D# => Buffer (2) := Character'Pos ('r');
            when Quote  => Buffer (2) := Quote;
            when Reverse_Solidus => Buffer (2) := Reverse_Solidus;
            when others =>
               Length := 6;
               Buffer (2) := Character'Pos ('u');
               Buffer (3) := Character'Pos ('0');
               Buffer (4) := Character'Pos ('0');
               Buffer (5) := Hex_Digit (Value / 16);
               Buffer (6) := Hex_Digit (Value mod 16);
         end case;

         Emit (Self, Buffer (1 .. Length), Succeeded, Diagnostic);
      end Emit_Escape;

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
         Result          : Parser_UTF8.Feed_Result;

         procedure Flush_Run (Exclusive_Last : Count) is
         begin
            if Exclusive_Last > Run_First_Count then
               Emit
                 (Self,
                  Value
                    (Value'First + Offset (Run_First_Count)
                     .. Value'First + Offset (Exclusive_Last) - 1),
                  Succeeded,
                  Diagnostic);
            else
               Succeeded := True;
               Diagnostic := Clear_Diagnostic;
            end if;
         end Flush_Run;
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
            if not Parser_UTF8.Has_Pending_Octets (Probe) then
               Probe_Lead := Base_Token + Byte_Offset (Position);
            end if;

            Parser_UTF8.Feed
              (Probe, Value (Value'First + Offset (Position)), Result);
            if Result.Status = Parser_UTF8.Invalid then
               Flush_Run (Position);
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
            elsif Needs_Escape (Value (Value'First + Offset (Position))) then
               Flush_Run (Position);
               if not Succeeded then
                  return;
               end if;

               Emit_Escape
                 (Self,
                  Value (Value'First + Offset (Position)),
                  Succeeded,
                  Diagnostic);
               if not Succeeded then
                  return;
               end if;
               Run_First_Count := Position + 1;
            end if;
            Position := Position + 1;
         end loop;

         Flush_Run (Position);
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

      procedure Begin_Document_Impl (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
         Ordinal  : Byte_Offset;
         Reserved : Boolean;
      begin
         if Self.Current_State /= Ready then
            Reject_State (Self, Diagnostic);
            return;
         end if;

         Reserve_Call (Self, Ordinal, Reserved, Diagnostic);
         if not Reserved then
            return;
         end if;
         pragma Unreferenced (Ordinal);

         declare
            --  Initialize is abort-deferred by Ada RM 9.8, so no task abort
            --  can land between destination ownership and the writer record.
            type Begin_Transfer is new Ada.Finalization.Limited_Controlled with null record;

            overriding procedure Initialize (Guard : in out Begin_Transfer) is
               pragma Unreferenced (Guard);
               Status : Begin_Status;
            begin
               Destination_Begin (Self.Target.all, Status);
               if Status = Begin_Succeeded then
                  Self.Current_State := Active;
                  Self.Owns_Transaction := True;
                  Self.Abort_Attempted := False;
                  Diagnostic := Clear_Diagnostic;
               else
                  Self.Last_Diagnostic :=
                    Make_Diagnostic (Destination_Failed, Staged_Output_Byte, 0);
                  Self.Current_State := Failed;
                  Diagnostic := Self.Last_Diagnostic;
               end if;
            end Initialize;

            Transfer : Begin_Transfer;
            pragma Unreferenced (Transfer);
         begin
            null;
         end;
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
                  Value (Value'First .. Value'First + Offset (Position) - 1),
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
      begin
         if Self.Current_State /= Active then
            Reject_State (Self, Diagnostic);
            return;
         end if;
         Reserve_Call (Self, Ordinal, Reserved, Diagnostic);
         if not Reserved then
            return;
         elsif Self.Token /= No_Token
           or else Self.Depth /= 0
           or else not Self.Root_Complete
         then
            Grammar_Failure (Self, Ordinal, Diagnostic);
            return;
         end if;

         declare
            --  Successful publication and the loss of transaction ownership,
            --  or failed publication and its cleanup, are one abort-deferred
            --  transfer under Ada RM 9.8.
            type Commit_Transfer is new Ada.Finalization.Limited_Controlled with null record;

            overriding procedure Initialize (Guard : in out Commit_Transfer) is
               pragma Unreferenced (Guard);
               Status : Commit_Status;
            begin
               Destination_Commit (Self.Target.all, Status);
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
            end Initialize;

            Transfer : Commit_Transfer;
            pragma Unreferenced (Transfer);
         begin
            null;
         end;
      end Finish_Document_Impl;

      procedure Abort_Document_Impl
        (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic)
      is
      begin
         case Self.Current_State is
            when Ready =>
               Self.Current_State := Aborted;
               Diagnostic := Clear_Diagnostic;

            when Active =>
               Abort_Owned_Transaction (Self, Aborted);
               Diagnostic := Self.Last_Diagnostic;

            when Failed | Aborted =>
               Diagnostic := Self.Last_Diagnostic;

            when Uninitialized | Completed =>
               Diagnostic := Clear_Diagnostic;
         end case;
      end Abort_Document_Impl;

      procedure Reset_Impl (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         if Self.Current_State not in Completed | Failed | Aborted then
            Reject_State (Self, Diagnostic);
            return;
         end if;

         Self.Current_State := Uninitialized;
         Initialize_Impl (Self, Diagnostic);
      end Reset_Impl;

      generic
         with procedure Implementation
           (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic);
      procedure Guarded_Simple_Call
        (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic);

      procedure Guarded_Simple_Call
        (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic)
      is
         procedure Perform is
         begin
            Implementation (Self, Diagnostic);
         end Perform;
      begin
         Run_Abort_Deferred (Self, Perform'Access);
      end Guarded_Simple_Call;

      generic
         with procedure Implementation
           (Self       : in out Writer;
            Value      : Ada.Streams.Stream_Element_Array;
            Diagnostic : out Writer_Core.Diagnostic);
      procedure Guarded_Fragment_Call
        (Self       : in out Writer;
         Value      : Ada.Streams.Stream_Element_Array;
         Diagnostic : out Writer_Core.Diagnostic);

      procedure Guarded_Fragment_Call
        (Self       : in out Writer;
         Value      : Ada.Streams.Stream_Element_Array;
         Diagnostic : out Writer_Core.Diagnostic)
      is
         procedure Perform is
         begin
            Implementation (Self, Value, Diagnostic);
         end Perform;
      begin
         Run_Abort_Deferred (Self, Perform'Access);
      end Guarded_Fragment_Call;

      generic
         with procedure Implementation
           (Self : in out Writer; Value : Boolean; Diagnostic : out Writer_Core.Diagnostic);
      procedure Guarded_Boolean_Call
        (Self : in out Writer; Value : Boolean; Diagnostic : out Writer_Core.Diagnostic);

      procedure Guarded_Boolean_Call
        (Self : in out Writer; Value : Boolean; Diagnostic : out Writer_Core.Diagnostic)
      is
         procedure Perform is
         begin
            Implementation (Self, Value, Diagnostic);
         end Perform;
      begin
         Run_Abort_Deferred (Self, Perform'Access);
      end Guarded_Boolean_Call;

      procedure Guarded_Initialize is new Guarded_Simple_Call (Initialize_Impl);
      procedure Guarded_Begin_Document is new Guarded_Simple_Call (Begin_Document_Impl);
      procedure Guarded_Begin_Object is new Guarded_Simple_Call (Begin_Object_Impl);
      procedure Guarded_End_Object is new Guarded_Simple_Call (End_Object_Impl);
      procedure Guarded_Begin_Array is new Guarded_Simple_Call (Begin_Array_Impl);
      procedure Guarded_End_Array is new Guarded_Simple_Call (End_Array_Impl);
      procedure Guarded_Begin_Name is new Guarded_Simple_Call (Begin_Name_Impl);
      procedure Guarded_Put_Name_Fragment is new Guarded_Fragment_Call (Put_Name_Fragment_Impl);
      procedure Guarded_End_Name is new Guarded_Simple_Call (End_Name_Impl);
      procedure Guarded_Begin_String is new Guarded_Simple_Call (Begin_String_Impl);
      procedure Guarded_Put_String_Fragment is new Guarded_Fragment_Call (Put_String_Fragment_Impl);
      procedure Guarded_End_String is new Guarded_Simple_Call (End_String_Impl);
      procedure Guarded_Begin_Number is new Guarded_Simple_Call (Begin_Number_Impl);
      procedure Guarded_Put_Number_Fragment is new Guarded_Fragment_Call (Put_Number_Fragment_Impl);
      procedure Guarded_End_Number is new Guarded_Simple_Call (End_Number_Impl);
      procedure Guarded_Put_Null is new Guarded_Simple_Call (Put_Null_Impl);
      procedure Guarded_Put_Boolean is new Guarded_Boolean_Call (Put_Boolean_Impl);
      procedure Guarded_Finish_Document is new Guarded_Simple_Call (Finish_Document_Impl);
      procedure Guarded_Abort_Document is new Guarded_Simple_Call (Abort_Document_Impl);
      procedure Guarded_Reset is new Guarded_Simple_Call (Reset_Impl);

      procedure Initialize (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Guarded_Initialize (Self, Diagnostic);
      end Initialize;

      procedure Begin_Document (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Guarded_Begin_Document (Self, Diagnostic);
      end Begin_Document;

      procedure Begin_Object (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Guarded_Begin_Object (Self, Diagnostic);
      end Begin_Object;

      procedure End_Object (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Guarded_End_Object (Self, Diagnostic);
      end End_Object;

      procedure Begin_Array (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Guarded_Begin_Array (Self, Diagnostic);
      end Begin_Array;

      procedure End_Array (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Guarded_End_Array (Self, Diagnostic);
      end End_Array;

      procedure Begin_Name (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Guarded_Begin_Name (Self, Diagnostic);
      end Begin_Name;

      procedure Put_Name_Fragment
        (Self       : in out Writer;
         Value      : Ada.Streams.Stream_Element_Array;
         Diagnostic : out Writer_Core.Diagnostic)
      is
      begin
         Guarded_Put_Name_Fragment (Self, Value, Diagnostic);
      end Put_Name_Fragment;

      procedure End_Name (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Guarded_End_Name (Self, Diagnostic);
      end End_Name;

      procedure Begin_String (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Guarded_Begin_String (Self, Diagnostic);
      end Begin_String;

      procedure Put_String_Fragment
        (Self       : in out Writer;
         Value      : Ada.Streams.Stream_Element_Array;
         Diagnostic : out Writer_Core.Diagnostic)
      is
      begin
         Guarded_Put_String_Fragment (Self, Value, Diagnostic);
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
         Guarded_End_String (Self, Diagnostic);
      end End_String;

      procedure Begin_Number (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Guarded_Begin_Number (Self, Diagnostic);
      end Begin_Number;

      procedure Put_Number_Fragment
        (Self       : in out Writer;
         Value      : Ada.Streams.Stream_Element_Array;
         Diagnostic : out Writer_Core.Diagnostic)
      is
      begin
         Guarded_Put_Number_Fragment (Self, Value, Diagnostic);
      end Put_Number_Fragment;

      procedure End_Number (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Guarded_End_Number (Self, Diagnostic);
      end End_Number;

      procedure Put_Null (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Guarded_Put_Null (Self, Diagnostic);
      end Put_Null;

      procedure Put_Boolean
        (Self : in out Writer; Value : Boolean; Diagnostic : out Writer_Core.Diagnostic)
      is
      begin
         Guarded_Put_Boolean (Self, Value, Diagnostic);
      end Put_Boolean;

      procedure Finish_Document (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Guarded_Finish_Document (Self, Diagnostic);
      end Finish_Document;

      procedure Abort_Document (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Guarded_Abort_Document (Self, Diagnostic);
      end Abort_Document;

      procedure Reset (Self : in out Writer; Diagnostic : out Writer_Core.Diagnostic) is
      begin
         Guarded_Reset (Self, Diagnostic);
      end Reset;

      function State (Self : Writer) return Writer_State is (Self.Current_State);

      function Terminal_Diagnostic (Self : Writer) return Writer_Core.Diagnostic is
        (Self.Last_Diagnostic);

      procedure Set_Offsets_For_Test
        (Self        : in out Writer;
         Next_Staged : Byte_Offset;
         Next_Token  : Byte_Offset)
      is
      begin
         Self.Next_Staged_Offset := Next_Staged;
         Self.Next_Token_Offset := Next_Token;
      end Set_Offsets_For_Test;

      overriding procedure Finalize (Self : in out Writer) is
      begin
         Abort_Owned_Transaction (Self, Aborted);
      end Finalize;

   end Destination_Writers;

end Flyology_JSON.Writer_Core;
