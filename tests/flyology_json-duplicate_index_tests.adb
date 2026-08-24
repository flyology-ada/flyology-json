with Ada.Streams;
with Ada.Text_IO;
with Flyology_JSON.Parser_Duplicates;
with Interfaces;

procedure Flyology_JSON.Duplicate_Index_Tests is

   package Duplicates renames Flyology_JSON.Parser_Duplicates;

   use type Duplicates.Name_Classification;
   use type Duplicates.Operation_Status;
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Unsigned_32;

   Failures : Natural := 0;

   procedure Check (Condition : Boolean; Label : String) is
   begin
      if not Condition then
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "FAIL: " & Label);
         Failures := Failures + 1;
      end if;
   end Check;

   --  These bounds size only the deterministic test oracle.  They are not
   --  parser policy, defaults, or reusable operational limits.
   Oracle_Key_Capacity   : constant := 32;
   Oracle_Octet_Capacity : constant := 320;

   subtype Oracle_Key_Length is Natural range 0 .. Oracle_Octet_Capacity;
   subtype Oracle_Entry_Index is Positive range 1 .. Oracle_Key_Capacity;
   type Oracle_Octets is
     array (Positive range 1 .. Oracle_Octet_Capacity) of Ada.Streams.Stream_Element;

   type Oracle_Key is record
      Length : Oracle_Key_Length := 0;
      Octets : Oracle_Octets := [others => 0];
   end record;

   type Oracle_Entry_Array is array (Oracle_Entry_Index) of Oracle_Key;

   type Linear_Oracle is record
      Count        : Natural range 0 .. Oracle_Key_Capacity := 0;
      Stored_Octets : Natural := 0;
      Entries      : Oracle_Entry_Array;
   end record;

   function Equal (Left, Right : Oracle_Key) return Boolean is
   begin
      if Left.Length /= Right.Length then
         return False;
      end if;

      for Position in 1 .. Left.Length loop
         if Left.Octets (Position) /= Right.Octets (Position) then
            return False;
         end if;
      end loop;
      return True;
   end Equal;

   function Contains (Oracle : Linear_Oracle; Value : Oracle_Key) return Boolean is
   begin
      for Position in 1 .. Oracle.Count loop
         if Equal (Oracle.Entries (Position), Value) then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

   procedure Insert (Oracle : in out Linear_Oracle; Value : Oracle_Key) is
   begin
      Check (Oracle.Count < Oracle_Key_Capacity, "linear oracle capacity");
      if Oracle.Count < Oracle_Key_Capacity then
         Oracle.Count := Oracle.Count + 1;
         Oracle.Entries (Oracle.Count) := Value;
         Oracle.Stored_Octets := Oracle.Stored_Octets + Value.Length;
      end if;
   end Insert;

   procedure Clear (Oracle : out Linear_Oracle) is
   begin
      Oracle := (Count => 0, Stored_Octets => 0, Entries => [others => <>]);
   end Clear;

   function Next_Random (State : in out Interfaces.Unsigned_32) return Interfaces.Unsigned_32 is
   begin
      --  Fixed LCG parameters make failures exactly reproducible.  This is a
      --  test schedule generator, not a source of security randomness.
      State := State * 1_664_525 + 1_013_904_223;
      return State;
   end Next_Random;

   type Order_Array is array (Positive range <>) of Positive;

   procedure Shuffle (Order : in out Order_Array; State : in out Interfaces.Unsigned_32) is
   begin
      for Position in reverse Order'First + 1 .. Order'Last loop
         declare
            Span   : constant Positive := Position - Order'First + 1;
            Choice : constant Positive :=
              Order'First + Natural (Next_Random (State) mod Interfaces.Unsigned_32 (Span));
            Saved  : constant Positive := Order (Position);
         begin
            Order (Position) := Order (Choice);
            Order (Choice) := Saved;
         end;
      end loop;
   end Shuffle;

   procedure Add_And_Check
     (Index  : in out Duplicates.Index;
      Object : in out Duplicates.Object_Context;
      Oracle : in out Linear_Oracle;
      Value  : Oracle_Key;
      Label  : String) is
      Status         : Duplicates.Operation_Status;
      Classification : Duplicates.Name_Classification;
      Expected       : constant Duplicates.Name_Classification :=
        (if Contains (Oracle, Value) then Duplicates.Duplicate_Name else Duplicates.Unique_Name);
      Cursor         : Natural := 1;
   begin
      Duplicates.Begin_Name (Index, Object, Status);
      Check (Status = Duplicates.Operation_Succeeded, Label & " begin");
      if Status /= Duplicates.Operation_Succeeded then
         return;
      end if;

      --  A null array with a non-one lower bound is a successful no-op while
      --  a candidate is active.
      declare
         Empty : constant Ada.Streams.Stream_Element_Array (-11 .. -12) := [others => 0];
      begin
         Duplicates.Append_Octets (Index, Empty, Status);
         Check (Status = Duplicates.Operation_Succeeded, Label & " null append");
      end;

      while Cursor <= Value.Length and then Status = Duplicates.Operation_Succeeded loop
         declare
            Remaining : constant Positive := Value.Length - Cursor + 1;
            Amount    : constant Positive := Positive'Min (1 + Cursor mod 13, Remaining);
            First     : constant Ada.Streams.Stream_Element_Offset :=
              Ada.Streams.Stream_Element_Offset (-37 + Cursor mod 19);
            Last      : constant Ada.Streams.Stream_Element_Offset :=
              First + Ada.Streams.Stream_Element_Offset (Amount) - 1;
            Chunk     : Ada.Streams.Stream_Element_Array (First .. Last);
         begin
            for Offset in 0 .. Amount - 1 loop
               Chunk (First + Ada.Streams.Stream_Element_Offset (Offset)) :=
                 Value.Octets (Cursor + Offset);
            end loop;
            Duplicates.Append_Octets (Index, Chunk, Status);
            Check (Status = Duplicates.Operation_Succeeded, Label & " append");
            Cursor := Cursor + Amount;
         end;
      end loop;

      if Status = Duplicates.Operation_Succeeded then
         Duplicates.Complete_Name (Index, Object, Status, Classification);
         Check (Status = Duplicates.Operation_Succeeded, Label & " complete");
         if Status = Duplicates.Operation_Succeeded then
            Check (Classification = Expected, Label & " classification");
            if Expected = Duplicates.Unique_Name then
               Insert (Oracle, Value);
            end if;
         end if;
      end if;
   end Add_And_Check;

   function Prefix_Key (Length : Oracle_Key_Length) return Oracle_Key is
      Result : Oracle_Key := (Length => Length, Octets => [others => 0]);
   begin
      --  73 is relatively prime to 256, so longer fixtures contain every
      --  octet value.  Different lengths deliberately share exact prefixes.
      for Position in 1 .. Length loop
         Result.Octets (Position) := Ada.Streams.Stream_Element ((Position * 73 + 19) mod 256);
      end loop;
      return Result;
   end Prefix_Key;

   function Random_Key
     (State : in out Interfaces.Unsigned_32;
      Limit : Oracle_Key_Length) return Oracle_Key is
      Result : Oracle_Key;
   begin
      Result.Length :=
        Natural (Next_Random (State) mod Interfaces.Unsigned_32 (Natural (Limit) + 1));
      for Position in 1 .. Result.Length loop
         Result.Octets (Position) :=
           Ada.Streams.Stream_Element (Next_Random (State) mod Interfaces.Unsigned_32'(256));
      end loop;
      return Result;
   end Random_Key;

   procedure Add_String
     (Index          : in out Duplicates.Index;
      Object         : in out Duplicates.Object_Context;
      Value          : String;
      Expected       : Duplicates.Name_Classification;
      Expected_Status : Duplicates.Operation_Status := Duplicates.Operation_Succeeded) is
      Status         : Duplicates.Operation_Status;
      Classification : Duplicates.Name_Classification;
   begin
      Duplicates.Begin_Name (Index, Object, Status);
      Check (Status = Duplicates.Operation_Succeeded, "begin name for " & Value);
      if Status /= Duplicates.Operation_Succeeded then
         return;
      end if;

      for Position in Value'Range loop
         declare
            --  Deliberately non-one lower bounds exercise arbitrary-bound
            --  decoded-scalar input independently of parser chunk bounds.
            First  : constant Ada.Streams.Stream_Element_Offset :=
              Ada.Streams.Stream_Element_Offset (-17 + Position - Value'First);
            Octets : Ada.Streams.Stream_Element_Array (First .. First);
         begin
            Octets (First) := Character'Pos (Value (Position));
            Duplicates.Append_Octets (Index, Octets, Status);
            Check (Status = Duplicates.Operation_Succeeded, "append name for " & Value);
            exit when Status /= Duplicates.Operation_Succeeded;
         end;
      end loop;

      if Status = Duplicates.Operation_Succeeded then
         Duplicates.Complete_Name (Index, Object, Status, Classification);
         Check (Status = Expected_Status, "complete status for " & Value);
         if Status = Duplicates.Operation_Succeeded then
            Check (Classification = Expected, "classification for " & Value);
         end if;
      end if;
   end Add_String;

   procedure Check_Basic_Equality is
      --  Capacities exactly cover this fixture family; they are test storage,
      --  not production policy or parser defaults.
      Index  : Duplicates.Index (Name_Octet_Capacity => 64, Name_Capacity => 16);
      Object : Duplicates.Object_Context;
   begin
      Duplicates.Reset (Index);
      Duplicates.Begin_Object (Index, Object);
      Add_String (Index, Object, "", Duplicates.Unique_Name);
      Add_String (Index, Object, "a", Duplicates.Unique_Name);
      Add_String (Index, Object, "ab", Duplicates.Unique_Name);
      Add_String (Index, Object, "abc", Duplicates.Unique_Name);
      Add_String (Index, Object, "b", Duplicates.Unique_Name);
      Add_String (Index, Object, "a", Duplicates.Duplicate_Name);
      Add_String (Index, Object, "", Duplicates.Duplicate_Name);
      Add_String (Index, Object, "ab", Duplicates.Duplicate_Name);
      Check (Duplicates.Stored_Leaves (Index) = 5, "basic unique leaf count");
      Check (Duplicates.Stored_Nodes (Index) = 4, "basic internal node count");
      Duplicates.End_Object (Index, Object);
      Check (Duplicates.Stored_Name_Octets (Index) = 0, "object close restored name bytes");
      Check (Duplicates.Stored_Leaves (Index) = 0, "object close restored leaves");
      Check (Duplicates.Stored_Nodes (Index) = 0, "object close restored nodes");
   end Check_Basic_Equality;

   procedure Check_All_Orders is
      Key_Count : constant := 6;
      type Order_Array is array (Positive range 1 .. Key_Count) of Positive;
      type Used_Array is array (Positive range 1 .. Key_Count) of Boolean;
      Order : Order_Array := [others => 1];
      Used  : Used_Array := [others => False];
      Runs  : Natural := 0;

      procedure Add_Key
        (Index  : in out Duplicates.Index;
         Object : in out Duplicates.Object_Context;
         Key    : Positive;
         Kind   : Duplicates.Name_Classification) is
      begin
         case Key is
            when 1 => Add_String (Index, Object, "", Kind);
            when 2 => Add_String (Index, Object, String'(1 => Character'Val (0)), Kind);
            when 3 => Add_String (Index, Object, "a", Kind);
            when 4 => Add_String (Index, Object, "aa", Kind);
            when 5 => Add_String (Index, Object, "ab", Kind);
            when 6 => Add_String (Index, Object, "b", Kind);
            when others => raise Program_Error;
         end case;
      end Add_Key;

      procedure Run_Order is
         Index  : Duplicates.Index (Name_Octet_Capacity => 16, Name_Capacity => Key_Count);
         Object : Duplicates.Object_Context;
      begin
         Duplicates.Reset (Index);
         Duplicates.Begin_Object (Index, Object);
         for Position in Order'Range loop
            Add_Key (Index, Object, Order (Position), Duplicates.Unique_Name);
         end loop;
         for Key in 1 .. Key_Count loop
            Add_Key (Index, Object, Key, Duplicates.Duplicate_Name);
         end loop;
         Check (Duplicates.Stored_Leaves (Index) = Key_Count, "permutation leaf count");
         Check (Duplicates.Stored_Nodes (Index) = Key_Count - 1, "permutation node count");
         Runs := Runs + 1;
      end Run_Order;

      procedure Generate (Position : Positive) is
      begin
         if Position > Key_Count then
            Run_Order;
         else
            for Key in 1 .. Key_Count loop
               if not Used (Key) then
                  Used (Key) := True;
                  Order (Position) := Key;
                  Generate (Position + 1);
                  Used (Key) := False;
               end if;
            end loop;
         end if;
      end Generate;
   begin
      Generate (1);
      Check (Runs = 720, "all six-key insertion orders ran");
   end Check_All_Orders;

   procedure Check_Adversarial_Prefixes is
      Prefix_Count : constant := 128;
      --  Sum 1 .. 128 plus the longest duplicate candidate is 8,384.  These
      --  exact fixture capacities are not a reusable operational limit.
      Index  : Duplicates.Index (Name_Octet_Capacity => 8_384, Name_Capacity => Prefix_Count);
      Object : Duplicates.Object_Context;
   begin
      Duplicates.Reset (Index);
      Duplicates.Begin_Object (Index, Object);
      for Length in 1 .. Prefix_Count loop
         Add_String (Index, Object, [1 .. Length => 'a'], Duplicates.Unique_Name);
      end loop;
      for Length in reverse 1 .. Prefix_Count loop
         Add_String (Index, Object, [1 .. Length => 'a'], Duplicates.Duplicate_Name);
      end loop;
      Check (Duplicates.Stored_Leaves (Index) = Prefix_Count, "adversarial leaf count");
      Check (Duplicates.Stored_Nodes (Index) = Prefix_Count - 1, "adversarial node count");
   end Check_Adversarial_Prefixes;

   procedure Check_Length_Boundaries_Against_Oracle is
      type Length_Array is array (Positive range <>) of Oracle_Key_Length;
      Boundary_Lengths : constant Length_Array :=
        [0, 1, 2, 7, 8, 15, 16, 31, 32, 63, 64, 127, 128, 254, 255, 256, 257];
      type Boundary_Key_Array is array (Boundary_Lengths'Range) of Oracle_Key;
      Keys  : Boundary_Key_Array;
      Order : Order_Array (Boundary_Lengths'Range);
      State : Interfaces.Unsigned_32 := 16#7A11_CE55#;
      Index : Duplicates.Index (Name_Octet_Capacity => 4_096, Name_Capacity => 32);
      Object : Duplicates.Object_Context;
      Oracle : Linear_Oracle;
   begin
      for Position in Boundary_Lengths'Range loop
         Keys (Position) := Prefix_Key (Boundary_Lengths (Position));
      end loop;

      --  Multiple deterministic permutations exercise the length-prefix
      --  boundary independently of insertion order, including 255 versus 256.
      for Round in 1 .. 16 loop
         Duplicates.Reset (Index);
         Duplicates.Begin_Object (Index, Object);
         Clear (Oracle);
         for Position in Order'Range loop
            Order (Position) := Position;
         end loop;
         Shuffle (Order, State);

         for Position in Order'Range loop
            Add_And_Check
              (Index,
               Object,
               Oracle,
               Keys (Order (Position)),
               "boundary round" & Natural'Image (Round) & " key" & Natural'Image (Order (Position)));
         end loop;
         Shuffle (Order, State);
         for Position in Order'Range loop
            Add_And_Check
              (Index,
               Object,
               Oracle,
               Keys (Order (Position)),
               "boundary duplicate round" & Natural'Image (Round));
         end loop;

         Check
           (Duplicates.Stored_Name_Octets (Index) = Oracle.Stored_Octets,
            "boundary oracle octet count round" & Natural'Image (Round));
         Check
           (Duplicates.Stored_Leaves (Index) = Oracle.Count,
            "boundary oracle leaf count round" & Natural'Image (Round));
         Check
           (Duplicates.Stored_Nodes (Index) = Oracle.Count - 1,
            "boundary oracle node count round" & Natural'Image (Round));
         Duplicates.End_Object (Index, Object);
      end loop;
   end Check_Length_Boundaries_Against_Oracle;

   procedure Check_Randomized_Against_Oracle is
      type Key_Array is array (Oracle_Entry_Index) of Oracle_Key;
      Keys   : Key_Array;
      Order  : Order_Array (Oracle_Entry_Index);
      State  : Interfaces.Unsigned_32 := 16#C0DE_4A5B#;
      Index  : Duplicates.Index (Name_Octet_Capacity => 4_096, Name_Capacity => 32);
      Object : Duplicates.Object_Context;
      Oracle : Linear_Oracle;
   begin
      --  Reset and reuse one bounded index repeatedly.  Every seventh key is
      --  an intentional duplicate; all other keys contain deterministic
      --  arbitrary octets, with the empty key forced into every round.
      for Round in 1 .. 24 loop
         Duplicates.Reset (Index);
         Duplicates.Begin_Object (Index, Object);
         Clear (Oracle);
         Keys (1) := Prefix_Key (0);
         for Position in 2 .. Oracle_Key_Capacity loop
            if Position mod 7 = 0 then
               Keys (Position) := Keys (Position - 1);
            else
               Keys (Position) := Random_Key (State, 96);
            end if;
         end loop;
         for Position in Order'Range loop
            Order (Position) := Position;
         end loop;
         Shuffle (Order, State);

         for Position in Order'Range loop
            Add_And_Check
              (Index,
               Object,
               Oracle,
               Keys (Order (Position)),
               "property round" & Natural'Image (Round) & " operation" & Natural'Image (Position));
         end loop;
         Shuffle (Order, State);
         for Position in Order'Range loop
            Add_And_Check
              (Index,
               Object,
               Oracle,
               Keys (Order (Position)),
               "property duplicate round" & Natural'Image (Round));
         end loop;

         Check
           (Duplicates.Stored_Name_Octets (Index) = Oracle.Stored_Octets,
            "property oracle octet count round" & Natural'Image (Round));
         Check
           (Duplicates.Stored_Leaves (Index) = Oracle.Count,
            "property oracle leaf count round" & Natural'Image (Round));
         Check
           (Duplicates.Stored_Nodes (Index) = Natural'Max (Oracle.Count, 1) - 1,
            "property oracle node count round" & Natural'Image (Round));

         if Round mod 2 = 0 then
            --  Exercise operation reset against populated live state, not
            --  only after LIFO cleanup has already restored empty marks.
            Duplicates.Reset (Index);
         else
            Duplicates.End_Object (Index, Object);
         end if;
         Check (Duplicates.Stored_Name_Octets (Index) = 0, "property reset name mark");
         Check (Duplicates.Stored_Leaves (Index) = 0, "property reset leaf mark");
         Check (Duplicates.Stored_Nodes (Index) = 0, "property reset node mark");
      end loop;
   end Check_Randomized_Against_Oracle;

   procedure Check_Capacity_Atomicity is
      Status         : Duplicates.Operation_Status;
      Classification : Duplicates.Name_Classification;
   begin
      declare
         Index  : Duplicates.Index (Name_Octet_Capacity => 0, Name_Capacity => 1);
         Object : Duplicates.Object_Context;
      begin
         Duplicates.Reset (Index);
         Duplicates.Begin_Object (Index, Object);
         Add_String (Index, Object, "", Duplicates.Unique_Name);
         Add_String (Index, Object, "", Duplicates.Duplicate_Name);
      end;

      declare
         Index  : Duplicates.Index (Name_Octet_Capacity => 1, Name_Capacity => 2);
         Object : Duplicates.Object_Context;
         First  : constant Ada.Streams.Stream_Element_Offset := -3;
         Pair   : constant Ada.Streams.Stream_Element_Array
           (First .. First + Ada.Streams.Stream_Element_Offset'(1)) := [16#C3#, 16#A9#];
      begin
         Duplicates.Reset (Index);
         Duplicates.Begin_Object (Index, Object);
         Duplicates.Begin_Name (Index, Object, Status);
         Duplicates.Append_Octets (Index, Pair, Status);
         Check (Status = Duplicates.Name_Storage_Exhausted, "scalar capacity denial");
         Check (Duplicates.Stored_Name_Octets (Index) = 0, "scalar capacity denial is atomic");
      end;

      declare
         Index  : Duplicates.Index (Name_Octet_Capacity => 4, Name_Capacity => 1);
         Object : Duplicates.Object_Context;
      begin
         Duplicates.Reset (Index);
         Duplicates.Begin_Object (Index, Object);
         Add_String (Index, Object, "a", Duplicates.Unique_Name);
         Duplicates.Begin_Name (Index, Object, Status);
         declare
            Byte : constant Ada.Streams.Stream_Element_Array (9 .. 9) := [Character'Pos ('b')];
         begin
            Duplicates.Append_Octets (Index, Byte, Status);
         end;
         Duplicates.Complete_Name (Index, Object, Status, Classification);
         Check (Status = Duplicates.Index_Storage_Exhausted, "unique index capacity denial");
         Check (Duplicates.Stored_Leaves (Index) = 1, "index denial did not add a leaf");
         Check (Duplicates.Stored_Nodes (Index) = 0, "index denial did not add a node");
      end;

      declare
         Index  : Duplicates.Index (Name_Octet_Capacity => 1, Name_Capacity => 0);
         Object : Duplicates.Object_Context;
      begin
         Duplicates.Reset (Index);
         Duplicates.Begin_Object (Index, Object);
         Duplicates.Begin_Name (Index, Object, Status);
         Check (Status = Duplicates.Index_Storage_Exhausted, "zero index rejected at name begin");
         Check (Duplicates.Stored_Name_Octets (Index) = 0, "zero index retained no candidate");
      end;
   end Check_Capacity_Atomicity;

   procedure Check_Nested_LIFO is
      Index  : Duplicates.Index (Name_Octet_Capacity => 4_096, Name_Capacity => 32);
      Outer  : Duplicates.Object_Context;
      Middle : Duplicates.Object_Context;
      Inner  : Duplicates.Object_Context;
      Outer_Oracle  : Linear_Oracle;
      Middle_Oracle : Linear_Oracle;
      Inner_Oracle  : Linear_Oracle;
      Outer_Octet_Mark : Natural;
      Outer_Leaf_Mark  : Natural;
      Outer_Node_Mark  : Natural;
      Middle_Octet_Mark : Natural;
      Middle_Leaf_Mark  : Natural;
      Middle_Node_Mark  : Natural;
   begin
      Duplicates.Reset (Index);
      Clear (Outer_Oracle);
      Clear (Middle_Oracle);
      Clear (Inner_Oracle);

      Duplicates.Begin_Object (Index, Outer);
      Add_And_Check (Index, Outer, Outer_Oracle, Prefix_Key (0), "outer empty");
      Add_And_Check (Index, Outer, Outer_Oracle, Prefix_Key (31), "outer prefix");
      Add_And_Check (Index, Outer, Outer_Oracle, Prefix_Key (256), "outer long prefix");
      Outer_Octet_Mark := Duplicates.Stored_Name_Octets (Index);
      Outer_Leaf_Mark := Duplicates.Stored_Leaves (Index);
      Outer_Node_Mark := Duplicates.Stored_Nodes (Index);

      Duplicates.Begin_Object (Index, Middle);
      Add_And_Check (Index, Middle, Middle_Oracle, Prefix_Key (31), "middle outer-equal");
      Add_And_Check (Index, Middle, Middle_Oracle, Prefix_Key (32), "middle prefix");
      Add_And_Check (Index, Middle, Middle_Oracle, Prefix_Key (32), "middle duplicate");
      Middle_Octet_Mark := Duplicates.Stored_Name_Octets (Index);
      Middle_Leaf_Mark := Duplicates.Stored_Leaves (Index);
      Middle_Node_Mark := Duplicates.Stored_Nodes (Index);

      Duplicates.Begin_Object (Index, Inner);
      Add_And_Check (Index, Inner, Inner_Oracle, Prefix_Key (0), "inner outer-equal");
      Add_And_Check (Index, Inner, Inner_Oracle, Prefix_Key (255), "inner long prefix");
      Add_And_Check (Index, Inner, Inner_Oracle, Prefix_Key (255), "inner duplicate");
      Duplicates.End_Object (Index, Inner);
      Check
        (Duplicates.Stored_Name_Octets (Index) = Middle_Octet_Mark,
         "inner close restored middle octet mark");
      Check (Duplicates.Stored_Leaves (Index) = Middle_Leaf_Mark, "inner close restored middle leaves");
      Check (Duplicates.Stored_Nodes (Index) = Middle_Node_Mark, "inner close restored middle nodes");
      Add_And_Check (Index, Middle, Middle_Oracle, Prefix_Key (31), "middle resume duplicate");

      Duplicates.End_Object (Index, Middle);
      Check
        (Duplicates.Stored_Name_Octets (Index) = Outer_Octet_Mark,
         "middle close restored outer octet mark");
      Check (Duplicates.Stored_Leaves (Index) = Outer_Leaf_Mark, "middle close restored outer leaves");
      Check (Duplicates.Stored_Nodes (Index) = Outer_Node_Mark, "middle close restored outer nodes");
      Add_And_Check (Index, Outer, Outer_Oracle, Prefix_Key (31), "outer resume duplicate");

      Duplicates.End_Object (Index, Outer);
      Check (Duplicates.Stored_Name_Octets (Index) = 0, "outer close restored octets");
      Check (Duplicates.Stored_Leaves (Index) = 0, "outer close restored leaves");
      Check (Duplicates.Stored_Nodes (Index) = 0, "outer close restored nodes");
   end Check_Nested_LIFO;

   procedure Check_Invalid_Order_And_Null_Arrays is
      Index          : Duplicates.Index (Name_Octet_Capacity => 8, Name_Capacity => 2);
      Inactive       : Duplicates.Object_Context;
      Object         : Duplicates.Object_Context;
      Status         : Duplicates.Operation_Status;
      Classification : Duplicates.Name_Classification;
      Empty          : constant Ada.Streams.Stream_Element_Array (23 .. 22) := [others => 0];
   begin
      Duplicates.Reset (Index);
      Duplicates.Begin_Name (Index, Inactive, Status);
      Check (Status = Duplicates.Invalid_Operation_Order, "begin name before object");
      Duplicates.Append_Octets (Index, Empty, Status);
      Check (Status = Duplicates.Invalid_Operation_Order, "null append before name");
      Duplicates.Complete_Name (Index, Inactive, Status, Classification);
      Check (Status = Duplicates.Invalid_Operation_Order, "complete before object");

      Duplicates.Begin_Object (Index, Object);
      Duplicates.Complete_Name (Index, Object, Status, Classification);
      Check (Status = Duplicates.Invalid_Operation_Order, "complete before name");
      Duplicates.Begin_Name (Index, Object, Status);
      Check (Status = Duplicates.Operation_Succeeded, "valid begin before invalid second begin");
      Duplicates.Begin_Name (Index, Object, Status);
      Check (Status = Duplicates.Invalid_Operation_Order, "second begin while candidate active");
      Duplicates.Append_Octets (Index, Empty, Status);
      Check (Status = Duplicates.Operation_Succeeded, "arbitrary-bound null append");
      Duplicates.Complete_Name (Index, Object, Status, Classification);
      Check (Status = Duplicates.Operation_Succeeded, "complete after null append");
      Check (Classification = Duplicates.Unique_Name, "null append preserved empty key");
      Duplicates.Append_Octets (Index, Empty, Status);
      Check (Status = Duplicates.Invalid_Operation_Order, "append after complete");
      Duplicates.Complete_Name (Index, Object, Status, Classification);
      Check (Status = Duplicates.Invalid_Operation_Order, "second complete");

      Duplicates.End_Object (Index, Object);
      Duplicates.Begin_Name (Index, Object, Status);
      Check (Status = Duplicates.Invalid_Operation_Order, "begin after object end");
      Duplicates.End_Object (Index, Object);
      Check (Duplicates.Stored_Name_Octets (Index) = 0, "idempotent end kept zero octets");
      Check (Duplicates.Stored_Leaves (Index) = 0, "idempotent end kept zero leaves");
      Check (Duplicates.Stored_Nodes (Index) = 0, "idempotent end kept zero nodes");
   end Check_Invalid_Order_And_Null_Arrays;

begin
   Check_Basic_Equality;
   Check_All_Orders;
   Check_Adversarial_Prefixes;
   Check_Length_Boundaries_Against_Oracle;
   Check_Randomized_Against_Oracle;
   Check_Capacity_Atomicity;
   Check_Nested_LIFO;
   Check_Invalid_Order_And_Null_Arrays;

   if Failures /= 0 then
      raise Program_Error with Natural'Image (Failures) & " duplicate-index test failures";
   end if;
end Flyology_JSON.Duplicate_Index_Tests;
