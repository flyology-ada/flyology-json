with Ada.Streams;

--  Bounded transactional collection of already selected token octets.

package Flyology_JSON.Tokens is
   type Token_Kind is (Decoded_Name, Decoded_String, Exact_Number);
   type Collector_State is (Empty, Collecting, Complete, Failed);
   type Collector_Status is
     (Operation_Accepted, Token_Completed, Invalid_Order, Storage_Exhausted);

   --  This is the exact stream-element array type, not a derived array type.
   --  A completed prefix can therefore be passed directly to another octet API
   --  without a conversion, hidden copy, or unchecked overlay.
   subtype Token_Storage is Ada.Streams.Stream_Element_Array;

   --  Storage is caller-owned, may have arbitrary bounds, and outlives Self.
   --  Self performs no allocation and retains no input passed to Append.
   type Collector (Storage : not null access Token_Storage) is limited private;

   --  Begin_Token succeeds only in Empty.  It enters Collecting with no
   --  published token.  Every other state returns Invalid_Order unchanged.
   procedure Begin_Token
     (Self : in out Collector; Kind : Token_Kind; Status : out Collector_Status);

   --  Append succeeds only in Collecting.  It copies all Value octets or none,
   --  accepts arbitrary array bounds, and treats an empty Value as a no-op.
   --  Value must not overlap Storage.  Capacity denial enters Failed and
   --  publishes no completed length.
   procedure Append
     (Self   : in out Collector;
      Value  : Ada.Streams.Stream_Element_Array;
      Status : out Collector_Status);

   --  Complete_Token succeeds only in Collecting and atomically publishes the
   --  staged prefix length, including zero.  Other states return Invalid_Order
   --  without changing state or publication.
   procedure Complete_Token (Self : in out Collector; Status : out Collector_Status);

   --  Abort_Token and Reset are nonraising, idempotent in every state, and
   --  return Self to Empty.  Retained storage octets become unspecified.
   procedure Abort_Token (Self : in out Collector);

   procedure Reset (Self : in out Collector);

   function State (Self : Collector) return Collector_State;

   function Kind (Self : Collector) return Token_Kind
   with Pre => State (Self) in Collecting | Complete;

   function Collected_Length (Self : Collector) return Ada.Streams.Stream_Element_Count
   with Pre => State (Self) = Complete;

   --  While Collecting or Failed, the bound storage is unpublished candidate
   --  state and the caller neither reads nor mutates it.  In Complete, the readable token
   --  is exactly Collected_Length components beginning at Storage'First.  The
   --  caller keeps that prefix unchanged until Reset or Abort_Token.  Bytes
   --  outside the completed prefix have no promised value.

private
   type Collector (Storage : not null access Token_Storage) is limited record
      Current_State : Collector_State := Empty;
      Current_Kind  : Token_Kind := Decoded_Name;
      Staged_Length : Ada.Streams.Stream_Element_Count := 0;
      Public_Length : Ada.Streams.Stream_Element_Count := 0;
   end record;
end Flyology_JSON.Tokens;
