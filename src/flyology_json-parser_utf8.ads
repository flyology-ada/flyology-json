with Ada.Streams;

--  Allocation-free incremental validation of RFC 3629 UTF-8 scalars.

private package Flyology_JSON.Parser_UTF8
  with Pure
is
   type Feed_Status is (Need_More, Scalar_Ready, Invalid);

   type Blame_Position is (Current_Octet, Stored_Lead_Octet);

   --  RFC 3629 limits a Unicode scalar encoding to at most four octets.
   type Scalar_Octets is array (Positive range 1 .. 4) of Ada.Streams.Stream_Element;

   subtype Scalar_Length is Positive range 1 .. Scalar_Octets'Length;

   type Scalar is record
      Length : Scalar_Length;
      --  Only Octets (1 .. Length) is part of the completed scalar value.
      Octets : Scalar_Octets;
   end record;

   type Feed_Result (Status : Feed_Status := Need_More) is record
      case Status is
         when Need_More =>
            null;
         when Scalar_Ready =>
            Value : Scalar;
         when Invalid =>
            Blame : Blame_Position;
      end case;
   end record;

   type Decoder is private;

   procedure Reset (Self : out Decoder);

   --  Feed exactly one octet. On Scalar_Ready or Invalid, Self is reset and
   --  ready for the lead octet of another scalar. Stored_Lead_Octet means that
   --  the complete prefix proves an overlong, surrogate, or out-of-range
   --  encoding; all other malformed octets blame Current_Octet.
   procedure Feed
     (Self   : in out Decoder;
      Octet  : Ada.Streams.Stream_Element;
      Result : out Feed_Result);

   function Has_Pending_Octets (Self : Decoder) return Boolean;

private
   subtype Buffered_Length is Natural range 0 .. Scalar_Octets'Length;

   type Decoder is record
      Octets          : Scalar_Octets := [others => 0];
      Length          : Buffered_Length := 0;
      Expected_Length : Buffered_Length := 0;
   end record;
end Flyology_JSON.Parser_UTF8;
