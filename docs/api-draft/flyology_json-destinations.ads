--  Operation-specific outcomes for transactional writer destinations.

package Flyology_JSON.Destinations
  with Pure
is
   type Begin_Status is (Begin_Succeeded, Begin_Failed);
   type Write_Status is (Write_Succeeded, Write_Exhausted, Write_Failed);
   type Commit_Status is (Commit_Succeeded, Commit_Failed);
   type Abort_Status is (Abort_Succeeded, Abort_Failed);
end Flyology_JSON.Destinations;
