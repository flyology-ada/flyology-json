package body Flyology_JSON.Profiles is

   function Validate (Profile : Parser_Profile) return Profile_Status is
   begin
      if Profile.Syntax.Version /= 1
        or else Profile.Unicode.Version /= 1
        or else Profile.Compatibility.Version /= 1
      then
         return Profile_Unsupported;
      end if;

      return Profile_Supported;
   end Validate;

   function Validate (Profile : Writer_Profile) return Profile_Status is
   begin
      if Profile.Syntax.Version /= 1
        or else Profile.Unicode.Version /= 1
        or else Profile.Formatting.Version /= 1
      then
         return Profile_Unsupported;
      end if;

      return Profile_Supported;
   end Validate;

end Flyology_JSON.Profiles;
