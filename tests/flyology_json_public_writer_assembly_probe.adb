with Ada.Streams;
with Flyology_JSON.Destinations;
with Flyology_JSON.Errors;
with Flyology_JSON.Profiles;
with Flyology_JSON.Writing;
with Interfaces;

procedure Flyology_JSON_Public_Writer_Assembly_Probe is
   package Profiles renames Flyology_JSON.Profiles;

   use type Ada.Streams.Stream_Element_Count;
   use type Flyology_JSON.Errors.Error_Code;
   use type Interfaces.Unsigned_64;

   subtype Count is Ada.Streams.Stream_Element_Count;
   subtype Offset is Ada.Streams.Stream_Element_Offset;

   type Destination is limited record
      Checksum : Interfaces.Unsigned_64 := 0;
      Active   : Boolean := False;
   end record;

   procedure Begin_Transaction
     (Target : in out Destination;
      Status : out Flyology_JSON.Destinations.Begin_Status)
   is
   begin
      Target.Active := True;
      Status := Flyology_JSON.Destinations.Begin_Succeeded;
   end Begin_Transaction;

   procedure Write
     (Target  : in out Destination;
      Data    : Ada.Streams.Stream_Element_Array;
      Written : out Count;
      Status  : out Flyology_JSON.Destinations.Write_Status)
   is
   begin
      for Item of Data loop
         Target.Checksum := Target.Checksum + Interfaces.Unsigned_64 (Item) + 1;
      end loop;
      Written := Data'Length;
      Status := Flyology_JSON.Destinations.Write_Succeeded;
   end Write;

   procedure Commit
     (Target : in out Destination;
      Status : out Flyology_JSON.Destinations.Commit_Status)
   is
   begin
      Target.Active := False;
      Status := Flyology_JSON.Destinations.Commit_Succeeded;
   end Commit;

   procedure Abort_Transaction
     (Target : in out Destination;
      Status : out Flyology_JSON.Destinations.Abort_Status)
   is
   begin
      Target.Active := False;
      Status := Flyology_JSON.Destinations.Abort_Succeeded;
   end Abort_Transaction;

   package Writers is new Flyology_JSON.Writing
     (Destination_Type   => Destination,
      Destination_Begin  => Begin_Transaction,
      Destination_Write  => Write,
      Destination_Commit => Commit,
      Destination_Abort  => Abort_Transaction);

   Profile : constant Profiles.Writer_Profile :=
     (Syntax     => (Family => Profiles.RFC_8259, Version => 1),
      Unicode    => (Family => Profiles.Unicode_Scalars, Version => 1),
      Formatting => (Policy => Profiles.Ordinary_Compact, Version => 1));

   Target     : aliased Destination;
   Subject    : Writers.Writer (Target'Access, Maximum_Depth => 0);
   Diagnostic : Flyology_JSON.Errors.Diagnostic;

   procedure Probe_Fragment
     (Value      : Ada.Streams.Stream_Element_Array;
      Result     : out Flyology_JSON.Errors.Diagnostic)
   is
   begin
      Writers.Put_String_Fragment (Subject, Value, Result);
   end Probe_Fragment;

   pragma No_Inline (Probe_Fragment);

   Input : constant Ada.Streams.Stream_Element_Array :=
     [Offset (-9) => Character'Pos ('f'),
      -8          => Character'Pos ('l'),
      -7          => Character'Pos ('y'),
      -6          => Character'Pos ('o'),
      -5          => Character'Pos ('l'),
      -4          => Character'Pos ('o'),
      -3          => Character'Pos ('g'),
      -2          => Character'Pos ('y')];

begin
   Writers.Initialize (Subject, Profile, Diagnostic);
   Writers.Begin_Document (Subject, Diagnostic);
   Writers.Begin_String (Subject, Diagnostic);
   Probe_Fragment (Input, Diagnostic);
   if Diagnostic.Code /= Flyology_JSON.Errors.No_Error then
      raise Program_Error with "public writer assembly probe fragment failed";
   end if;
   Writers.End_String (Subject, Diagnostic);
   Writers.Finish_Document (Subject, Diagnostic);

   if Diagnostic.Code /= Flyology_JSON.Errors.No_Error
     or else Target.Active
     or else Target.Checksum = 0
   then
      raise Program_Error with "public writer assembly probe did not publish its result";
   end if;
end Flyology_JSON_Public_Writer_Assembly_Probe;
