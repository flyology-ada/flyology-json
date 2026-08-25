with Ada.Streams;
with Flyology_JSON.Errors;
with Flyology_JSON.Numbers.Unsigned_Integers;
with Flyology_JSON.Parsing;
with Flyology_JSON.Profiles;
with Flyology_JSON.Tokens;
with Interfaces;

procedure Flyology_JSON.Public_Parsing_Tests is

   package Strict_Parsing is new Flyology_JSON.Parsing (Profiles.Reject_Duplicates);
   package Preserve_Parsing is new Flyology_JSON.Parsing (Profiles.Preserve_Unchecked);
   package Unsigned_64_Numbers is new
     Flyology_JSON.Numbers.Unsigned_Integers (Interfaces.Unsigned_64);

   use type Ada.Streams.Stream_Element_Count;
   use type Ada.Streams.Stream_Element_Array;
   use type Errors.Byte_Offset;
   use type Errors.Coordinate_Kind;
   use type Errors.Error_Code;
   use type Preserve_Parsing.Drain_Stop;
   use type Preserve_Parsing.Event_Kind;
   use type Preserve_Parsing.Step_Outcome;
   use type Profiles.Duplicate_Policy;
   use type Strict_Parsing.Decoded_Fragment_Kind;
   use type Strict_Parsing.Drain_Stop;
   use type Strict_Parsing.Event_Kind;
   use type Strict_Parsing.Parser_State;
   use type Strict_Parsing.Slice_Status;
   use type Strict_Parsing.Step_Outcome;
   use type Tokens.Collector_Status;
   use type Unsigned_64_Numbers.Parse_Status;

   subtype Offset is Ada.Streams.Stream_Element_Offset;
   subtype Count is Ada.Streams.Stream_Element_Count;

   Quote           : constant Character := '"';
   Reverse_Solidus : constant Character := '\';
   Maximum_Steps   : constant Positive := 256;

   procedure Check (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Check;

   function To_Input (Text : String; First : Offset) return Ada.Streams.Stream_Element_Array is
      Result : Ada.Streams.Stream_Element_Array
        (First .. First + Offset (Text'Length) - 1);
   begin
      for Position in Text'Range loop
         Result (First + Offset (Position - Text'First)) := Character'Pos (Text (Position));
      end loop;
      return Result;
   end To_Input;

   function Profile
     (Duplicates : Profiles.Duplicate_Policy;
      Top_Level  : Profiles.Top_Level_Policy := Profiles.Accept_Any_Value)
      return Profiles.Parser_Profile
   is
     (Syntax        => (Family => Profiles.RFC_8259, Version => 1),
      Unicode       => (Family => Profiles.Unicode_Scalars, Version => 1),
      Compatibility => (Family => Profiles.No_Extensions, Version => 1),
      BOM           => Profiles.Reject_BOM,
      Duplicates    => Duplicates,
      Top_Level     => Top_Level);

   procedure Check_Profile_And_Lifecycle is
      Subject    : Strict_Parsing.Parser (2, 16, 4);
      Unsupported : Strict_Parsing.Parser (2, 16, 4);
      Diagnostic : Errors.Diagnostic;
      Result     : Strict_Parsing.Step_Result;
      Events     : Strict_Parsing.Event_Array (3 .. 3);
      Drain_Info : Strict_Parsing.Drain_Result;
      Empty      : constant Ada.Streams.Stream_Element_Array (19 .. 18) := [others => 0];
   begin
      Strict_Parsing.Initialize
        (Unsupported,
         (Profile (Profiles.Reject_Duplicates) with delta
            Syntax => (Family => Profiles.RFC_8259, Version => 2)),
         Diagnostic);
      Check (Diagnostic.Code = Errors.Unsupported_Profile, "unknown syntax version was accepted");
      Check
        (Strict_Parsing.State (Unsupported) = Strict_Parsing.Failed,
         "unsupported profile did not fail parser");
      Check
        (not Strict_Parsing.Has_Applied_Profile (Unsupported),
         "unsupported profile became queryable");

      Strict_Parsing.Step (Subject, Empty, False, Result);
      Check (Result.Outcome = Strict_Parsing.Call_Rejected, "uninitialized Step was admitted");
      Check (Result.Diagnostic.Code = Errors.Invalid_State, "wrong uninitialized Step diagnostic");
      Strict_Parsing.Drain (Subject, Empty, False, Events, Drain_Info);
      Check (Drain_Info.Stop = Strict_Parsing.Drain_Rejected, "uninitialized Drain was admitted");
      Strict_Parsing.Reset (Subject, Profile (Profiles.Reject_Duplicates), Diagnostic);
      Check (Diagnostic.Code = Errors.Invalid_State, "uninitialized Reset was admitted");
      Strict_Parsing.Abort_Document (Subject);
      Check
        (Strict_Parsing.State (Subject) = Strict_Parsing.Uninitialized,
         "uninitialized Abort changed state");

      Strict_Parsing.Initialize
        (Subject, Profile (Profiles.Preserve_Unchecked), Diagnostic);
      Check (Diagnostic.Code = Errors.Incompatible_Profile, "static duplicate mismatch accepted");
      Check (Strict_Parsing.State (Subject) = Strict_Parsing.Failed, "mismatch did not fail parser");
      Check (not Strict_Parsing.Has_Applied_Profile (Subject), "mismatch published a profile");

      Strict_Parsing.Step (Subject, Empty, False, Result);
      Check (Result.Outcome = Strict_Parsing.Call_Rejected, "failed parser admitted Step");
      Check (Result.Consumed = 0, "rejected Step consumed input");
      Check (Result.Diagnostic.Code = Errors.Incompatible_Profile, "rejection lost profile failure");
      Strict_Parsing.Drain (Subject, Empty, False, Events, Drain_Info);
      Check (Drain_Info.Stop = Strict_Parsing.Drain_Rejected, "failed Drain was admitted");
      Check
        (Drain_Info.Diagnostic.Code = Errors.Incompatible_Profile,
         "failed Drain lost profile failure");
      Strict_Parsing.Initialize (Subject, Profile (Profiles.Reject_Duplicates), Diagnostic);
      Check
        (Diagnostic.Code = Errors.Incompatible_Profile,
         "illegal Initialize replaced retained profile failure");
      Strict_Parsing.Abort_Document (Subject);
      Check (Strict_Parsing.State (Subject) = Strict_Parsing.Failed, "failed Abort changed state");

      Strict_Parsing.Reset (Subject, Profile (Profiles.Reject_Duplicates), Diagnostic);
      Check (Diagnostic.Code = Errors.No_Error, "valid reset from profile failure failed");
      Check (Strict_Parsing.State (Subject) = Strict_Parsing.Ready, "reset did not enter Ready");
      Check (Strict_Parsing.Has_Applied_Profile (Subject), "reset did not publish profile");
      Check
        (Strict_Parsing.Applied_Profile (Subject).Duplicates = Profiles.Reject_Duplicates,
         "applied profile changed");

      Strict_Parsing.Reset (Subject, Profile (Profiles.Reject_Duplicates), Diagnostic);
      Check (Diagnostic.Code = Errors.Invalid_State, "ready Reset was admitted");

      Strict_Parsing.Initialize (Subject, Profile (Profiles.Reject_Duplicates), Diagnostic);
      Check (Diagnostic.Code = Errors.Invalid_State, "second Initialize was admitted");
      Check (Strict_Parsing.State (Subject) = Strict_Parsing.Ready, "illegal Initialize changed state");

      Strict_Parsing.Step (Subject, Empty, True, Result);
      Check (Result.Outcome = Strict_Parsing.Event_Ready, "ready Step did not publish document begin");
      Check (Strict_Parsing.Kind (Result.Item) = Strict_Parsing.Document_Begin, "wrong first event");
      Check (Result.Input_Origin = 0 and then Result.Consumed = 0, "synthetic event moved input");

      Strict_Parsing.Initialize (Subject, Profile (Profiles.Reject_Duplicates), Diagnostic);
      Check (Diagnostic.Code = Errors.Invalid_State, "active Initialize was admitted");
      Strict_Parsing.Reset (Subject, Profile (Profiles.Reject_Duplicates), Diagnostic);
      Check (Diagnostic.Code = Errors.Invalid_State, "active Reset was admitted");

      Strict_Parsing.Step (Subject, Empty, False, Result);
      Check (Result.Outcome = Strict_Parsing.Call_Rejected, "final-input retraction was admitted");
      Check (Result.Diagnostic.Code = Errors.Final_Input_Retracted, "wrong finality diagnostic");
      Check (Result.Diagnostic.Coordinate = Errors.Source_Byte, "finality coordinate changed");
      Check (Result.Consumed = 0, "finality rejection consumed input");

      Strict_Parsing.Abort_Document (Subject);
      Check (Strict_Parsing.State (Subject) = Strict_Parsing.Aborted, "abort did not seal parser");
      Check
        (Strict_Parsing.Terminal_Diagnostic (Subject).Code = Errors.No_Error,
         "clean abort retained an error");
      Strict_Parsing.Abort_Document (Subject);
      Check (Strict_Parsing.State (Subject) = Strict_Parsing.Aborted, "abort was not idempotent");
      Strict_Parsing.Step (Subject, Empty, True, Result);
      Check (Result.Outcome = Strict_Parsing.Call_Rejected, "aborted Step was admitted");
      Strict_Parsing.Drain (Subject, Empty, True, Events, Drain_Info);
      Check (Drain_Info.Stop = Strict_Parsing.Drain_Rejected, "aborted Drain was admitted");
      Strict_Parsing.Initialize (Subject, Profile (Profiles.Reject_Duplicates), Diagnostic);
      Check (Diagnostic.Code = Errors.Invalid_State, "aborted Initialize was admitted");
      Strict_Parsing.Reset (Subject, Profile (Profiles.Reject_Duplicates), Diagnostic);
      Check (Diagnostic.Code = Errors.No_Error, "aborted Reset failed");
      Check (Strict_Parsing.State (Subject) = Strict_Parsing.Ready, "aborted Reset did not enter Ready");
   end Check_Profile_And_Lifecycle;

   procedure Check_Drain is
      Subject     : Strict_Parsing.Parser (4, 32, 8);
      Input       : constant Ada.Streams.Stream_Element_Array := To_Input ("[null,true,false]", -31);
      Events      : Strict_Parsing.Event_Array (-7 .. -4);
      Null_Events : Strict_Parsing.Event_Array (17 .. 16);
      Result      : Strict_Parsing.Drain_Result;
      Diagnostic  : Errors.Diagnostic;
      Used        : Count := 0;
      Seen        : Natural := 0;
   begin
      Strict_Parsing.Drain (Subject, Input, True, Null_Events, Result);
      Check (Result.Stop = Strict_Parsing.Output_Full, "null Drain did not report capacity stop");
      Check (Result.Consumed = 0 and then Result.Produced = 0, "null Drain had effects");
      Check (Strict_Parsing.State (Subject) = Strict_Parsing.Uninitialized, "null Drain changed state");

      Strict_Parsing.Initialize (Subject, Profile (Profiles.Reject_Duplicates), Diagnostic);
      Check (Diagnostic.Code = Errors.No_Error, "Drain parser initialization failed");

      for Attempt in 1 .. Maximum_Steps loop
         declare
            First : constant Offset := Input'First + Offset (Used);
         begin
            if Used < Input'Length then
               Strict_Parsing.Drain (Subject, Input (First .. Input'Last), True, Events, Result);
            else
               declare
                  Empty : constant Ada.Streams.Stream_Element_Array (First .. First - 1) :=
                    [others => 0];
               begin
                  Strict_Parsing.Drain (Subject, Empty, True, Events, Result);
               end;
            end if;
         end;

         Check (Result.Input_Origin = Errors.Byte_Offset (Used), "Drain input origin changed");
         Check (Result.Produced <= Events'Length, "Drain overfilled caller storage");
         if Result.Produced > 0 then
            for Published in Count range 0 .. Result.Produced - 1 loop
               declare
                  Item : Strict_Parsing.Event renames
                    Events (Events'First + Offset (Published));
                  Expected : constant Strict_Parsing.Event_Kind :=
                    (case Seen + 1 is
                       when 1      => Strict_Parsing.Document_Begin,
                       when 2      => Strict_Parsing.Array_Begin,
                       when 3      => Strict_Parsing.Null_Value,
                       when 4 | 5  => Strict_Parsing.Boolean_Value,
                       when 6      => Strict_Parsing.Array_End,
                       when others => Strict_Parsing.Document_End);
               begin
                  Seen := Seen + 1;
                  Check (Strict_Parsing.Kind (Item) = Expected, "Drain event transcript changed");

                  if Strict_Parsing.Kind (Item)
                    in Strict_Parsing.Null_Value | Strict_Parsing.Boolean_Value
                  then
                     declare
                        Slice  : Strict_Parsing.Chunk_Range;
                        Status : Strict_Parsing.Slice_Status;
                     begin
                        Strict_Parsing.Resolve_Raw_Range
                          (Item,
                           Result.Input_Origin,
                           Input'Length - Used,
                           Slice,
                           Status);
                        Check
                          (Status = Strict_Parsing.Slice_Resolved,
                           "Drain scalar raw range failed");
                        Check
                          (Slice.Octet_Length
                           = (if Strict_Parsing.Kind (Item) = Strict_Parsing.Null_Value
                              then 4
                              elsif Strict_Parsing.Boolean_Data (Item)
                              then 4
                              else 5),
                           "Drain scalar raw length changed");
                     end;
                  end if;
               end;
            end loop;
         end if;
         Used := Used + Result.Consumed;

         exit when Result.Stop = Strict_Parsing.Drain_Document_Complete;
         Check
           (Result.Stop in Strict_Parsing.Output_Full | Strict_Parsing.Drain_Need_Input,
            "valid Drain stopped unexpectedly");
         pragma Assert (Attempt < Maximum_Steps);
      end loop;

      Check (Result.Stop = Strict_Parsing.Drain_Document_Complete, "Drain did not complete document");
      Check (Used = Input'Length, "Drain did not consume complete input");
      Check (Seen = 7, "Drain event transcript length changed");
      Check (Strict_Parsing.State (Subject) = Strict_Parsing.Completed, "Drain did not enter Completed");

      declare
         Empty     : constant Ada.Streams.Stream_Element_Array (Input'Last + 1 .. Input'Last) :=
           [others => 0];
         Step_Info : Strict_Parsing.Step_Result;
      begin
         Strict_Parsing.Step (Subject, Empty, True, Step_Info);
         Check (Step_Info.Outcome = Strict_Parsing.Call_Rejected, "completed Step was admitted");
         Strict_Parsing.Drain (Subject, Empty, True, Events, Result);
         Check (Result.Stop = Strict_Parsing.Drain_Rejected, "completed Drain was admitted");
         Strict_Parsing.Initialize (Subject, Profile (Profiles.Reject_Duplicates), Diagnostic);
         Check (Diagnostic.Code = Errors.Invalid_State, "completed Initialize was admitted");
         Strict_Parsing.Abort_Document (Subject);
         Check
           (Strict_Parsing.State (Subject) = Strict_Parsing.Completed,
            "completed Abort changed state");

         Strict_Parsing.Reset (Subject, Profile (Profiles.Preserve_Unchecked), Diagnostic);
         Check
           (Diagnostic.Code = Errors.Incompatible_Profile,
            "mismatched completed Reset was accepted");
         Strict_Parsing.Step (Subject, Empty, True, Step_Info);
         Check
           (Step_Info.Outcome = Strict_Parsing.Call_Rejected
            and then Step_Info.Input_Origin = 0,
            "invalid completed Reset retained the prior input origin");
         Strict_Parsing.Drain (Subject, Empty, True, Events, Result);
         Check
           (Result.Stop = Strict_Parsing.Drain_Rejected
            and then Result.Input_Origin = 0,
            "invalid completed Reset retained the prior Drain origin");
         Strict_Parsing.Reset (Subject, Profile (Profiles.Reject_Duplicates), Diagnostic);
         Check (Diagnostic.Code = Errors.No_Error, "completed Reset failed");
         Check (Strict_Parsing.State (Subject) = Strict_Parsing.Ready, "completed Reset did not enter Ready");
      end;
   end Check_Drain;

   procedure Check_Drain_Finality_And_Null_Precedence is
      Subject     : Strict_Parsing.Parser (1, 0, 0);
      Input       : constant Ada.Streams.Stream_Element_Array := To_Input ("[]", -17);
      Events      : Strict_Parsing.Event_Array (9 .. 9);
      Null_Events : Strict_Parsing.Event_Array (4 .. 3);
      Result      : Strict_Parsing.Drain_Result;
      Diagnostic  : Errors.Diagnostic;
   begin
      Strict_Parsing.Initialize (Subject, Profile (Profiles.Reject_Duplicates), Diagnostic);
      Strict_Parsing.Drain (Subject, Input, True, Events, Result);
      Check
        (Result.Stop = Strict_Parsing.Output_Full
         and then Result.Produced = 1
         and then Strict_Parsing.Kind (Events (Events'First)) = Strict_Parsing.Document_Begin,
         "nonnull Drain did not latch finality at an output stop");

      Strict_Parsing.Drain (Subject, Input, False, Null_Events, Result);
      Check
        (Result.Stop = Strict_Parsing.Output_Full
         and then Result.Consumed = 0
         and then Result.Produced = 0,
         "null Drain did not take precedence after finality latch");
      Check (Strict_Parsing.State (Subject) = Strict_Parsing.Active, "null Drain changed active state");

      Strict_Parsing.Drain (Subject, Input, False, Events, Result);
      Check
        (Result.Stop = Strict_Parsing.Drain_Rejected
         and then Result.Diagnostic.Code = Errors.Final_Input_Retracted,
         "nonnull Drain accepted final-input retraction");
      Check
        (Result.Input_Origin = 0 and then Result.Consumed = 0 and then Result.Produced = 0,
         "Drain final-input rejection had effects");

      Strict_Parsing.Abort_Document (Subject);
      Strict_Parsing.Drain (Subject, Input, False, Null_Events, Result);
      Check (Result.Stop = Strict_Parsing.Output_Full, "terminal null Drain lost precedence");
      Check (Strict_Parsing.State (Subject) = Strict_Parsing.Aborted, "terminal null Drain changed state");
   end Check_Drain_Finality_And_Null_Precedence;

   procedure Check_No_Copy_Pipeline is
      Text : constant String :=
        "{" & Quote & "id" & Quote & ":18446744073709551615," & Quote & "label" & Quote
        & ":" & Quote & "A" & Reverse_Solidus & "u20AC" & Quote & "}";
      Input          : constant Ada.Streams.Stream_Element_Array := To_Input (Text, -101);
      Subject        : Strict_Parsing.Parser (2, 32, 8);
      Result         : Strict_Parsing.Step_Result;
      Diagnostic     : Errors.Diagnostic;
      Used           : Count := 0;
      Number_Storage : aliased Tokens.Token_Storage := [41 .. 60 => 0];
      String_Storage : aliased Tokens.Token_Storage := [-9 .. -6 => 0];
      Number_Token   : Tokens.Collector (Number_Storage'Access);
      String_Token   : Tokens.Collector (String_Storage'Access);
      Token_Status   : Tokens.Collector_Status;
      Number_Result  : Unsigned_64_Numbers.Parse_Result;
      Number_Done    : Boolean := False;
      String_Done    : Boolean := False;

      procedure Append_Raw
        (Collector : in out Tokens.Collector;
         Item      : Strict_Parsing.Event;
         Window    : Ada.Streams.Stream_Element_Array;
         Origin    : Errors.Byte_Offset)
      is
         Slice  : Strict_Parsing.Chunk_Range;
         Status : Strict_Parsing.Slice_Status;
         First  : Offset;
      begin
         Strict_Parsing.Resolve_Raw_Range (Item, Origin, Window'Length, Slice, Status);
         Check (Status = Strict_Parsing.Slice_Resolved, "raw event did not resolve in producing window");
         Check (Slice.Octet_Length > 0, "raw token fragment was empty");
         First := Window'First + Offset (Slice.First_Count);
         Tokens.Append
           (Collector,
            Window (First .. First + Offset (Slice.Octet_Length) - 1),
            Token_Status);
         Check (Token_Status = Tokens.Operation_Accepted, "raw token append failed");
      end Append_Raw;

      procedure Observe
        (Item   : Strict_Parsing.Event;
         Window : Ada.Streams.Stream_Element_Array;
         Origin : Errors.Byte_Offset)
      is
      begin
         case Strict_Parsing.Kind (Item) is
            when Strict_Parsing.Number_Begin    =>
               Tokens.Begin_Token (Number_Token, Tokens.Exact_Number, Token_Status);
               Check (Token_Status = Tokens.Operation_Accepted, "number collection did not begin");

            when Strict_Parsing.Number_Fragment =>
               Append_Raw (Number_Token, Item, Window, Origin);

            when Strict_Parsing.Number_End       =>
               Tokens.Complete_Token (Number_Token, Token_Status);
               Check (Token_Status = Tokens.Token_Completed, "number collection did not complete");
               Unsigned_64_Numbers.Parse
                 (Number_Storage
                    (Number_Storage'First
                     .. Number_Storage'First + Offset (Tokens.Collected_Length (Number_Token)) - 1),
                  Number_Result);
               Check (Number_Result.Status = Unsigned_64_Numbers.Converted, "uint64 conversion failed");
               Check (Number_Result.Value = Interfaces.Unsigned_64'Last, "uint64 endpoint changed");
               Number_Done := True;

            when Strict_Parsing.String_Begin     =>
               Tokens.Begin_Token (String_Token, Tokens.Decoded_String, Token_Status);
               Check (Token_Status = Tokens.Operation_Accepted, "string collection did not begin");

            when Strict_Parsing.String_Fragment  =>
               case Strict_Parsing.Decoded_Kind (Item) is
                  when Strict_Parsing.No_Decoded_Fragment  =>
                     null;

                  when Strict_Parsing.Decoded_Is_Raw_Range =>
                     Append_Raw (String_Token, Item, Window, Origin);

                  when Strict_Parsing.Decoded_Inline_Scalar =>
                     declare
                        Scalar : constant Strict_Parsing.Inline_Scalar :=
                          Strict_Parsing.Decoded_Scalar (Item);
                     begin
                        Tokens.Append
                          (String_Token,
                           Scalar.Octets (1 .. Offset (Scalar.Length)),
                           Token_Status);
                        Check (Token_Status = Tokens.Operation_Accepted, "decoded scalar append failed");
                     end;
               end case;

            when Strict_Parsing.String_End        =>
               Tokens.Complete_Token (String_Token, Token_Status);
               Check (Token_Status = Tokens.Token_Completed, "string collection did not complete");
               Check (Tokens.Collected_Length (String_Token) = 4, "decoded string length changed");
               Check
                 (String_Storage = Tokens.Token_Storage'(-9 => 16#41#, -8 => 16#E2#, -7 => 16#82#,
                                                        -6 => 16#AC#),
                  "decoded string octets changed");
               String_Done := True;

            when others                            =>
               null;
         end case;
      end Observe;
   begin
      Strict_Parsing.Initialize (Subject, Profile (Profiles.Reject_Duplicates), Diagnostic);
      Check (Diagnostic.Code = Errors.No_Error, "pipeline parser initialization failed");

      for Attempt in 1 .. Maximum_Steps loop
         declare
            First : constant Offset := Input'First + Offset (Used);
         begin
            if Used < Input'Length then
               declare
                  Window : Ada.Streams.Stream_Element_Array renames Input (First .. Input'Last);
               begin
                  Strict_Parsing.Step (Subject, Window, True, Result);
                  if Result.Outcome = Strict_Parsing.Event_Ready then
                     Observe (Result.Item, Window, Result.Input_Origin);
                  end if;
               end;
            else
               declare
                  Empty : constant Ada.Streams.Stream_Element_Array (First .. First - 1) :=
                    [others => 0];
               begin
                  Strict_Parsing.Step (Subject, Empty, True, Result);
               end;
            end if;
         end;

         Check (Result.Input_Origin = Errors.Byte_Offset (Used), "Step input origin changed");
         Used := Used + Result.Consumed;
         exit when Result.Outcome = Strict_Parsing.Document_Complete;
         Check
           (Result.Outcome in Strict_Parsing.Event_Ready | Strict_Parsing.Need_Input,
            "valid pipeline stopped unexpectedly");
         pragma Assert (Attempt < Maximum_Steps);
      end loop;

      Check (Result.Outcome = Strict_Parsing.Document_Complete, "pipeline document did not complete");
      Check (Used = Input'Length, "pipeline did not consume input");
      Check (Number_Done, "pipeline did not publish number token");
      Check (String_Done, "pipeline did not publish decoded string token");
   end Check_No_Copy_Pipeline;

   procedure Check_One_Byte_Transport is

      procedure Check_Text
        (Text             : String;
         Expect_Boolean   : Boolean;
         Expect_Inline    : Boolean)
      is
         Input       : constant Ada.Streams.Stream_Element_Array := To_Input (Text, -73);
         Subject     : Strict_Parsing.Parser (2, 16, 4);
         Result      : Strict_Parsing.Step_Result;
         Diagnostic  : Errors.Diagnostic;
         Used        : Count := 0;
         Saw_Boolean : Boolean := False;
         Saw_Inline  : Boolean := False;
         Checked_Bad_Window : Boolean := False;
      begin
         Strict_Parsing.Initialize (Subject, Profile (Profiles.Reject_Duplicates), Diagnostic);
         Check (Diagnostic.Code = Errors.No_Error, "one-byte parser initialization failed");

         for Attempt in 1 .. Maximum_Steps loop
            declare
               First : constant Offset := Input'First + Offset (Used);
            begin
               if Used < Input'Length then
                  declare
                     Window : Ada.Streams.Stream_Element_Array renames Input (First .. First);
                     Final  : constant Boolean := Used + 1 = Input'Length;
                  begin
                     Strict_Parsing.Step (Subject, Window, Final, Result);
                     if Result.Outcome = Strict_Parsing.Event_Ready then
                        if Strict_Parsing.Has_Raw_Slice (Result.Item) then
                           declare
                              Slice  : Strict_Parsing.Chunk_Range;
                              Status : Strict_Parsing.Slice_Status;
                           begin
                              Strict_Parsing.Resolve_Raw_Range
                                (Result.Item, Result.Input_Origin, Window'Length, Slice, Status);
                              Check (Status = Strict_Parsing.Slice_Resolved, "one-byte raw range failed");
                              Check (Slice.Octet_Length = 1, "one-byte raw range changed length");

                              if not Checked_Bad_Window then
                                 Strict_Parsing.Resolve_Raw_Range
                                   (Result.Item, Result.Input_Origin + 1, 0, Slice, Status);
                                 Check
                                   (Status = Strict_Parsing.Range_Outside_Window,
                                    "foreign coordinate window resolved");
                                 Check
                                   (Slice.First_Count = 0 and then Slice.Octet_Length = 0,
                                    "failed raw resolution published counts");
                                 Checked_Bad_Window := True;
                              end if;
                           end;
                        end if;

                        if Strict_Parsing.Kind (Result.Item) = Strict_Parsing.Boolean_Value then
                           Check
                             (not Strict_Parsing.Has_Raw_Slice (Result.Item),
                              "split Boolean claimed a complete raw slice");
                           Check (Strict_Parsing.Boolean_Data (Result.Item), "Boolean payload changed");
                           Saw_Boolean := True;
                        elsif Strict_Parsing.Decoded_Kind (Result.Item)
                          = Strict_Parsing.Decoded_Inline_Scalar
                        then
                           declare
                              Scalar : constant Strict_Parsing.Inline_Scalar :=
                                Strict_Parsing.Decoded_Scalar (Result.Item);
                              Decoded : constant Strict_Parsing.Source_Range :=
                                Strict_Parsing.Decoded_Source (Result.Item);
                           begin
                              Check (Scalar.Length = 3, "escaped scalar UTF-8 length changed");
                              Check
                                (Scalar.Octets (1 .. 3)
                                 = Ada.Streams.Stream_Element_Array'
                                     (1 => 16#E2#, 2 => 16#82#, 3 => 16#AC#),
                                 "escaped scalar UTF-8 bytes changed");
                              Check
                                (Decoded.First = 1 and then Decoded.Octet_Length = 6,
                                 "cross-call decoded provenance changed");
                              Saw_Inline := True;
                           end;
                        end if;
                     end if;
                  end;
               else
                  declare
                     Empty : constant Ada.Streams.Stream_Element_Array (First .. First - 1) :=
                       [others => 0];
                  begin
                     Strict_Parsing.Step (Subject, Empty, True, Result);
                  end;
               end if;
            end;

            Used := Used + Result.Consumed;
            exit when Result.Outcome = Strict_Parsing.Document_Complete;
            Check
              (Result.Outcome in Strict_Parsing.Event_Ready | Strict_Parsing.Need_Input,
               "one-byte transcript stopped unexpectedly");
            pragma Assert (Attempt < Maximum_Steps);
         end loop;

         Check (Result.Outcome = Strict_Parsing.Document_Complete, "one-byte document did not complete");
         Check (Saw_Boolean = Expect_Boolean, "one-byte Boolean observation changed");
         Check (Saw_Inline = Expect_Inline, "one-byte inline-scalar observation changed");
         Check
           (Checked_Bad_Window or else not Expect_Inline,
            "one-byte text transcript had no raw range to validate");
      end Check_Text;
   begin
      Check_Text ("true", Expect_Boolean => True, Expect_Inline => False);
      Check_Text
        (Quote & Reverse_Solidus & "u20AC" & Quote,
         Expect_Boolean => False,
         Expect_Inline  => True);
   end Check_One_Byte_Transport;

   procedure Check_Policies_And_Failures is
      Preserve         : Preserve_Parsing.Parser (2, 0, 0);
      Preserve_Drained : Preserve_Parsing.Parser (2, 0, 0);
      Strict           : Strict_Parsing.Parser (2, 16, 4);
      Narrow_Name      : Strict_Parsing.Parser (2, 2, 1);
      Pending_Abort    : Strict_Parsing.Parser (2, 2, 1);
      Pending_Reset    : Strict_Parsing.Parser (2, 2, 1);
      Pending_Invalid  : Strict_Parsing.Parser (2, 2, 1);
      Object_Only      : Strict_Parsing.Parser (2, 16, 4);
      Diagnostic       : Errors.Diagnostic;
      Preserve_Result  : Preserve_Parsing.Step_Result;
      Preserve_Events  : Preserve_Parsing.Event_Array (-7 .. -4);
      Preserve_Drain   : Preserve_Parsing.Drain_Result;
      Strict_Result    : Strict_Parsing.Step_Result;
      Strict_Events    : Strict_Parsing.Event_Array (2 .. 2);
      Null_Strict_Events : Strict_Parsing.Event_Array (2 .. 1);
      Strict_Drain     : Strict_Parsing.Drain_Result;
      Duplicate        : constant Ada.Streams.Stream_Element_Array :=
        To_Input ("{" & Quote & "a" & Quote & ":0," & Quote & Reverse_Solidus & "u0061" & Quote & ":1}", 7);
      Escaped_Name    : constant Ada.Streams.Stream_Element_Array :=
        To_Input ("{" & Quote & Reverse_Solidus & "u20AC" & Quote & ":0}", -50);
      Scalar           : constant Ada.Streams.Stream_Element_Array := To_Input ("  0", 91);

      procedure Run_Preserve is
         Used : Count := 0;
      begin
         for Attempt in 1 .. Maximum_Steps loop
            declare
               First : constant Offset := Duplicate'First + Offset (Used);
            begin
               if Used < Duplicate'Length then
                  Preserve_Parsing.Step
                    (Preserve, Duplicate (First .. Duplicate'Last), True, Preserve_Result);
               else
                  declare
                     Empty : constant Ada.Streams.Stream_Element_Array (First .. First - 1) :=
                       [others => 0];
                  begin
                     Preserve_Parsing.Step (Preserve, Empty, True, Preserve_Result);
                  end;
               end if;
            end;
            Used := Used + Preserve_Result.Consumed;
            exit when Preserve_Result.Outcome = Preserve_Parsing.Document_Complete;
            Check
              (Preserve_Result.Outcome in Preserve_Parsing.Event_Ready | Preserve_Parsing.Need_Input,
               "preserve mode rejected duplicate names");
            pragma Assert (Attempt < Maximum_Steps);
         end loop;
         Check
           (Preserve_Result.Outcome = Preserve_Parsing.Document_Complete,
            "preserve mode did not complete duplicate object");
      end Run_Preserve;

      procedure Run_Preserve_Drain is
         Used        : Count := 0;
         Name_Begins : Natural := 0;
         Name_Ends   : Natural := 0;
      begin
         for Attempt in 1 .. Maximum_Steps loop
            declare
               First : constant Offset := Duplicate'First + Offset (Used);
            begin
               if Used < Duplicate'Length then
                  Preserve_Parsing.Drain
                    (Preserve_Drained,
                     Duplicate (First .. Duplicate'Last),
                     True,
                     Preserve_Events,
                     Preserve_Drain);
               else
                  declare
                     Empty : constant Ada.Streams.Stream_Element_Array (First .. First - 1) :=
                       [others => 0];
                  begin
                     Preserve_Parsing.Drain
                       (Preserve_Drained, Empty, True, Preserve_Events, Preserve_Drain);
                  end;
               end if;
            end;

            if Preserve_Drain.Produced > 0 then
               for Published in Count range 0 .. Preserve_Drain.Produced - 1 loop
                  case Preserve_Parsing.Kind
                    (Preserve_Events (Preserve_Events'First + Offset (Published)))
                  is
                     when Preserve_Parsing.Name_Begin =>
                        Name_Begins := Name_Begins + 1;

                     when Preserve_Parsing.Name_End   =>
                        Name_Ends := Name_Ends + 1;

                     when others                     =>
                        null;
                  end case;
               end loop;
            end if;

            Used := Used + Preserve_Drain.Consumed;
            exit when Preserve_Drain.Stop = Preserve_Parsing.Drain_Document_Complete;
            Check
              (Preserve_Drain.Stop
               in Preserve_Parsing.Output_Full | Preserve_Parsing.Drain_Need_Input,
               "preserve Drain rejected duplicate names");
            pragma Assert (Attempt < Maximum_Steps);
         end loop;

         Check
           (Preserve_Drain.Stop = Preserve_Parsing.Drain_Document_Complete,
            "preserve Drain did not complete duplicate object");
         Check (Used = Duplicate'Length, "preserve Drain changed consumed count");
         Check (Name_Begins = 2 and then Name_Ends = 2, "preserve Drain hid duplicate names");
      end Run_Preserve_Drain;

      procedure Run_Until_Stop
        (Subject : in out Strict_Parsing.Parser;
         Input   : Ada.Streams.Stream_Element_Array;
         Result  : out Strict_Parsing.Step_Result)
      is
         Used : Count := 0;
      begin
         for Attempt in 1 .. Maximum_Steps loop
            declare
               First : constant Offset := Input'First + Offset (Used);
            begin
               if Used < Input'Length then
                  Strict_Parsing.Step (Subject, Input (First .. Input'Last), True, Result);
               else
                  declare
                     Empty : constant Ada.Streams.Stream_Element_Array (First .. First - 1) :=
                       [others => 0];
                  begin
                     Strict_Parsing.Step (Subject, Empty, True, Result);
                  end;
               end if;
            end;
            Used := Used + Result.Consumed;
            exit when Result.Outcome not in Strict_Parsing.Event_Ready | Strict_Parsing.Need_Input;
            pragma Assert (Attempt < Maximum_Steps);
         end loop;
      end Run_Until_Stop;

      procedure Run_To_Failure_Pending
        (Subject : in out Strict_Parsing.Parser;
         Result  : out Strict_Parsing.Step_Result)
      is
         Used : Count := 0;
      begin
         for Attempt in 1 .. Maximum_Steps loop
            declare
               First : constant Offset := Escaped_Name'First + Offset (Used);
            begin
               if Used < Escaped_Name'Length then
                  Strict_Parsing.Step
                    (Subject, Escaped_Name (First .. Escaped_Name'Last), True, Result);
               else
                  declare
                     Empty : constant Ada.Streams.Stream_Element_Array (First .. First - 1) :=
                       [others => 0];
                  begin
                     Strict_Parsing.Step (Subject, Empty, True, Result);
                  end;
               end if;
            end;
            Used := Used + Result.Consumed;
            exit when Strict_Parsing.State (Subject) = Strict_Parsing.Failure_Pending;
            Check
              (Result.Outcome in Strict_Parsing.Event_Ready | Strict_Parsing.Need_Input,
               "name storage denial skipped provisional event");
            pragma Assert (Attempt < Maximum_Steps);
         end loop;

         Check
           (Strict_Parsing.State (Subject) = Strict_Parsing.Failure_Pending,
            "name storage denial did not enter Failure_Pending");
         Check
           (Result.Outcome = Strict_Parsing.Event_Ready
            and then Strict_Parsing.Kind (Result.Item) = Strict_Parsing.Name_Fragment,
            "name storage denial did not return its raw-only fragment");
         Check
           (Strict_Parsing.Decoded_Kind (Result.Item) = Strict_Parsing.No_Decoded_Fragment,
            "denied name scalar published decoded output");
      end Run_To_Failure_Pending;
   begin
      Preserve_Parsing.Initialize (Preserve, Profile (Profiles.Preserve_Unchecked), Diagnostic);
      Check (Diagnostic.Code = Errors.No_Error, "preserve parser initialization failed");
      Run_Preserve;
      Preserve_Parsing.Initialize
        (Preserve_Drained, Profile (Profiles.Preserve_Unchecked), Diagnostic);
      Check (Diagnostic.Code = Errors.No_Error, "preserve Drain initialization failed");
      Run_Preserve_Drain;

      Strict_Parsing.Initialize (Strict, Profile (Profiles.Reject_Duplicates), Diagnostic);
      Run_Until_Stop (Strict, Duplicate, Strict_Result);
      Check (Strict_Result.Outcome = Strict_Parsing.Step_Failed, "strict duplicate was accepted");
      Check (Strict_Result.Diagnostic.Code = Errors.Duplicate_Name, "wrong duplicate diagnostic");
      Strict_Parsing.Step (Strict, Scalar, True, Strict_Result);
      Check (Strict_Result.Outcome = Strict_Parsing.Call_Rejected, "failed Step was admitted");
      Check (Strict_Result.Diagnostic.Code = Errors.Duplicate_Name, "failed Step lost primary");
      Strict_Parsing.Drain (Strict, Scalar, True, Strict_Events, Strict_Drain);
      Check (Strict_Drain.Stop = Strict_Parsing.Drain_Rejected, "failed Drain was admitted");
      Check (Strict_Drain.Diagnostic.Code = Errors.Duplicate_Name, "failed Drain lost primary");
      Strict_Parsing.Initialize (Strict, Profile (Profiles.Reject_Duplicates), Diagnostic);
      Check (Diagnostic.Code = Errors.Duplicate_Name, "failed Initialize replaced primary");
      Strict_Parsing.Abort_Document (Strict);
      Check (Strict_Parsing.State (Strict) = Strict_Parsing.Failed, "failed Abort changed state");
      Strict_Parsing.Reset (Strict, Profile (Profiles.Preserve_Unchecked), Diagnostic);
      Check (Diagnostic.Code = Errors.Incompatible_Profile, "mismatched failed Reset was accepted");
      Strict_Parsing.Step (Strict, Scalar, True, Strict_Result);
      Check
        (Strict_Result.Outcome = Strict_Parsing.Call_Rejected
         and then Strict_Result.Input_Origin = 0,
         "invalid failed Reset retained the prior input origin");

      Strict_Parsing.Initialize
        (Object_Only,
         Profile (Profiles.Reject_Duplicates, Profiles.Require_Object),
         Diagnostic);
      Run_Until_Stop (Object_Only, Scalar, Strict_Result);
      Check (Strict_Result.Outcome = Strict_Parsing.Step_Failed, "object policy accepted scalar root");
      Check
        (Strict_Result.Diagnostic.Code = Errors.Top_Level_Kind_Rejected,
         "wrong top-level diagnostic");
      Check (Strict_Result.Diagnostic.Offset = 2, "top-level rejection offset changed");
      Check (Strict_Result.Consumed = 2, "top-level rejection consumed the denied root octet");

      Strict_Parsing.Initialize (Narrow_Name, Profile (Profiles.Reject_Duplicates), Diagnostic);
      Run_To_Failure_Pending (Narrow_Name, Strict_Result);
      Strict_Parsing.Initialize (Narrow_Name, Profile (Profiles.Reject_Duplicates), Diagnostic);
      Check
        (Diagnostic.Code = Errors.Name_Storage_Exhausted,
         "failure-pending Initialize replaced primary");
      Strict_Parsing.Step (Narrow_Name, Scalar, True, Strict_Result);
      Check
        (Strict_Result.Outcome = Strict_Parsing.Step_Failed,
         "name storage denial did not reach terminal failure");
      Check
        (Strict_Result.Diagnostic.Code = Errors.Name_Storage_Exhausted,
         "wrong name storage diagnostic");
      Check (Strict_Result.Diagnostic.Offset = 1, "name storage blame offset changed");

      Strict_Parsing.Initialize (Pending_Abort, Profile (Profiles.Reject_Duplicates), Diagnostic);
      Run_To_Failure_Pending (Pending_Abort, Strict_Result);
      Strict_Parsing.Drain
        (Pending_Abort, Scalar, False, Null_Strict_Events, Strict_Drain);
      Check
        (Strict_Drain.Stop = Strict_Parsing.Output_Full
         and then Strict_Drain.Consumed = 0
         and then Strict_Drain.Produced = 0,
         "failure-pending null Drain lost capacity precedence");
      Check
        (Strict_Parsing.State (Pending_Abort) = Strict_Parsing.Failure_Pending,
         "failure-pending null Drain changed state");
      Strict_Parsing.Abort_Document (Pending_Abort);
      Check
        (Strict_Parsing.State (Pending_Abort) = Strict_Parsing.Failed,
         "failure-pending Abort did not enter Failed");
      Check
        (Strict_Parsing.Terminal_Diagnostic (Pending_Abort).Code = Errors.Name_Storage_Exhausted,
         "failure-pending Abort lost primary");

      Strict_Parsing.Initialize (Pending_Reset, Profile (Profiles.Reject_Duplicates), Diagnostic);
      Run_To_Failure_Pending (Pending_Reset, Strict_Result);
      Strict_Parsing.Reset (Pending_Reset, Profile (Profiles.Reject_Duplicates), Diagnostic);
      Check (Diagnostic.Code = Errors.No_Error, "valid failure-pending Reset failed");
      Check
        (Strict_Parsing.State (Pending_Reset) = Strict_Parsing.Ready,
         "failure-pending Reset did not enter Ready");
      Check
        (Strict_Parsing.Has_Applied_Profile (Pending_Reset),
         "valid failure-pending Reset lost applied profile");

      Strict_Parsing.Initialize (Pending_Invalid, Profile (Profiles.Reject_Duplicates), Diagnostic);
      Run_To_Failure_Pending (Pending_Invalid, Strict_Result);
      Strict_Parsing.Reset (Pending_Invalid, Profile (Profiles.Preserve_Unchecked), Diagnostic);
      Check
        (Diagnostic.Code = Errors.Incompatible_Profile,
         "mismatched failure-pending Reset was accepted");
      Check
        (Strict_Parsing.State (Pending_Invalid) = Strict_Parsing.Failed,
         "mismatched failure-pending Reset did not enter Failed");
      Check
        (not Strict_Parsing.Has_Applied_Profile (Pending_Invalid),
         "mismatched failure-pending Reset retained applied profile");
      Strict_Parsing.Step (Pending_Invalid, Scalar, True, Strict_Result);
      Check
        (Strict_Result.Outcome = Strict_Parsing.Call_Rejected
         and then Strict_Result.Input_Origin = 0,
         "invalid failure-pending Reset retained the prior input origin");
      Strict_Parsing.Drain (Pending_Invalid, Scalar, True, Strict_Events, Strict_Drain);
      Check
        (Strict_Drain.Stop = Strict_Parsing.Drain_Rejected
         and then Strict_Drain.Input_Origin = 0,
         "invalid failure-pending Reset retained the prior Drain origin");
   end Check_Policies_And_Failures;

begin
   Check_Profile_And_Lifecycle;
   Check_Drain;
   Check_Drain_Finality_And_Null_Precedence;
   Check_No_Copy_Pipeline;
   Check_One_Byte_Transport;
   Check_Policies_And_Failures;
end Flyology_JSON.Public_Parsing_Tests;
