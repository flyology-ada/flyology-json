package body Flyology_JSON.Parsing is

   use type Errors.Byte_Offset;
   use type Errors.Error_Code;
   use type Parser_Core.Drain_Stop;
   use type Profiles.Duplicate_Policy;
   use type Profiles.Profile_Status;
   use type Profiles.Top_Level_Policy;

   subtype Count is Ada.Streams.Stream_Element_Count;

   Empty_Event : constant Event := Event (Parser_Core.Empty_Buffered);

   function Empty_Diagnostic return Errors.Diagnostic
   is
     (Code                 => Errors.No_Error,
      Coordinate           => Errors.No_Coordinate,
      Offset               => 0,
      Secondary            => Errors.No_Error,
      Secondary_Coordinate => Errors.No_Coordinate,
      Secondary_Offset     => 0);

   function State_Of (Value : Parser_Core.Parser_State) return Parser_State
   is (Parser_State'Val (Parser_Core.Parser_State'Pos (Value)));

   function Event_Kind_Of (Value : Parser_Core.Event_Kind) return Event_Kind
   is (Event_Kind'Val (Parser_Core.Event_Kind'Pos (Value)));

   function Root_Policy_Of (Value : Profiles.Top_Level_Policy) return Parser_Core.Root_Policy
   is (if Value = Profiles.Accept_Any_Value then Parser_Core.Accept_Any else Parser_Core.Require_Object);

   function Map_Code (Value : Parser_Core.Error_Code) return Errors.Error_Code is
   begin
      return
        (case Value is
           when Parser_Core.No_Error                    => Errors.No_Error,
           when Parser_Core.Invalid_State               => Errors.Invalid_State,
           when Parser_Core.Final_Input_Retracted       => Errors.Final_Input_Retracted,
           when Parser_Core.Unexpected_Token            => Errors.Unexpected_Token,
           when Parser_Core.Trailing_Input              => Errors.Trailing_Input,
           when Parser_Core.Truncated_Input             => Errors.Truncated_Input,
           when Parser_Core.Invalid_Literal             => Errors.Invalid_Literal,
           when Parser_Core.Invalid_Number              => Errors.Invalid_Number,
           when Parser_Core.Invalid_UTF8                => Errors.Invalid_UTF8,
           when Parser_Core.Invalid_Escape              => Errors.Invalid_Escape,
           when Parser_Core.Invalid_Surrogate           => Errors.Invalid_Surrogate,
           when Parser_Core.Raw_Control_Character       => Errors.Raw_Control_Character,
           when Parser_Core.Duplicate_Name              => Errors.Duplicate_Name,
           when Parser_Core.Top_Level_Kind_Rejected     => Errors.Top_Level_Kind_Rejected,
           when Parser_Core.Depth_Exhausted             => Errors.Depth_Exhausted,
           when Parser_Core.Name_Storage_Exhausted      => Errors.Name_Storage_Exhausted,
           when Parser_Core.Duplicate_Index_Exhausted   => Errors.Duplicate_Index_Exhausted,
           when Parser_Core.Offset_Exhausted            => Errors.Offset_Exhausted);
   end Map_Code;

   function Map_Diagnostic (Value : Parser_Core.Diagnostic) return Errors.Diagnostic is
      Code : constant Errors.Error_Code := Map_Code (Value.Code);
   begin
      if Code = Errors.No_Error then
         return Empty_Diagnostic;
      end if;

      return
        (Code                 => Code,
         Coordinate           => Errors.Source_Byte,
         Offset               => Errors.Byte_Offset (Value.Offset),
         Secondary            => Errors.No_Error,
         Secondary_Coordinate => Errors.No_Coordinate,
         Secondary_Offset     => 0);
   end Map_Diagnostic;

   function Invalid_State_Diagnostic return Errors.Diagnostic
   is
     (Code                 => Errors.Invalid_State,
      Coordinate           => Errors.No_Coordinate,
      Offset               => 0,
      Secondary            => Errors.No_Error,
      Secondary_Coordinate => Errors.No_Coordinate,
      Secondary_Offset     => 0);

   function Profile_Diagnostic (Code : Errors.Error_Code) return Errors.Diagnostic
   is
     (Code                 => Code,
      Coordinate           => Errors.No_Coordinate,
      Offset               => 0,
      Secondary            => Errors.No_Error,
      Secondary_Coordinate => Errors.No_Coordinate,
      Secondary_Offset     => 0);

   function Validate_Profile (Profile : Profiles.Parser_Profile) return Errors.Diagnostic is
      Status : constant Profiles.Profile_Status := Profiles.Validate (Profile);
   begin
      if Status = Profiles.Profile_Unsupported then
         return Profile_Diagnostic (Errors.Unsupported_Profile);
      elsif Status = Profiles.Profile_Incompatible or else Profile.Duplicates /= Duplicate_Mode then
         return Profile_Diagnostic (Errors.Incompatible_Profile);
      end if;

      return Empty_Diagnostic;
   end Validate_Profile;

   function Convert_Event (Item : Parser_Core.Buffered_Event) return Event
   is (Event (Item));

   pragma Inline_Always (Convert_Event);

   procedure Core_Drain is new Parser_Core.Generic_Drain
     (Output_Event       => Event,
      Output_Event_Array => Event_Array,
      Convert            => Convert_Event);

   procedure Sync_State (Self : in out Parser) is
   begin
      Self.Current_State := State_Of (Parser_Core.State (Self.Core_Data));
      if Self.Current_State in Failure_Pending | Failed | Aborted then
         Self.Last_Diagnostic := Map_Diagnostic (Parser_Core.Terminal_Diagnostic (Self.Core_Data));
      end if;
   end Sync_State;

   function Rejection_Diagnostic (Self : Parser) return Errors.Diagnostic is
   begin
      if Self.Current_State in Failure_Pending | Failed then
         return Self.Last_Diagnostic;
      end if;

      return Invalid_State_Diagnostic;
   end Rejection_Diagnostic;

   function Kind (Item : Event) return Event_Kind
   is (Event_Kind_Of (Parser_Core.Buffered_Kind (Parser_Core.Buffered_Event (Item))));

   function Source (Item : Event) return Source_Range is
      Core_Source : constant Parser_Core.Source_Range :=
        Parser_Core.Buffered_Source (Parser_Core.Buffered_Event (Item));
   begin
      return
        (First        => Byte_Offset (Core_Source.First),
         Octet_Length => Byte_Offset (Core_Source.Octet_Length));
   end Source;

   function Has_Raw_Slice (Item : Event) return Boolean
   is (Parser_Core.Buffered_Has_Raw_Slice (Parser_Core.Buffered_Event (Item)));

   procedure Resolve_Raw_Range
     (Item          : Event;
      Window_Origin : Byte_Offset;
      Window_Length : Ada.Streams.Stream_Element_Count;
      Slice         : out Chunk_Range;
      Status        : out Slice_Status)
   is
      Length         : constant Byte_Offset := Byte_Offset (Window_Length);
      Relative_First : Byte_Offset;
   begin
      Slice := (First_Count => 0, Octet_Length => 0);

      if not Has_Raw_Slice (Item) then
         Status := No_Raw_Slice;
         return;
      end if;

      if Source (Item).First < Window_Origin then
         Status := Range_Outside_Window;
         return;
      end if;

      Relative_First := Source (Item).First - Window_Origin;
      if Relative_First > Length
        or else Source (Item).Octet_Length > Length - Relative_First
      then
         Status := Range_Outside_Window;
         return;
      end if;

      Slice :=
        (First_Count  => Count (Relative_First),
         Octet_Length => Count (Source (Item).Octet_Length));
      Status := Slice_Resolved;
   end Resolve_Raw_Range;

   function Decoded_Kind (Item : Event) return Decoded_Fragment_Kind is
      Core_Kind : constant Parser_Core.Decoded_Fragment_Kind :=
        Parser_Core.Buffered_Decoded_Kind (Parser_Core.Buffered_Event (Item));
   begin
      return Decoded_Fragment_Kind'Val (Parser_Core.Decoded_Fragment_Kind'Pos (Core_Kind));
   end Decoded_Kind;

   function Decoded_Source (Item : Event) return Source_Range is
      Fragment_Kind : constant Decoded_Fragment_Kind := Decoded_Kind (Item);
      Core_Source   : constant Parser_Core.Source_Range :=
        Parser_Core.Buffered_Decoded_Source (Parser_Core.Buffered_Event (Item));
   begin
      pragma Unreferenced (Fragment_Kind);
      return
        (First        => Byte_Offset (Core_Source.First),
         Octet_Length => Byte_Offset (Core_Source.Octet_Length));
   end Decoded_Source;

   function Decoded_Scalar (Item : Event) return Inline_Scalar is
      Scalar : constant Parser_Core.Inline_Scalar :=
        Parser_Core.Buffered_Decoded_Scalar (Parser_Core.Buffered_Event (Item));
   begin
      return
        (Length => Positive (Scalar.Length),
         Octets =>
           [1 => Scalar.Octets (1),
            2 => Scalar.Octets (2),
            3 => Scalar.Octets (3),
            4 => Scalar.Octets (4)]);
   end Decoded_Scalar;

   function Boolean_Data (Item : Event) return Boolean
   is (Parser_Core.Buffered_Boolean_Data (Parser_Core.Buffered_Event (Item)));

   procedure Initialize
     (Self : in out Parser; Profile : Profiles.Parser_Profile; Diagnostic : out Errors.Diagnostic)
   is
   begin
      if Self.Current_State /= Uninitialized then
         Diagnostic := Rejection_Diagnostic (Self);
         return;
      end if;

      Diagnostic := Validate_Profile (Profile);
      if Diagnostic.Code /= Errors.No_Error then
         Self.Current_State := Failed;
         Self.Has_Profile := False;
         Self.Last_Diagnostic := Diagnostic;
         return;
      end if;

      Parser_Core.Initialize (Self.Core_Data, Root_Policy_Of (Profile.Top_Level));
      Self.Current_State := Ready;
      Self.Has_Profile := True;
      Self.Applied_Profile_Data := Profile;
      Self.Last_Diagnostic := Empty_Diagnostic;
      Self.Next_Origin := 0;
      Self.Core_Initialized := True;
      Diagnostic := Empty_Diagnostic;
   end Initialize;

   procedure Step
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Result       : out Step_Result)
   is
      Events      : Event_Array (1 .. 1);
      Core_Result : Parser_Core.Buffered_Drain_Result;
   begin
      if Self.Current_State not in Ready | Active | Failure_Pending then
         Result :=
           (Outcome      => Call_Rejected,
            Input_Origin => Self.Next_Origin,
            Consumed     => 0,
            Item         => Empty_Event,
            Diagnostic   => Rejection_Diagnostic (Self));
         return;
      end if;

      Core_Drain (Self.Core_Data, Input, End_Of_Input, Events, Core_Result);
      Self.Next_Origin := Byte_Offset (Core_Result.Input_First) + Byte_Offset (Core_Result.Consumed);
      Sync_State (Self);
      Result :=
        (Outcome      =>
           (case Core_Result.Stop is
              when Parser_Core.Drain_Buffer_Full       => Event_Ready,
              when Parser_Core.Drain_Need_Input        => Need_Input,
              when Parser_Core.Drain_Document_Complete => Document_Complete,
              when Parser_Core.Drain_Parse_Failed      => Step_Failed,
              when Parser_Core.Drain_Call_Rejected     => Call_Rejected),
         Input_Origin => Byte_Offset (Core_Result.Input_First),
         Consumed     => Core_Result.Consumed,
         Item         =>
           (if Core_Result.Stop = Parser_Core.Drain_Buffer_Full
            then Events (Events'First)
            else Empty_Event),
         Diagnostic   =>
           (if Core_Result.Stop in Parser_Core.Drain_Parse_Failed | Parser_Core.Drain_Call_Rejected
            then Map_Diagnostic (Core_Result.Diagnostic)
            else Empty_Diagnostic));
   end Step;

   procedure Drain
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Events       : out Event_Array;
      Result       : out Drain_Result)
   is
      Core_Result : Parser_Core.Buffered_Drain_Result;
   begin
      if Events'Length = 0 then
         Result :=
           (Stop         => Output_Full,
            Input_Origin => Self.Next_Origin,
            Consumed     => 0,
            Produced     => 0,
            Diagnostic   => Empty_Diagnostic);
         return;
      end if;

      if Self.Current_State not in Ready | Active | Failure_Pending then
         Result :=
           (Stop         => Drain_Rejected,
            Input_Origin => Self.Next_Origin,
            Consumed     => 0,
            Produced     => 0,
            Diagnostic   => Rejection_Diagnostic (Self));
         return;
      end if;

      Core_Drain (Self.Core_Data, Input, End_Of_Input, Events, Core_Result);
      Self.Next_Origin := Byte_Offset (Core_Result.Input_First) + Byte_Offset (Core_Result.Consumed);
      Sync_State (Self);
      Result :=
        (Stop         =>
           (case Core_Result.Stop is
              when Parser_Core.Drain_Buffer_Full       => Output_Full,
              when Parser_Core.Drain_Need_Input        => Drain_Need_Input,
              when Parser_Core.Drain_Document_Complete => Drain_Document_Complete,
              when Parser_Core.Drain_Parse_Failed      => Drain_Failed,
              when Parser_Core.Drain_Call_Rejected     => Drain_Rejected),
         Input_Origin => Byte_Offset (Core_Result.Input_First),
         Consumed     => Core_Result.Consumed,
         Produced     => Core_Result.Produced,
         Diagnostic   =>
           (if Core_Result.Stop in Parser_Core.Drain_Parse_Failed | Parser_Core.Drain_Call_Rejected
            then Map_Diagnostic (Core_Result.Diagnostic)
            else Empty_Diagnostic));
   end Drain;

   procedure Abort_Document (Self : in out Parser) is
   begin
      if Self.Current_State in Ready | Active | Failure_Pending then
         Parser_Core.Abort_Document (Self.Core_Data);
         Sync_State (Self);
      end if;
   end Abort_Document;

   procedure Reset
     (Self : in out Parser; Profile : Profiles.Parser_Profile; Diagnostic : out Errors.Diagnostic)
   is
   begin
      if Self.Current_State not in Failure_Pending | Completed | Failed | Aborted then
         Diagnostic := Rejection_Diagnostic (Self);
         return;
      end if;

      --  An admitted Reset starts a new operation even when its explicit
      --  profile is rejected.  Such rejection therefore occurs at byte zero,
      --  rather than retaining the previous operation's terminal origin.
      Self.Next_Origin := 0;
      Diagnostic := Validate_Profile (Profile);
      if Diagnostic.Code /= Errors.No_Error then
         Self.Current_State := Failed;
         Self.Has_Profile := False;
         Self.Last_Diagnostic := Diagnostic;
         return;
      end if;

      if Self.Core_Initialized then
         Parser_Core.Reset (Self.Core_Data, Root_Policy_Of (Profile.Top_Level));
      else
         Parser_Core.Initialize (Self.Core_Data, Root_Policy_Of (Profile.Top_Level));
         Self.Core_Initialized := True;
      end if;

      Self.Current_State := Ready;
      Self.Has_Profile := True;
      Self.Applied_Profile_Data := Profile;
      Self.Last_Diagnostic := Empty_Diagnostic;
      Self.Next_Origin := 0;
      Diagnostic := Empty_Diagnostic;
   end Reset;

   function State (Self : Parser) return Parser_State
   is (Self.Current_State);

   function Has_Applied_Profile (Self : Parser) return Boolean
   is (Self.Has_Profile);

   function Applied_Profile (Self : Parser) return Profiles.Parser_Profile
   is (Self.Applied_Profile_Data);

   function Terminal_Diagnostic (Self : Parser) return Errors.Diagnostic
   is (Self.Last_Diagnostic);

end Flyology_JSON.Parsing;
