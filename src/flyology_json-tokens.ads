with Ada.Streams;

--  Bounded transactional collection of already selected token octets.

package Flyology_JSON.Tokens is
   --  Collects one selected decoded string, decoded name, or exact number lexeme into
   --  bounded caller storage and publishes only a completed prefix.

   --  Semantic token category selected when collection begins.
   --  @enum Decoded_Name UTF-8 octets of a decoded object member name.
   --  @enum Decoded_String UTF-8 octets of a decoded JSON string value.
   --  @enum Exact_Number Exact source octets of a validated JSON number lexeme.
   type Token_Kind is (Decoded_Name, Decoded_String, Exact_Number);

   --  Lifecycle state of one bounded collector.
   --  @enum Empty No token is active or published.
   --  @enum Collecting A token is active, but its staged bytes are unpublished.
   --  @enum Complete One complete token prefix is published in caller storage.
   --  @enum Failed Storage denial ended collection without publishing a token.
   type Collector_State is (Empty, Collecting, Complete, Failed);

   --  Outcome of a state-changing collector operation.
   --  @enum Operation_Accepted The requested begin or append operation completed.
   --  @enum Token_Completed The staged token became the published completed prefix.
   --  @enum Invalid_Order The operation is not legal in the current collector state.
   --  @enum Storage_Exhausted The complete append would exceed caller storage.
   type Collector_Status is (Operation_Accepted, Token_Completed, Invalid_Order, Storage_Exhausted);

   --  This is the exact stream-element array type, not a derived array type.
   --  A completed prefix can therefore be passed directly to another octet API
   --  without a conversion, hidden copy, or unchecked overlay.
   subtype Token_Storage is Ada.Streams.Stream_Element_Array;

   --  Storage is caller-owned, may have arbitrary bounds, and outlives Self.
   --  Self performs no allocation and retains no input passed to Append.
   --  @field Storage Nonnull caller-owned array that stages and publishes the selected token.
   type Collector (Storage : not null access Token_Storage) is limited private;

   --  Begin_Token succeeds only in Empty.  It enters Collecting with no
   --  published token.  Every other state returns Invalid_Order unchanged.
   --  @param Self Collector whose lifecycle state is updated.
   --  @param Kind Semantic kind assigned to the new token.
   --  @param Status `Operation_Accepted` or `Invalid_Order`.
   procedure Begin_Token (Self : in out Collector; Kind : Token_Kind; Status : out Collector_Status);

   --  Append succeeds only in Collecting.  It copies all Value octets or none,
   --  accepts arbitrary array bounds, and treats an empty Value as a no-op.
   --  Value must not overlap Storage.  Capacity denial enters Failed and
   --  publishes no completed length.
   --  @param Self Collector that owns the unpublished staged prefix.
   --  @param Value Complete fragment to copy atomically; it may have arbitrary bounds.
   --  @param Status `Operation_Accepted`, `Invalid_Order`, or `Storage_Exhausted`.
   procedure Append
     (Self : in out Collector; Value : Ada.Streams.Stream_Element_Array; Status : out Collector_Status);

   --  Complete_Token succeeds only in Collecting and atomically publishes the
   --  staged prefix length, including zero.  Other states return Invalid_Order
   --  without changing state or publication.
   --  @param Self Collector whose staged prefix is published on success.
   --  @param Status `Token_Completed` or `Invalid_Order`.
   procedure Complete_Token (Self : in out Collector; Status : out Collector_Status);

   --  Discard staged or published token state and return `Self` to `Empty`.
   --  The operation is nonraising and idempotent in every state. Retained storage octets
   --  become unspecified.
   --  @param Self Collector to clear.
   procedure Abort_Token (Self : in out Collector);

   --  Prepare the collector for reuse. This has the same lifecycle and storage effects as
   --  `Abort_Token` and is nonraising and idempotent.
   --  @param Self Collector to reset to `Empty`.
   procedure Reset (Self : in out Collector);

   --  Report the current collector lifecycle state.
   --  @param Self Collector to inspect.
   --  @return Current state without changing storage or publication.
   function State (Self : Collector) return Collector_State;

   --  Report the semantic kind selected by `Begin_Token`.
   --  @param Self Active or completed collector to inspect.
   --  @return Selected token kind.
   function Kind (Self : Collector) return Token_Kind
   with Pre => State (Self) in Collecting | Complete;

   --  Report the length of the completed published prefix.
   --  @param Self Completed collector to inspect.
   --  @return Number of readable components beginning at `Storage'First`.
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
