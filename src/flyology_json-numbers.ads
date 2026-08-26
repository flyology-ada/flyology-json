--  Checked JSON numeric conversion and deterministic rendering.

package Flyology_JSON.Numbers
  with Pure
is
   --  Defines shared outcomes for checked numeric rendering operations.

   --  Rendered publishes exactly the Produced-component prefix beginning at
   --  Output'First and leaves the suffix unchanged.  Every failure publishes
   --  Produced = 0 and leaves the complete Output array unchanged.
   --  @enum Rendered The requested numeric value was written completely.
   --  @enum Output_Too_Small Caller storage cannot hold the complete spelling.
   --  @enum Unsupported_Value The requested numeric category has no JSON spelling in this operation.
   type Render_Status is (Rendered, Output_Too_Small, Unsupported_Value);
end Flyology_JSON.Numbers;
