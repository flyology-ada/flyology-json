--  Independently versioned JSON syntax, interoperability, and output policy.

package Flyology_JSON.Profiles
  with Pure
is
   type Syntax_Profile_Id is (RFC8259_Syntax_V1);
   type Unicode_Profile_Id is (Unicode_Scalars_V1);
   type Compatibility_Profile_Id is (No_Extensions_V1);
   type Writer_Profile_Id is (Ordinary_Compact_V1);

   type BOM_Profile_Id is (Reject_BOM_V1);
   type Duplicate_Name_Profile_Id is (Preserve_Unchecked_V1, Detect_And_Report_V1, Reject_Duplicate_V1);
   type Top_Level_Profile_Id is (Accept_Any_Value_V1, Require_Object_V1);

   type Parser_Profile is record
      Syntax        : Syntax_Profile_Id;
      Unicode       : Unicode_Profile_Id;
      Compatibility : Compatibility_Profile_Id;
      BOM           : BOM_Profile_Id;
      Duplicates    : Duplicate_Name_Profile_Id;
      Top_Level     : Top_Level_Profile_Id;
   end record;

   type Writer_Profile is record
      Syntax     : Syntax_Profile_Id;
      Unicode    : Unicode_Profile_Id;
      Formatting : Writer_Profile_Id;
   end record;

   type Profile_Status is (Profile_Supported, Profile_Unsupported, Profile_Incompatible);

   function Interoperable_RFC8259_V1 return Parser_Profile;

   function Compact_UTF8_V1 return Writer_Profile;

   function Validate (Profile : Parser_Profile) return Profile_Status;

   function Validate (Profile : Writer_Profile) return Profile_Status;
end Flyology_JSON.Profiles;
