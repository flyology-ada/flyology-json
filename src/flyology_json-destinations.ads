--  Operation-specific outcomes for transactional writer destinations.

package Flyology_JSON.Destinations
  with Pure
is
   --  These outcomes describe synchronous, nonraising operations on one
   --  whole-document transaction.  Begin_Failed owns no transaction;
   --  Commit_Failed publishes nothing; Abort always ends unpublished staging
   --  even when it reports Abort_Failed.
   type Begin_Status is (Begin_Succeeded, Begin_Failed);

   --  Write_Succeeded accepts the complete supplied array.  Write_Exhausted
   --  accepts exactly its longest prefix.  Write_Failed accepts none.  The
   --  corresponding Written value is a count independent of array bounds;
   --  empty data cannot report Write_Exhausted.
   type Write_Status is (Write_Succeeded, Write_Exhausted, Write_Failed);
   type Commit_Status is (Commit_Succeeded, Commit_Failed);
   type Abort_Status is (Abort_Succeeded, Abort_Failed);
end Flyology_JSON.Destinations;
