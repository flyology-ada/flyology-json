with Ada.Streams;
with Flyology_JSON.Destinations;
with Flyology_JSON.Errors;
with Flyology_JSON.Numbers.Signed_Integers;
with Flyology_JSON.Numbers.Unsigned_Integers;
with Flyology_JSON.Profiles;
with Flyology_JSON.Tokens;
with Interfaces;

procedure Flyology_JSON.Public_Foundation_Tests is

   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Count;
   use type Destinations.Abort_Status;
   use type Destinations.Begin_Status;
   use type Destinations.Commit_Status;
   use type Destinations.Write_Status;
   use type Errors.Byte_Offset;
   use type Errors.Coordinate_Kind;
   use type Errors.Error_Code;
   use type Numbers.Render_Status;
   use type Profiles.Profile_Status;
   use type Tokens.Collector_State;
   use type Tokens.Collector_Status;
   use type Tokens.Token_Kind;
   use type Tokens.Token_Storage;

   subtype Offset is Ada.Streams.Stream_Element_Offset;

   procedure Check (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Check;

   procedure Check_Profiles is
      Parser : constant Profiles.Parser_Profile :=
        (Syntax        => (Family => Profiles.RFC_8259, Version => 1),
         Unicode       => (Family => Profiles.Unicode_Scalars, Version => 1),
         Compatibility => (Family => Profiles.No_Extensions, Version => 1),
         BOM           => Profiles.Reject_BOM,
         Duplicates    => Profiles.Reject_Duplicates,
         Top_Level     => Profiles.Accept_Any_Value);
      Writer : constant Profiles.Writer_Profile :=
        (Syntax     => (Family => Profiles.RFC_8259, Version => 1),
         Unicode    => (Family => Profiles.Unicode_Scalars, Version => 1),
         Formatting => (Policy => Profiles.Ordinary_Compact, Version => 1));
   begin
      Check (Profiles.Validate (Parser) = Profiles.Profile_Supported, "strict parser profile rejected");
      for Family in Profiles.Compatibility_Family loop
         Check
           (Profiles.Validate
              ((Parser with delta Compatibility => (Family => Family, Version => 1)))
            = Profiles.Profile_Supported,
            "declared compatibility family was rejected");
      end loop;
      Check (Profiles.Validate (Writer) = Profiles.Profile_Supported, "compact writer profile rejected");
      Check
        (Profiles.Validate ((Parser with delta Syntax => (Family => Profiles.RFC_8259, Version => 2)))
         = Profiles.Profile_Unsupported,
         "unknown parser syntax version accepted");
      Check
        (Profiles.Validate
           ((Parser with delta Unicode => (Family => Profiles.Unicode_Scalars, Version => 2)))
         = Profiles.Profile_Unsupported,
         "unknown parser Unicode version accepted");
      Check
        (Profiles.Validate
           ((Parser with delta Compatibility => (Family => Profiles.No_Extensions, Version => 2)))
         = Profiles.Profile_Unsupported,
         "unknown parser compatibility version accepted");
      Check
        (Profiles.Validate ((Writer with delta Syntax => (Family => Profiles.RFC_8259, Version => 2)))
         = Profiles.Profile_Unsupported,
         "unknown writer syntax version accepted");
      Check
        (Profiles.Validate
           ((Writer with delta Unicode => (Family => Profiles.Unicode_Scalars, Version => 2)))
         = Profiles.Profile_Unsupported,
         "unknown writer Unicode version accepted");
      Check
        (Profiles.Validate
           ((Writer with delta Formatting => (Policy => Profiles.Ordinary_Compact, Version => 2)))
         = Profiles.Profile_Unsupported,
         "unknown writer output version accepted");
   end Check_Profiles;

   procedure Check_Destinations is
      Begin_Result  : Destinations.Begin_Status := Destinations.Begin_Succeeded with Volatile;
      Write_Result  : Destinations.Write_Status := Destinations.Write_Succeeded with Volatile;
      Commit_Result : Destinations.Commit_Status := Destinations.Commit_Succeeded with Volatile;
      Abort_Result  : Destinations.Abort_Status := Destinations.Abort_Succeeded with Volatile;
   begin
      Check (Begin_Result = Destinations.Begin_Succeeded, "begin success outcome unavailable");
      Begin_Result := Destinations.Begin_Failed;
      Check (Begin_Result = Destinations.Begin_Failed, "begin failure outcome unavailable");

      Check (Write_Result = Destinations.Write_Succeeded, "write success outcome unavailable");
      Write_Result := Destinations.Write_Exhausted;
      Check (Write_Result = Destinations.Write_Exhausted, "write exhaustion outcome unavailable");
      Write_Result := Destinations.Write_Failed;
      Check (Write_Result = Destinations.Write_Failed, "write failure outcome unavailable");

      Check (Commit_Result = Destinations.Commit_Succeeded, "commit success outcome unavailable");
      Commit_Result := Destinations.Commit_Failed;
      Check (Commit_Result = Destinations.Commit_Failed, "commit failure outcome unavailable");

      Check (Abort_Result = Destinations.Abort_Succeeded, "abort success outcome unavailable");
      Abort_Result := Destinations.Abort_Failed;
      Check (Abort_Result = Destinations.Abort_Failed, "abort failure outcome unavailable");
   end Check_Destinations;

   procedure Check_Diagnostics is
      Item : Errors.Diagnostic :=
        (Code                 => Errors.Invalid_Number,
         Coordinate           => Errors.Source_Byte,
         Offset               => 17,
         Secondary            => Errors.Abort_Failed,
         Secondary_Coordinate => Errors.Staged_Output_Byte,
         Secondary_Offset     => 23);
   begin
      Errors.Clear (Item);
      Check (Item.Code = Errors.No_Error, "Clear retained primary code");
      Check (Item.Coordinate = Errors.No_Coordinate, "Clear retained primary coordinate");
      Check (Item.Offset = 0, "Clear retained primary offset");
      Check (Item.Secondary = Errors.No_Error, "Clear retained secondary code");
      Check (Item.Secondary_Coordinate = Errors.No_Coordinate, "Clear retained secondary coordinate");
      Check (Item.Secondary_Offset = 0, "Clear retained secondary offset");
   end Check_Diagnostics;

   procedure Check_Collector is
      Storage : aliased Tokens.Token_Storage :=
        [-4 => 16#A5#, -3 => 16#A5#, -2 => 16#A5#, -1 => 16#A5#];
      Subject : Tokens.Collector (Storage'Access);
      Status  : Tokens.Collector_Status;
      First   : constant Ada.Streams.Stream_Element_Array :=
        [Offset (11) => 1, Offset (12) => 2, Offset (13) => 3];
      Exact    : constant Ada.Streams.Stream_Element_Array :=
        [Offset (7) => 9, Offset (8) => 8, Offset (9) => 7, Offset (10) => 6];
      Too_Much : constant Ada.Streams.Stream_Element_Array :=
        [Offset (-9) => 4, Offset (-8) => 5];
      Empty    : Ada.Streams.Stream_Element_Array (31 .. 30);

      procedure Fill_Sentinel is
      begin
         Storage := [-4 => 16#A5#, -3 => 16#A5#, -2 => 16#A5#, -1 => 16#A5#];
      end Fill_Sentinel;

      procedure Enter_Collecting is
      begin
         Tokens.Begin_Token (Subject, Tokens.Exact_Number, Status);
         Check (Status = Tokens.Operation_Accepted, "could not enter Collecting");
      end Enter_Collecting;

      procedure Enter_Complete is
      begin
         Enter_Collecting;
         Tokens.Append (Subject, First, Status);
         Check (Status = Tokens.Operation_Accepted, "could not stage completed token");
         Tokens.Complete_Token (Subject, Status);
         Check (Status = Tokens.Token_Completed, "could not enter Complete");
      end Enter_Complete;

      procedure Enter_Failed is
      begin
         Enter_Collecting;
         Tokens.Append (Subject, First, Status);
         Check (Status = Tokens.Operation_Accepted, "could not stage failed token prefix");
         Tokens.Append (Subject, Too_Much, Status);
         Check (Status = Tokens.Storage_Exhausted, "could not enter Failed");
      end Enter_Failed;
   begin
      --  Empty: invalid status-returning calls preserve state and storage;
      --  Abort and Reset are both idempotent.
      Tokens.Append (Subject, First, Status);
      Check (Status = Tokens.Invalid_Order, "append before begin changed order result");
      Check (Tokens.State (Subject) = Tokens.Empty, "append before begin changed state");
      Tokens.Complete_Token (Subject, Status);
      Check (Status = Tokens.Invalid_Order, "complete in Empty changed order result");
      Check (Tokens.State (Subject) = Tokens.Empty, "complete in Empty changed state");
      Check
        (Storage = Tokens.Token_Storage'(-4 => 16#A5#, -3 => 16#A5#, -2 => 16#A5#, -1 => 16#A5#),
         "invalid Empty calls changed storage");
      Tokens.Abort_Token (Subject);
      Check (Tokens.State (Subject) = Tokens.Empty, "abort in Empty changed state");
      Tokens.Reset (Subject);
      Check (Tokens.State (Subject) = Tokens.Empty, "reset in Empty changed state");

      --  Collecting: a second begin is rejected without changing kind or the
      --  already staged prefix.  Abort and Reset each discard the candidate.
      Enter_Collecting;
      Check (Tokens.Kind (Subject) = Tokens.Exact_Number, "collector lost token kind");
      Tokens.Append (Subject, Empty, Status);
      Check (Status = Tokens.Operation_Accepted, "empty append failed");
      Tokens.Append (Subject, First, Status);
      Check (Status = Tokens.Operation_Accepted, "arbitrary-bound append failed");
      Tokens.Begin_Token (Subject, Tokens.Decoded_Name, Status);
      Check (Status = Tokens.Invalid_Order, "begin in Collecting changed order result");
      Check (Tokens.State (Subject) = Tokens.Collecting, "begin in Collecting changed state");
      Check (Tokens.Kind (Subject) = Tokens.Exact_Number, "invalid begin changed token kind");
      Check (Storage (-4 .. -2) = First, "invalid begin changed staged prefix");
      Tokens.Abort_Token (Subject);
      Check (Tokens.State (Subject) = Tokens.Empty, "abort did not clear Collecting");

      Enter_Collecting;
      Tokens.Reset (Subject);
      Check (Tokens.State (Subject) = Tokens.Empty, "reset did not clear Collecting");

      --  Empty completion is a valid published token.
      Tokens.Begin_Token (Subject, Tokens.Decoded_String, Status);
      Tokens.Complete_Token (Subject, Status);
      Check (Status = Tokens.Token_Completed, "empty token did not complete");
      Check (Tokens.Collected_Length (Subject) = 0, "empty token published bytes");
      Tokens.Reset (Subject);

      --  Filling the storage exactly is accepted and directly readable as a
      --  Stream_Element_Array without an array type conversion.
      Fill_Sentinel;
      Enter_Collecting;
      Tokens.Append (Subject, Exact, Status);
      Check (Status = Tokens.Operation_Accepted, "exact capacity was denied");
      Tokens.Complete_Token (Subject, Status);
      Check (Status = Tokens.Token_Completed, "exact-capacity token did not complete");
      Check (Tokens.Collected_Length (Subject) = Exact'Length, "exact capacity length changed");
      Check (Storage = Exact, "exact-capacity token contents changed");

      --  Every invalid status-returning call in Complete preserves the
      --  published length and bytes.
      Tokens.Begin_Token (Subject, Tokens.Decoded_Name, Status);
      Check (Status = Tokens.Invalid_Order, "begin after completion skipped reset");
      Check (Tokens.State (Subject) = Tokens.Complete, "invalid begin revoked completion");
      Tokens.Append (Subject, First, Status);
      Check (Status = Tokens.Invalid_Order, "append in Complete changed order result");
      Tokens.Complete_Token (Subject, Status);
      Check (Status = Tokens.Invalid_Order, "complete in Complete changed order result");
      Check (Tokens.Collected_Length (Subject) = Exact'Length, "invalid Complete call changed length");
      Check (Storage = Exact, "invalid Complete call changed storage");
      Tokens.Abort_Token (Subject);
      Check (Tokens.State (Subject) = Tokens.Empty, "abort did not clear Complete");

      Fill_Sentinel;
      Enter_Complete;
      Check (Tokens.Collected_Length (Subject) = 3, "completed length changed");
      Check
        (Storage = Tokens.Token_Storage'(-4 => 1, -3 => 2, -2 => 3, -1 => 16#A5#),
         "collector copied into the wrong arbitrary-bound prefix");
      Tokens.Reset (Subject);
      Check (Tokens.State (Subject) = Tokens.Empty, "reset did not clear Complete");

      --  Capacity failure copies none of the denied Append.  Every invalid
      --  status-returning call in Failed preserves state and staged storage.
      Fill_Sentinel;
      Enter_Failed;
      Check (Tokens.State (Subject) = Tokens.Failed, "capacity failure did not enter Failed");
      Check (Storage (-1) = 16#A5#, "denied append partially copied");
      Tokens.Begin_Token (Subject, Tokens.Decoded_Name, Status);
      Check (Status = Tokens.Invalid_Order, "begin in Failed changed order result");
      Tokens.Append (Subject, First, Status);
      Check (Status = Tokens.Invalid_Order, "append in Failed changed order result");
      Tokens.Complete_Token (Subject, Status);
      Check (Status = Tokens.Invalid_Order, "complete in Failed changed order result");
      Check (Tokens.State (Subject) = Tokens.Failed, "invalid Failed call changed state");
      Check
        (Storage = Tokens.Token_Storage'(-4 => 1, -3 => 2, -2 => 3, -1 => 16#A5#),
         "invalid Failed call changed storage");
      Tokens.Abort_Token (Subject);
      Check (Tokens.State (Subject) = Tokens.Empty, "abort did not clear Failed");

      Fill_Sentinel;
      Enter_Failed;
      Tokens.Reset (Subject);
      Check (Tokens.State (Subject) = Tokens.Empty, "reset did not clear Failed");
   end Check_Collector;

   procedure Check_Null_Collector is
      Storage : aliased Tokens.Token_Storage := [Offset (5) .. Offset (4) => 0];
      Subject : Tokens.Collector (Storage'Access);
      Status  : Tokens.Collector_Status;
      Empty   : Ada.Streams.Stream_Element_Array (Offset (-2) .. Offset (-3));
      One     : constant Ada.Streams.Stream_Element_Array := [Offset (-7) => 1];
   begin
      Tokens.Begin_Token (Subject, Tokens.Exact_Number, Status);
      Check (Status = Tokens.Operation_Accepted, "null collector begin failed");
      Tokens.Append (Subject, Empty, Status);
      Check (Status = Tokens.Operation_Accepted, "null collector empty append failed");
      Tokens.Complete_Token (Subject, Status);
      Check (Status = Tokens.Token_Completed, "null collector completion failed");
      Check (Tokens.Collected_Length (Subject) = 0, "null collector published bytes");

      Tokens.Reset (Subject);
      Tokens.Begin_Token (Subject, Tokens.Decoded_String, Status);
      Tokens.Append (Subject, One, Status);
      Check (Status = Tokens.Storage_Exhausted, "null collector accepted a nonempty value");
      Check (Tokens.State (Subject) = Tokens.Failed, "null collector denial did not fail");
   end Check_Null_Collector;

   procedure Check_Signed_Integers is
      type Small_Integer is range -128 .. 127;
      type Positive_Integer is range 1 .. 9;
      type Negative_Integer is range -9 .. -1;

      package Small_JSON is new Numbers.Signed_Integers (Small_Integer);
      package Positive_JSON is new Numbers.Signed_Integers (Positive_Integer);
      package Negative_JSON is new Numbers.Signed_Integers (Negative_Integer);
      package Int64_JSON is new Numbers.Signed_Integers (Interfaces.Integer_64);

      use type Small_JSON.Parse_Status;
      use type Positive_JSON.Parse_Status;
      use type Negative_JSON.Parse_Status;
      use type Int64_JSON.Parse_Status;
      use type Interfaces.Integer_64;

      Result   : Small_JSON.Parse_Result;
      Positive : Positive_JSON.Parse_Result;
      Negative : Negative_JSON.Parse_Result;
      Int64    : Int64_JSON.Parse_Result;

      function Input (Value : String; First : Offset) return Ada.Streams.Stream_Element_Array is
         Item : Ada.Streams.Stream_Element_Array
           (First .. First + Offset (Value'Length) - 1);
      begin
         for Position in Value'Range loop
            Item (First + Offset (Position - Value'First)) :=
              Ada.Streams.Stream_Element (Character'Pos (Value (Position)));
         end loop;
         return Item;
      end Input;

      procedure Expect
        (Value : String; Status : Small_JSON.Parse_Status; Expected : Small_Integer := 0)
      is
      begin
         Small_JSON.Parse (Input (Value, -17), Result);
         Check (Result.Status = Status, "signed parse status differs for " & Value);
         if Status = Small_JSON.Converted then
            Check (Result.Value = Expected, "signed parse value differs for " & Value);
         end if;
      end Expect;

      Output   : Ada.Streams.Stream_Element_Array (-11 .. -7) := [others => 16#A5#];
      Short    : Ada.Streams.Stream_Element_Array (20 .. 22) := [others => 16#A5#];
      Produced : Ada.Streams.Stream_Element_Count;
      Status   : Numbers.Render_Status;
   begin
      Small_JSON.Parse ([Offset (4) .. Offset (3) => 0], Result);
      Check (Result.Status = Small_JSON.Invalid_Syntax, "empty signed spelling accepted");

      Expect ("0", Small_JSON.Converted, 0);
      Expect ("-0", Small_JSON.Converted, 0);
      Expect ("127", Small_JSON.Converted, 127);
      Expect ("-128", Small_JSON.Converted, -128);
      Expect ("128", Small_JSON.Above_Range);
      Expect ("-129", Small_JSON.Below_Range);
      Expect ("01", Small_JSON.Invalid_Syntax);
      Expect ("+1", Small_JSON.Invalid_Syntax);
      Expect ("1.0", Small_JSON.Invalid_Syntax);
      Expect ("1e2", Small_JSON.Invalid_Syntax);
      Expect ("1x", Small_JSON.Invalid_Syntax);

      Positive_JSON.Parse (Input ("0", 31), Positive);
      Check (Positive.Status = Positive_JSON.Below_Range, "positive-only lower bound missed");
      Positive_JSON.Parse (Input ("-1", 31), Positive);
      Check (Positive.Status = Positive_JSON.Below_Range, "positive-only negative accepted");
      Negative_JSON.Parse (Input ("0", 31), Negative);
      Check (Negative.Status = Negative_JSON.Above_Range, "negative-only upper bound missed");
      Negative_JSON.Parse (Input ("-0", 31), Negative);
      Check (Negative.Status = Negative_JSON.Above_Range, "negative-only -0 accepted");

      Int64_JSON.Parse (Input ("9223372036854775807", -41), Int64);
      Check (Int64.Status = Int64_JSON.Converted, "int64 maximum was rejected");
      Check (Int64.Value = Interfaces.Integer_64'Last, "int64 maximum changed");
      Int64_JSON.Parse (Input ("-9223372036854775808", 77), Int64);
      Check (Int64.Status = Int64_JSON.Converted, "int64 minimum was rejected");
      Check (Int64.Value = Interfaces.Integer_64'First, "int64 minimum changed");
      Int64_JSON.Parse (Input ("9223372036854775808", -41), Int64);
      Check (Int64.Status = Int64_JSON.Above_Range, "int64 overflow was accepted");
      Int64_JSON.Parse (Input ("-9223372036854775809", 77), Int64);
      Check (Int64.Status = Int64_JSON.Below_Range, "int64 underflow was accepted");

      Small_JSON.Render (-128, Output, Produced, Status);
      Check (Status = Numbers.Rendered, "signed render failed");
      Check (Produced = 4, "signed render length differs");
      Check (Output (-11 .. -8) = Input ("-128", -11), "signed render bytes differ");
      Check (Output (-7) = 16#A5#, "signed render changed output suffix");

      Small_JSON.Render (-128, Short, Produced, Status);
      Check (Status = Numbers.Output_Too_Small, "short signed render was accepted");
      Check (Produced = 0, "short signed render published a length");
      Check
        (Short = Ada.Streams.Stream_Element_Array'(20 .. 22 => 16#A5#),
         "short signed render changed output");
   end Check_Signed_Integers;

   procedure Check_Unsigned_Integers is
      type Tiny_Modulus is mod 3;

      package UInt32_JSON is new Numbers.Unsigned_Integers (Interfaces.Unsigned_32);
      package UInt64_JSON is new Numbers.Unsigned_Integers (Interfaces.Unsigned_64);
      package Tiny_JSON is new Numbers.Unsigned_Integers (Tiny_Modulus);

      use type Interfaces.Unsigned_32;
      use type UInt32_JSON.Parse_Status;
      use type UInt64_JSON.Parse_Status;
      use type Tiny_JSON.Parse_Status;

      function Input (Value : String; First : Offset) return Ada.Streams.Stream_Element_Array is
         Item : Ada.Streams.Stream_Element_Array
           (First .. First + Offset (Value'Length) - 1);
      begin
         for Position in Value'Range loop
            Item (First + Offset (Position - Value'First)) :=
              Ada.Streams.Stream_Element (Character'Pos (Value (Position)));
         end loop;
         return Item;
      end Input;

      Result_32 : UInt32_JSON.Parse_Result;
      Result_64 : UInt64_JSON.Parse_Result;
      Tiny      : Tiny_JSON.Parse_Result;
      Output    : Ada.Streams.Stream_Element_Array (-31 .. -12) := [others => 16#A5#];
      Short     : Ada.Streams.Stream_Element_Array (9 .. 27) := [others => 16#A5#];
      Produced  : Ada.Streams.Stream_Element_Count;
      Status    : Numbers.Render_Status;
   begin
      UInt32_JSON.Parse (Input ("4294967295", -17), Result_32);
      Check (Result_32.Status = UInt32_JSON.Converted, "uint32 maximum was rejected");
      Check (Result_32.Value = Interfaces.Unsigned_32'Last, "uint32 maximum changed");
      UInt32_JSON.Parse (Input ("4294967296", 41), Result_32);
      Check (Result_32.Status = UInt32_JSON.Above_Range, "uint32 overflow was accepted");

      UInt64_JSON.Parse (Input ("18446744073709551615", -53), Result_64);
      Check (Result_64.Status = UInt64_JSON.Converted, "uint64 maximum was rejected");
      Check (Result_64.Value = Interfaces.Unsigned_64'Last, "uint64 maximum changed");
      UInt64_JSON.Parse (Input ("18446744073709551616", 67), Result_64);
      Check (Result_64.Status = UInt64_JSON.Above_Range, "uint64 overflow was accepted");
      UInt64_JSON.Parse (Input ("-0", -7), Result_64);
      Check (Result_64.Status = UInt64_JSON.Negative_Value, "uint64 accepted -0");
      UInt64_JSON.Parse (Input ("-1", 19), Result_64);
      Check (Result_64.Status = UInt64_JSON.Negative_Value, "uint64 accepted -1");
      UInt64_JSON.Parse (Input ("-01", 19), Result_64);
      Check (Result_64.Status = UInt64_JSON.Invalid_Syntax, "uint64 accepted negative leading zero");
      UInt64_JSON.Parse (Input ("01", 19), Result_64);
      Check (Result_64.Status = UInt64_JSON.Invalid_Syntax, "uint64 accepted leading zero");
      UInt64_JSON.Parse (Input ("1.0", 19), Result_64);
      Check (Result_64.Status = UInt64_JSON.Invalid_Syntax, "uint64 accepted fraction");

      Tiny_JSON.Parse (Input ("2", -5), Tiny);
      Check (Tiny.Status = Tiny_JSON.Converted, "small-modulus endpoint was rejected");
      Check (Tiny.Value = 2, "small-modulus endpoint changed");
      Tiny_JSON.Parse (Input ("3", 8), Tiny);
      Check (Tiny.Status = Tiny_JSON.Above_Range, "small modulus wrapped digit 3");
      Tiny_JSON.Parse (Input ("9", 8), Tiny);
      Check (Tiny.Status = Tiny_JSON.Above_Range, "small modulus wrapped digit 9");

      UInt64_JSON.Render (Interfaces.Unsigned_64'Last, Output, Produced, Status);
      Check (Status = Numbers.Rendered, "uint64 render failed");
      Check (Produced = Output'Length, "uint64 render length changed");
      Check (Output = Input ("18446744073709551615", Output'First), "uint64 render changed bytes");

      UInt64_JSON.Render (Interfaces.Unsigned_64'Last, Short, Produced, Status);
      Check (Status = Numbers.Output_Too_Small, "short uint64 render was accepted");
      Check (Produced = 0, "short uint64 render published a length");
      Check
        (Short = Ada.Streams.Stream_Element_Array'(9 .. 27 => 16#A5#),
         "short uint64 render changed output");
   end Check_Unsigned_Integers;

begin
   Check_Profiles;
   Check_Destinations;
   Check_Diagnostics;
   Check_Collector;
   Check_Null_Collector;
   Check_Signed_Integers;
   Check_Unsigned_Integers;
end Flyology_JSON.Public_Foundation_Tests;
