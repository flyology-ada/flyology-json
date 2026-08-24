with Ada.Streams;
with Interfaces;

--  Caller-backed exact decoded-name storage and crit-bit duplicate index.
--  This private mechanism assumes its caller supplies already validated,
--  canonical UTF-8 scalar octets.  It performs no Unicode normalization.
private package Flyology_JSON.Parser_Duplicates is

   type Operation_Status is
     (Operation_Succeeded,
      Name_Storage_Exhausted,
      Index_Storage_Exhausted,
      Invalid_Operation_Order);

   type Name_Classification is (Unique_Name, Duplicate_Name);

   type Object_Context is private;

   type Index
     (Name_Octet_Capacity : Natural;
      Name_Capacity       : Natural)
   is limited private;

   procedure Reset (Self : in out Index);

   procedure Begin_Object (Self : Index; Context : out Object_Context);

   --  Restore all name, leaf, and node storage acquired since Begin_Object.
   --  Parser nesting guarantees LIFO order.
   procedure End_Object (Self : in out Index; Context : in out Object_Context);

   --  Begin one candidate name in Context.  A zero Name_Capacity is rejected
   --  here so an empty name cannot reach its closing quote without a leaf.
   procedure Begin_Name
     (Self    : in out Index;
      Context : Object_Context;
      Status  : out Operation_Status);

   --  Append already validated decoded UTF-8 octets.  The operation is atomic:
   --  either every supplied octet is retained or none is.
   procedure Append_Octets
     (Self   : in out Index;
      Octets : Ada.Streams.Stream_Element_Array;
      Status : out Operation_Status);

   --  Compare the candidate exactly, reclaim it when duplicate, or add one
   --  leaf and (except for an empty tree) one node after all capacity checks.
   procedure Complete_Name
     (Self           : in out Index;
      Context        : in out Object_Context;
      Status         : out Operation_Status;
      Classification : out Name_Classification);

   function Stored_Name_Octets (Self : Index) return Natural;

   function Available_Name_Octets (Self : Index) return Natural;

   function Stored_Leaves (Self : Index) return Natural;

   function Stored_Nodes (Self : Index) return Natural;

private

   type Entry_Kind is (No_Entry, Leaf_Entry, Node_Entry);

   type Entry_Reference is record
      Kind  : Entry_Kind := No_Entry;
      Index : Natural := 0;
   end record;

   type Name_Leaf is record
      Offset : Natural := 0;
      Length : Natural := 0;
   end record;

   type Crit_Bit_Node is record
      Critical_Bit : Interfaces.Unsigned_64 := 0;
      Child_Zero   : Entry_Reference;
      Child_One    : Entry_Reference;
   end record;

   type Name_Octet_Array is array (Positive range <>) of Ada.Streams.Stream_Element;
   type Leaf_Array is array (Positive range <>) of Name_Leaf;
   type Node_Array is array (Positive range <>) of Crit_Bit_Node;

   type Object_Context is record
      Name_Octet_Mark : Natural := 0;
      Leaf_Mark       : Natural := 0;
      Node_Mark       : Natural := 0;
      Root            : Entry_Reference;
      Active          : Boolean := False;
   end record;

   type Index
     (Name_Octet_Capacity : Natural;
      Name_Capacity       : Natural)
   is limited record
      Name_Octets      : Name_Octet_Array (1 .. Name_Octet_Capacity);
      Leaves           : Leaf_Array (1 .. Name_Capacity);
      Nodes            : Node_Array (1 .. Name_Capacity);
      Name_Octets_Used : Natural := 0;
      Leaves_Used      : Natural := 0;
      Nodes_Used       : Natural := 0;
      Candidate_Start  : Natural := 0;
      Candidate_Active : Boolean := False;
   end record;

end Flyology_JSON.Parser_Duplicates;
