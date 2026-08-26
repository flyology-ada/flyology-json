--  Independently versioned JSON syntax, Unicode, compatibility, duplicate,
--  root, and output identities for the trusted surface.

package Flyology_JSON.Profiles
  with Pure
is
   --  Version identifiers are values rather than suffixes in declaration
   --  names.  The initial implementation supports version 1 for each family;
   --  adding behavior under an existing family/version is incompatible.
   subtype Profile_Version is Positive;

   --  JSON grammar family selected by a parser or writer profile.
   --  @enum RFC_8259 Strict RFC 8259 JSON grammar.
   type Syntax_Family is (RFC_8259);

   --  Unicode validation family selected by a parser or writer profile.
   --  @enum Unicode_Scalars UTF-8 and escapes must decode to Unicode scalar values.
   type Unicode_Family is (Unicode_Scalars);

   --  Compatibility family that controls nonstandard JSON extensions.
   --  @enum No_Extensions Reject comments, trailing commas, and nonstandard token spellings.
   type Compatibility_Family is (No_Extensions);

   --  Policy for a UTF-8 byte-order mark at byte zero.
   --  @enum Reject_BOM Report a byte-order mark as malformed input.
   type BOM_Policy is (Reject_BOM);

   --  Object member-name handling selected when the parser package is instantiated.
   --  @enum Reject_Duplicates Reject equal decoded names without Unicode normalization.
   --  @enum Preserve_Unchecked Emit every name in source order without duplicate selection.
   type Duplicate_Policy is (Reject_Duplicates, Preserve_Unchecked);

   --  Root JSON value kinds admitted by a parser operation.
   --  @enum Accept_Any_Value Accept objects, arrays, strings, numbers, Booleans, and null.
   --  @enum Require_Object Accept only an object as the root value.
   type Top_Level_Policy is (Accept_Any_Value, Require_Object);

   --  Writer formatting policy.
   --  @enum Ordinary_Compact Emit no added whitespace while preserving caller order and number lexemes.
   type Output_Policy is (Ordinary_Compact);

   --  Versioned syntax identity frozen for one operation.
   --  @field Family Selected JSON grammar family.
   --  @field Version Version of the selected grammar family.
   type Versioned_Syntax is record
      Family  : Syntax_Family;
      Version : Profile_Version;
   end record;

   --  Versioned Unicode identity frozen for one operation.
   --  @field Family Selected Unicode validation family.
   --  @field Version Version of the selected Unicode family.
   type Versioned_Unicode is record
      Family  : Unicode_Family;
      Version : Profile_Version;
   end record;

   --  Versioned compatibility identity frozen for one parser operation.
   --  @field Family Selected extension-compatibility family.
   --  @field Version Version of the selected compatibility family.
   type Versioned_Compatibility is record
      Family  : Compatibility_Family;
      Version : Profile_Version;
   end record;

   --  Versioned output identity frozen for one writer operation.
   --  @field Policy Selected output policy.
   --  @field Version Version of the selected output policy.
   type Versioned_Output is record
      Policy  : Output_Policy;
      Version : Profile_Version;
   end record;

   --  Complete parser acceptance policy. Every field is explicit; no public default exists.
   --  @field Syntax Versioned JSON grammar identity.
   --  @field Unicode Versioned Unicode validation identity.
   --  @field Compatibility Versioned extension-compatibility identity.
   --  @field BOM Handling of a UTF-8 byte-order mark at byte zero.
   --  @field Duplicates Object member-name policy; it must match the parser generic instance.
   --  @field Top_Level Admitted root JSON value kinds.
   type Parser_Profile is record
      Syntax        : Versioned_Syntax;
      Unicode       : Versioned_Unicode;
      Compatibility : Versioned_Compatibility;
      BOM           : BOM_Policy;
      Duplicates    : Duplicate_Policy;
      Top_Level     : Top_Level_Policy;
   end record;

   --  Complete ordinary writer policy. Every field is explicit; no public default exists.
   --  @field Syntax Versioned JSON grammar identity.
   --  @field Unicode Versioned Unicode validation identity.
   --  @field Formatting Versioned output identity; ordinary compact output is not canonical JSON.
   type Writer_Profile is record
      Syntax     : Versioned_Syntax;
      Unicode    : Versioned_Unicode;
      Formatting : Versioned_Output;
   end record;

   --  There is deliberately no profile factory, default, capacity, or policy
   --  constant.  A caller constructs every field explicitly.  The trusted
   --  profiles contain no accounting capability or hook.
   --  @enum Profile_Supported Every profile field and combination is implemented.
   --  @enum Profile_Unsupported At least one requested family or version is not implemented.
   --  @enum Profile_Incompatible The requested profile fields cannot be combined.
   type Profile_Status is (Profile_Supported, Profile_Unsupported, Profile_Incompatible);

   --  Validate accepts only the declared initial family/version combinations.
   --  Parser/writer operations separately freeze a validated profile before
   --  consuming input or beginning a destination transaction.
   --  @param Profile Complete parser profile to validate without consuming input.
   --  @return Support status for the exact parser profile.
   function Validate (Profile : Parser_Profile) return Profile_Status;

   --  Validate a complete writer profile without beginning a destination transaction.
   --  @param Profile Complete writer profile to validate.
   --  @return Support status for the exact writer profile.
   function Validate (Profile : Writer_Profile) return Profile_Status;
end Flyology_JSON.Profiles;
