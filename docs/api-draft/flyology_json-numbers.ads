--  Checked JSON numeric conversion and deterministic rendering.

package Flyology_JSON.Numbers
  with Pure
is
   --  Rendered publishes exactly the Produced-component prefix beginning at
   --  Output'First and leaves the suffix unchanged.  Every failure publishes
   --  Produced = 0 and leaves all of Output unchanged.
   type Render_Status is (Rendered, Output_Too_Small, Unsupported_Value);
end Flyology_JSON.Numbers;
