with Ada.Streams;
with Flyology_JSON.Errors;

--  JSON syntax events and count-based source fragment descriptions.

package Flyology_JSON.Events
  with Pure
is
   type Event_Kind is
     (Document_Begin,
      Document_End,
      Object_Begin,
      Object_End,
      Array_Begin,
      Array_End,
      Name_Begin,
      Name_Fragment,
      Name_End,
      String_Begin,
      String_Fragment,
      String_End,
      Number_Begin,
      Number_Fragment,
      Number_End,
      Null_Value,
      Boolean_Value);

   type Chunk_Range is record
      First_Count  : Ada.Streams.Stream_Element_Count;
      Octet_Length : Ada.Streams.Stream_Element_Count;
   end record;

   type Absolute_Range is record
      First        : Errors.Byte_Offset;
      Octet_Length : Errors.Byte_Offset;
   end record;

   --  Four octets are the maximum UTF-8 encoding of one Unicode scalar.
   type Scalar_Octets is array (Positive range 1 .. 4) of Ada.Streams.Stream_Element;

   type Decoded_Fragment_Kind is (No_Decoded_Fragment, Decoded_Is_Raw_Range, Decoded_Inline_Scalar);

   type Inline_Scalar is record
      Length : Natural range 0 .. 4;
      Octets : Scalar_Octets;
   end record;

   type Event is record
      Kind           : Event_Kind;
      Source_Start   : Errors.Byte_Offset;
      Source         : Absolute_Range;
      Has_Raw_Slice  : Boolean;
      Raw_Slice      : Chunk_Range;
      Decoded_Kind   : Decoded_Fragment_Kind;
      Decoded_Source : Absolute_Range;
      Decoded        : Inline_Scalar;
      Boolean_Data   : Boolean;
      Is_Duplicate   : Boolean;
   end record;
end Flyology_JSON.Events;
