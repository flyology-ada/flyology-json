package body Flyology_JSON.Parser_Duplicates is

   use type Ada.Streams.Stream_Element_Count;
   use type Ada.Streams.Stream_Element;
   use type Interfaces.Unsigned_64;

   subtype Octet is Ada.Streams.Stream_Element;
   subtype Bit_Position is Interfaces.Unsigned_64;

   --  The virtual key's eight length octets are the architecture's fixed
   --  unsigned-64 length prefix, not an operational storage capacity.
   Length_Prefix_Octets : constant := 8;
   Bits_Per_Octet       : constant := 8;

   function Candidate_Length (Self : Index) return Natural is
     (Self.Name_Octets_Used - Self.Candidate_Start);

   function Length_Octet (Length : Natural; Position : Natural) return Octet is
      Shift : constant Natural := (Length_Prefix_Octets - 1 - Position) * Bits_Per_Octet;
   begin
      return Octet (Interfaces.Shift_Right (Interfaces.Unsigned_64 (Length), Shift) and 16#FF#);
   end Length_Octet;

   function Key_Octet
     (Self     : Index;
      Offset   : Natural;
      Length   : Natural;
      Position : Natural) return Octet is
   begin
      if Position < Length_Prefix_Octets then
         return Length_Octet (Length, Position);
      elsif Position - Length_Prefix_Octets >= Length then
         --  Crit-bit descent can ask for a node bit beyond a shorter key's
         --  finite content before reaching the leaf used for exact comparison.
         --  Zero extension makes that branch query total; the earlier length
         --  prefix still supplies the first semantic difference.
         return 0;
      else
         return Self.Name_Octets (Offset + Position - Length_Prefix_Octets + 1);
      end if;
   end Key_Octet;

   function Key_Bit
     (Self     : Index;
      Offset   : Natural;
      Length   : Natural;
      Position : Bit_Position) return Boolean is
      Octet_Position : constant Natural := Natural (Position / Bits_Per_Octet);
      Within_Octet   : constant Natural := Natural (Position mod Bits_Per_Octet);
      Mask           : constant Octet := 2**(Bits_Per_Octet - 1 - Within_Octet);
   begin
      return (Key_Octet (Self, Offset, Length, Octet_Position) and Mask) /= 0;
   end Key_Bit;

   function Child
     (Self      : Index;
      Node      : Crit_Bit_Node;
      Key_Offset : Natural;
      Key_Length : Natural) return Entry_Reference is
   begin
      if Key_Bit (Self, Key_Offset, Key_Length, Node.Critical_Bit) then
         return Node.Child_One;
      else
         return Node.Child_Zero;
      end if;
   end Child;

   function First_Differing_Bit
     (Self       : Index;
      Left_Offset : Natural;
      Left_Length : Natural;
      Right_Offset : Natural;
      Right_Length : Natural;
      Found       : out Boolean) return Bit_Position is
      Left_Value  : Octet;
      Right_Value : Octet;
   begin
      for Position in 0 .. Length_Prefix_Octets - 1 loop
         Left_Value := Key_Octet (Self, Left_Offset, Left_Length, Position);
         Right_Value := Key_Octet (Self, Right_Offset, Right_Length, Position);
         if Left_Value /= Right_Value then
            for Bit in 0 .. Bits_Per_Octet - 1 loop
               if (Left_Value and 2**(Bits_Per_Octet - 1 - Bit))
                 /= (Right_Value and 2**(Bits_Per_Octet - 1 - Bit))
               then
                  Found := True;
                  return Bit_Position (Position * Bits_Per_Octet + Bit);
               end if;
            end loop;
         end if;
      end loop;

      --  Equal length prefixes make the content loop bounds identical.
      if Left_Length > 0 then
         for Position in 0 .. Left_Length - 1 loop
            Left_Value := Self.Name_Octets (Left_Offset + Position + 1);
            Right_Value := Self.Name_Octets (Right_Offset + Position + 1);
            if Left_Value /= Right_Value then
               for Bit in 0 .. Bits_Per_Octet - 1 loop
                  if (Left_Value and 2**(Bits_Per_Octet - 1 - Bit))
                    /= (Right_Value and 2**(Bits_Per_Octet - 1 - Bit))
                  then
                     Found := True;
                     return
                       Bit_Position (Length_Prefix_Octets) * Bits_Per_Octet
                       + Bit_Position (Position) * Bits_Per_Octet
                       + Bit_Position (Bit);
                  end if;
               end loop;
            end if;
         end loop;
      end if;

      Found := False;
      return 0;
   end First_Differing_Bit;

   procedure Reset (Self : in out Index) is
   begin
      Self.Name_Octets_Used := 0;
      Self.Leaves_Used := 0;
      Self.Nodes_Used := 0;
      Self.Candidate_Start := 0;
      Self.Candidate_Active := False;
   end Reset;

   procedure Begin_Object (Self : Index; Context : out Object_Context) is
   begin
      Context :=
        (Name_Octet_Mark => Self.Name_Octets_Used,
         Leaf_Mark       => Self.Leaves_Used,
         Node_Mark       => Self.Nodes_Used,
         Root            => (Kind => No_Entry, Index => 0),
         Active          => True);
   end Begin_Object;

   procedure End_Object (Self : in out Index; Context : in out Object_Context) is
   begin
      if Context.Active then
         Self.Name_Octets_Used := Context.Name_Octet_Mark;
         Self.Leaves_Used := Context.Leaf_Mark;
         Self.Nodes_Used := Context.Node_Mark;
         Self.Candidate_Start := Self.Name_Octets_Used;
         Self.Candidate_Active := False;
         Context.Active := False;
         Context.Root := (Kind => No_Entry, Index => 0);
      end if;
   end End_Object;

   procedure Begin_Name
     (Self    : in out Index;
      Context : Object_Context;
      Status  : out Operation_Status) is
   begin
      if not Context.Active or else Self.Candidate_Active then
         Status := Invalid_Operation_Order;
      elsif Self.Name_Capacity = 0 then
         Status := Index_Storage_Exhausted;
      else
         Self.Candidate_Start := Self.Name_Octets_Used;
         Self.Candidate_Active := True;
         Status := Operation_Succeeded;
      end if;
   end Begin_Name;

   procedure Append_Octets
     (Self   : in out Index;
      Octets : Ada.Streams.Stream_Element_Array;
      Status : out Operation_Status) is
   begin
      if not Self.Candidate_Active then
         Status := Invalid_Operation_Order;
      elsif Octets'Length = 0 then
         Status := Operation_Succeeded;
      elsif Octets'Length
        > Ada.Streams.Stream_Element_Count (Self.Name_Octet_Capacity - Self.Name_Octets_Used)
      then
         Status := Name_Storage_Exhausted;
      else
         for Position in Ada.Streams.Stream_Element_Count range 0 .. Octets'Length - 1 loop
            Self.Name_Octets (Self.Name_Octets_Used + Natural (Position) + 1) :=
              Octets (Octets'First + Ada.Streams.Stream_Element_Offset (Position));
         end loop;
         Self.Name_Octets_Used := Self.Name_Octets_Used + Natural (Octets'Length);
         Status := Operation_Succeeded;
      end if;
   end Append_Octets;

   procedure Complete_Name
     (Self           : in out Index;
      Context        : in out Object_Context;
      Status         : out Operation_Status;
      Classification : out Name_Classification) is
      Candidate_Length_Value : Natural;
      Cursor                 : Entry_Reference;
      Parent                 : Entry_Reference := (Kind => No_Entry, Index => 0);
      Parent_Bit             : Boolean := False;
      Existing               : Name_Leaf;
      Difference_Found       : Boolean;
      Difference             : Bit_Position;
      New_Leaf               : Entry_Reference;
      New_Node               : Entry_Reference;
   begin
      Classification := Unique_Name;
      if not Context.Active or else not Self.Candidate_Active then
         Status := Invalid_Operation_Order;
         return;
      end if;

      Candidate_Length_Value := Candidate_Length (Self);

      if Context.Root.Kind = No_Entry then
         if Self.Leaves_Used = Self.Name_Capacity then
            Status := Index_Storage_Exhausted;
            return;
         end if;

         Self.Leaves_Used := Self.Leaves_Used + 1;
         Self.Leaves (Self.Leaves_Used) :=
           (Offset => Self.Candidate_Start, Length => Candidate_Length_Value);
         Context.Root := (Kind => Leaf_Entry, Index => Self.Leaves_Used);
         Self.Candidate_Active := False;
         Status := Operation_Succeeded;
         return;
      end if;

      Cursor := Context.Root;
      while Cursor.Kind = Node_Entry loop
         Cursor :=
           Child
             (Self,
              Self.Nodes (Cursor.Index),
              Self.Candidate_Start,
              Candidate_Length_Value);
      end loop;

      Existing := Self.Leaves (Cursor.Index);
      Difference :=
        First_Differing_Bit
          (Self,
           Self.Candidate_Start,
           Candidate_Length_Value,
           Existing.Offset,
           Existing.Length,
           Difference_Found);

      if not Difference_Found then
         Self.Name_Octets_Used := Self.Candidate_Start;
         Self.Candidate_Active := False;
         Classification := Duplicate_Name;
         Status := Operation_Succeeded;
         return;
      end if;

      if Self.Leaves_Used = Self.Name_Capacity or else Self.Nodes_Used = Self.Name_Capacity then
         Status := Index_Storage_Exhausted;
         return;
      end if;

      Cursor := Context.Root;
      while Cursor.Kind = Node_Entry and then Self.Nodes (Cursor.Index).Critical_Bit < Difference loop
         Parent := Cursor;
         Parent_Bit :=
           Key_Bit
             (Self,
              Self.Candidate_Start,
              Candidate_Length_Value,
              Self.Nodes (Cursor.Index).Critical_Bit);
         Cursor :=
           Child
             (Self,
              Self.Nodes (Cursor.Index),
              Self.Candidate_Start,
              Candidate_Length_Value);
      end loop;

      New_Leaf := (Kind => Leaf_Entry, Index => Self.Leaves_Used + 1);
      New_Node := (Kind => Node_Entry, Index => Self.Nodes_Used + 1);
      Self.Leaves (New_Leaf.Index) :=
        (Offset => Self.Candidate_Start, Length => Candidate_Length_Value);
      Self.Nodes (New_Node.Index).Critical_Bit := Difference;
      if Key_Bit (Self, Self.Candidate_Start, Candidate_Length_Value, Difference) then
         Self.Nodes (New_Node.Index).Child_Zero := Cursor;
         Self.Nodes (New_Node.Index).Child_One := New_Leaf;
      else
         Self.Nodes (New_Node.Index).Child_Zero := New_Leaf;
         Self.Nodes (New_Node.Index).Child_One := Cursor;
      end if;

      Self.Leaves_Used := New_Leaf.Index;
      Self.Nodes_Used := New_Node.Index;
      if Parent.Kind = No_Entry then
         Context.Root := New_Node;
      elsif Parent_Bit then
         Self.Nodes (Parent.Index).Child_One := New_Node;
      else
         Self.Nodes (Parent.Index).Child_Zero := New_Node;
      end if;
      Self.Candidate_Active := False;
      Status := Operation_Succeeded;
   end Complete_Name;

   function Stored_Name_Octets (Self : Index) return Natural is (Self.Name_Octets_Used);

   function Available_Name_Octets (Self : Index) return Natural is
     (Self.Name_Octet_Capacity - Self.Name_Octets_Used);

   function Stored_Leaves (Self : Index) return Natural is (Self.Leaves_Used);

   function Stored_Nodes (Self : Index) return Natural is (Self.Nodes_Used);

end Flyology_JSON.Parser_Duplicates;
