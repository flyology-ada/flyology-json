--  Operation-specific outcomes for transactional writer destinations.

package Flyology_JSON.Destinations
  with Pure
is
   --  Defines synchronous, nonraising result values for one unpublished
   --  whole-document destination transaction.

   --  These outcomes describe synchronous, nonraising operations on one
   --  whole-document transaction.  Begin_Failed owns no transaction;
   --  Commit_Failed publishes nothing; Abort always ends unpublished staging
   --  even when it reports Abort_Failed.
   --  @enum Begin_Succeeded The destination started one unpublished transaction.
   --  @enum Begin_Failed The destination started no transaction.
   type Begin_Status is (Begin_Succeeded, Begin_Failed);

   --  Write_Succeeded accepts the complete supplied array.  Write_Exhausted
   --  accepts exactly its longest prefix.  Write_Failed accepts none.  The
   --  corresponding Written value is a count independent of array bounds;
   --  empty data cannot report Write_Exhausted.
   --  @enum Write_Succeeded The destination accepted every supplied octet.
   --  @enum Write_Exhausted The destination accepted exactly its longest available prefix.
   --  @enum Write_Failed The destination accepted no supplied octets.
   type Write_Status is (Write_Succeeded, Write_Exhausted, Write_Failed);

   --  Result of the whole-document publication request.
   --  @enum Commit_Succeeded The complete staged document was published.
   --  @enum Commit_Failed No staged octet was published; the transaction remains abortable.
   type Commit_Status is (Commit_Succeeded, Commit_Failed);

   --  Result of ending an unpublished transaction.
   --  @enum Abort_Succeeded The destination ended the unpublished transaction normally.
   --  @enum Abort_Failed Cleanup reported a failure, but the unpublished transaction still ended.
   type Abort_Status is (Abort_Succeeded, Abort_Failed);
end Flyology_JSON.Destinations;
