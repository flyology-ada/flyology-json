--  Complete transactional writer example with a bounded in-memory destination.
--  Writer calls describe JSON structure and decoded token fragments. The
--  destination keeps staged output separate from published output. It publishes
--  only when the writer validates a complete balanced document and requests
--  Commit.

with Ada.Streams;
with Ada.Text_IO;
with Flyology_JSON.Destinations;
with Flyology_JSON.Errors;
with Flyology_JSON.Profiles;
with Flyology_JSON.Writing;

procedure Transactional_Writer is
   package Destinations renames Flyology_JSON.Destinations;
   package Errors renames Flyology_JSON.Errors;
   package Profiles renames Flyology_JSON.Profiles;

   subtype Count is Ada.Streams.Stream_Element_Count;
   subtype Offset is Ada.Streams.Stream_Element_Offset;

   use type Ada.Streams.Stream_Element;
   use type Count;
   use type Errors.Error_Code;

   --  BEGIN destination-contract
   --  This capacity is an application choice for the example destination. It
   --  is not a Flyology JSON default. Production destinations can stage in a
   --  file, a message, a database transaction, or other caller-owned storage.
   Destination_Capacity : constant Count := 128;

   --  Staging and Published are deliberately separate. Observers can read only
   --  Published, so a malformed or incomplete document never leaks a prefix.
   type Buffer_Destination is limited record
      Staging          : Ada.Streams.Stream_Element_Array (-40 .. -40 + Offset (Destination_Capacity) - 1);
      Published        : Ada.Streams.Stream_Element_Array (90 .. 90 + Offset (Destination_Capacity) - 1);
      Staged_Length    : Count := 0;
      Published_Length : Count := 0;
      Active           : Boolean := False;
   end record;

   procedure Begin_Transaction (Target : in out Buffer_Destination; Status : out Destinations.Begin_Status) is
   begin
      --  Begin owns a fresh unpublished transaction and clears old staging.
      Target.Staged_Length := 0;
      Target.Active := True;
      Status := Destinations.Begin_Succeeded;
   end Begin_Transaction;

   procedure Write_Staged
     (Target  : in out Buffer_Destination;
      Data    : Ada.Streams.Stream_Element_Array;
      Written : out Count;
      Status  : out Destinations.Write_Status)
   is
      Available : constant Count := Destination_Capacity - Target.Staged_Length;
   begin
      --  A destination may accept all Data or its exact longest available
      --  prefix. Written is a count, so arbitrary Data bounds remain valid.
      Written := Count'Min (Available, Data'Length);
      if Written > 0 then
         for Position in Count range 0 .. Written - 1 loop
            Target.Staging (Target.Staging'First + Offset (Target.Staged_Length + Position)) :=
              Data (Data'First + Offset (Position));
         end loop;
      end if;
      Target.Staged_Length := Target.Staged_Length + Written;
      Status :=
        (if Written = Data'Length then Destinations.Write_Succeeded else Destinations.Write_Exhausted);
   end Write_Staged;

   procedure Commit_Transaction (Target : in out Buffer_Destination; Status : out Destinations.Commit_Status)
   is
   begin
      --  Commit is the only publication point. This simple array copy models
      --  publication at commit time; a real destination supplies its own
      --  transaction mechanism.
      if Target.Staged_Length > 0 then
         for Position in Count range 0 .. Target.Staged_Length - 1 loop
            Target.Published (Target.Published'First + Offset (Position)) :=
              Target.Staging (Target.Staging'First + Offset (Position));
         end loop;
      end if;
      Target.Published_Length := Target.Staged_Length;
      Target.Active := False;
      Status := Destinations.Commit_Succeeded;
   end Commit_Transaction;

   procedure Abort_Transaction (Target : in out Buffer_Destination; Status : out Destinations.Abort_Status) is
   begin
      --  Abort discards unpublished staging. It never changes Published.
      Target.Staged_Length := 0;
      Target.Active := False;
      Status := Destinations.Abort_Succeeded;
   end Abort_Transaction;

   package Writing is new
     Flyology_JSON.Writing
       (Destination_Type   => Buffer_Destination,
        Destination_Begin  => Begin_Transaction,
        Destination_Write  => Write_Staged,
        Destination_Commit => Commit_Transaction,
        Destination_Abort  => Abort_Transaction);
   --  The generic binds destination mechanism once. JSON grammar and escaping
   --  remain inside Flyology JSON; publication ownership remains here.
   --  END destination-contract

   function To_Octets (Text : String; First : Offset) return Ada.Streams.Stream_Element_Array is
      Result : Ada.Streams.Stream_Element_Array (First .. First + Offset (Text'Length) - 1);
   begin
      for Position in Text'Range loop
         Result (First + Offset (Position - Text'First)) := Character'Pos (Text (Position));
      end loop;
      return Result;
   end To_Octets;

   procedure Require_Success (Diagnostic : Errors.Diagnostic; Operation : String) is
   begin
      if Diagnostic.Code /= Errors.No_Error then
         raise Program_Error with Operation & " failed: " & Errors.Error_Code'Image (Diagnostic.Code);
      end if;
   end Require_Success;

   Profile : constant Profiles.Writer_Profile :=
     (Syntax     => (Family => Profiles.RFC_8259, Version => 1),
      Unicode    => (Family => Profiles.Unicode_Scalars, Version => 1),
      Formatting => (Policy => Profiles.Ordinary_Compact, Version => 1));

   Target : aliased Buffer_Destination;

   --  Maximum_Depth is another application choice. The single root object
   --  needs depth one.
   Writer     : Writing.Writer (Target'Access, Maximum_Depth => 1);
   Diagnostic : Errors.Diagnostic;
   Name       : constant Ada.Streams.Stream_Element_Array := To_Octets ("message", -12);
   Value      : constant Ada.Streams.Stream_Element_Array := To_Octets ("Hello, Ada!", 30);
   Expected   : constant Ada.Streams.Stream_Element_Array :=
     To_Octets ("{""message"":""Hello, Ada!""}", -100);
begin
   --  BEGIN writer-calls
   --  Initialize validates and freezes Ordinary_Compact before Begin can ask
   --  the destination to own a transaction.
   Writing.Initialize (Writer, Profile, Diagnostic);
   Require_Success (Diagnostic, "Initialize");

   Writing.Begin_Document (Writer, Diagnostic);
   Require_Success (Diagnostic, "Begin_Document");

   --  Semantic calls mirror the JSON grammar. The writer adds punctuation,
   --  validates UTF-8, and escapes decoded name and string fragments.
   Writing.Begin_Object (Writer, Diagnostic);
   Require_Success (Diagnostic, "Begin_Object");
   Writing.Begin_Name (Writer, Diagnostic);
   Require_Success (Diagnostic, "Begin_Name");
   Writing.Put_Name_Fragment (Writer, Name, Diagnostic);
   Require_Success (Diagnostic, "Put_Name_Fragment");
   Writing.End_Name (Writer, Diagnostic);
   Require_Success (Diagnostic, "End_Name");
   Writing.Begin_String (Writer, Diagnostic);
   Require_Success (Diagnostic, "Begin_String");
   Writing.Put_String_Fragment (Writer, Value, Diagnostic);
   Require_Success (Diagnostic, "Put_String_Fragment");
   Writing.End_String (Writer, Diagnostic);
   Require_Success (Diagnostic, "End_String");
   Writing.End_Object (Writer, Diagnostic);
   Require_Success (Diagnostic, "End_Object");

   --  The complete candidate is still unpublished at this point.
   if Target.Published_Length /= 0 then
      raise Program_Error with "the destination published before commit";
   end if;

   --  Finish validates the balanced root and invokes Commit. A failed commit
   --  would publish nothing and retain the primary diagnostic for cleanup.
   Writing.Finish_Document (Writer, Diagnostic);
   Require_Success (Diagnostic, "Finish_Document");
   --  END writer-calls

   if Target.Published_Length /= Expected'Length then
      raise Program_Error with "the published output has the wrong length";
   end if;
   for Position in Count range 0 .. Target.Published_Length - 1 loop
      if Target.Published (Target.Published'First + Offset (Position))
        /= Expected (Expected'First + Offset (Position))
      then
         raise Program_Error with "the published output differs";
      end if;
   end loop;

   --  Ordinary_Compact preserves caller order. It is not canonical JSON.
   for Position in Count range 0 .. Target.Published_Length - 1 loop
      Ada.Text_IO.Put (Character'Val (Target.Published (Target.Published'First + Offset (Position))));
   end loop;
   Ada.Text_IO.New_Line;
end Transactional_Writer;
