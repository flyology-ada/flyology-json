with Ada.Streams;

--  Bounded transactional collection of already selected token octets.

package Flyology_JSON.Tokens is
   type Token_Kind is (Decoded_Name, Decoded_String, Exact_Number);
   type Collector_State is (Empty, Collecting, Complete, Failed);
   type Collector_Status is
     (Operation_Accepted, Token_Completed, Invalid_Order, Storage_Exhausted);

   subtype Token_Storage is Ada.Streams.Stream_Element_Array;

   type Collector (Storage : not null access Token_Storage) is limited private;

   procedure Begin_Token
     (Self : in out Collector; Kind : Token_Kind; Status : out Collector_Status);

   --  Value is copied atomically: either every octet is staged or none is.
   --  Input bounds are arbitrary and no input reference is retained.  Value
   --  must not overlap Storage; overlap is outside the collector contract.
   procedure Append
     (Self : in out Collector;
      Value : Ada.Streams.Stream_Element_Array;
      Status : out Collector_Status);

   --  Completion publishes Collected_Length.  Before this succeeds, caller
   --  storage is staging and must not be observed as a completed token.
   procedure Complete_Token (Self : in out Collector; Status : out Collector_Status);

   procedure Abort_Token (Self : in out Collector);

   procedure Reset (Self : in out Collector);

   function State (Self : Collector) return Collector_State;

   function Kind (Self : Collector) return Token_Kind
   with Pre => State (Self) in Collecting | Complete;

   function Collected_Length (Self : Collector) return Ada.Streams.Stream_Element_Count
   with Pre => State (Self) = Complete;

   --  Storage is unpublished and unobservable through the collector contract
   --  while State is Collecting or Failed.  In Complete, exactly the
   --  Collected_Length prefix beginning at Storage'First is readable.

private
   type Collector (Storage : not null access Token_Storage) is limited record
      Current_State : Collector_State := Empty;
      Current_Kind  : Token_Kind := Decoded_Name;
      Staged_Length : Ada.Streams.Stream_Element_Count := 0;
      Public_Length : Ada.Streams.Stream_Element_Count := 0;
   end record;
end Flyology_JSON.Tokens;
