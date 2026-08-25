package body Flyology_JSON.Errors is

   procedure Clear (Item : out Diagnostic) is
   begin
      Item :=
        (Code                 => No_Error,
         Coordinate           => No_Coordinate,
         Offset               => 0,
         Secondary            => No_Error,
         Secondary_Coordinate => No_Coordinate,
         Secondary_Offset     => 0);
   end Clear;

end Flyology_JSON.Errors;
