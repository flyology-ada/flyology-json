--  Independently versioned JSON syntax, Unicode, compatibility, duplicate,
--  root, and output identities for the trusted surface.

package Flyology_JSON.Profiles
  with Pure
is
   subtype Profile_Version is Positive;

   type Syntax_Family is (RFC_8259);
   type Unicode_Family is (Unicode_Scalars);
   type Compatibility_Family is (No_Extensions);
   type BOM_Policy is (Reject_BOM);
   type Duplicate_Policy is (Reject_Duplicates, Preserve_Unchecked);
   type Top_Level_Policy is (Accept_Any_Value, Require_Object);
   type Output_Policy is (Ordinary_Compact);

   type Versioned_Syntax is record
      Family  : Syntax_Family;
      Version : Profile_Version;
   end record;

   type Versioned_Unicode is record
      Family  : Unicode_Family;
      Version : Profile_Version;
   end record;

   type Versioned_Compatibility is record
      Family  : Compatibility_Family;
      Version : Profile_Version;
   end record;

   type Versioned_Output is record
      Policy  : Output_Policy;
      Version : Profile_Version;
   end record;

   type Parser_Profile is record
      Syntax        : Versioned_Syntax;
      Unicode       : Versioned_Unicode;
      Compatibility : Versioned_Compatibility;
      BOM           : BOM_Policy;
      Duplicates    : Duplicate_Policy;
      Top_Level     : Top_Level_Policy;
   end record;

   type Writer_Profile is record
      Syntax     : Versioned_Syntax;
      Unicode    : Versioned_Unicode;
      Formatting : Versioned_Output;
   end record;

   type Profile_Status is (Profile_Supported, Profile_Unsupported, Profile_Incompatible);

   function Validate (Profile : Parser_Profile) return Profile_Status;

   function Validate (Profile : Writer_Profile) return Profile_Status;
end Flyology_JSON.Profiles;
