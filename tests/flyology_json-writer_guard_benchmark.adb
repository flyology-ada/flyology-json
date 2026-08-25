with Ada.Real_Time;
with Ada.Streams;
with Ada.Text_IO;
with Flyology_JSON.Destinations;
with Flyology_JSON.Errors;
with Flyology_JSON.Writer_Core;

procedure Flyology_JSON.Writer_Guard_Benchmark is

   package Core renames Flyology_JSON.Writer_Core;
   package Destinations renames Flyology_JSON.Destinations;
   package Errors renames Flyology_JSON.Errors;

   use type Ada.Real_Time.Time;
   use type Errors.Error_Code;

   type Sink is limited record
      Octets : Long_Long_Integer := 0;
      Active : Boolean := False;
   end record;

   procedure Sink_Begin
     (Target : in out Sink; Status : out Destinations.Begin_Status)
   is
   begin
      Target.Active := True;
      Status := Destinations.Begin_Succeeded;
   end Sink_Begin;

   procedure Sink_Write
     (Target  : in out Sink;
      Data    : Ada.Streams.Stream_Element_Array;
      Written : out Ada.Streams.Stream_Element_Count;
      Status  : out Destinations.Write_Status)
   is
   begin
      Target.Octets := Target.Octets + Long_Long_Integer (Data'Length);
      Written := Data'Length;
      Status := Destinations.Write_Succeeded;
   end Sink_Write;

   procedure Sink_Commit
     (Target : in out Sink; Status : out Destinations.Commit_Status)
   is
   begin
      Target.Active := False;
      Status := Destinations.Commit_Succeeded;
   end Sink_Commit;

   procedure Sink_Abort
     (Target : in out Sink; Status : out Destinations.Abort_Status)
   is
   begin
      Target.Active := False;
      Status := Destinations.Abort_Succeeded;
   end Sink_Abort;

   package Writers is new Core.Destination_Writers
     (Destination_Type   => Sink,
      Destination_Begin  => Sink_Begin,
      Destination_Write  => Sink_Write,
      Destination_Commit => Sink_Commit,
      Destination_Abort  => Sink_Abort);

   --  Benchmark fixture sizes select measurement resolution, not writer policy.
   Large_Octets : constant := 1_048_576;
   Large_Calls  : constant := 64;
   Small_Calls  : constant := 10_000;
   Samples      : constant := 5;

   Large_Fragment : constant Ada.Streams.Stream_Element_Array (1 .. Large_Octets) :=
     [others => Character'Pos ('a')];
   Small_Fragment : constant Ada.Streams.Stream_Element_Array (1 .. 1) :=
     [1 => Character'Pos ('a')];

   procedure Run
     (Label    : String;
      Guarded  : Boolean;
      Fragment : Ada.Streams.Stream_Element_Array;
      Calls    : Positive)
   is
      Target     : aliased Sink;
      Writer     : Writers.Writer (Target'Access, Maximum_Depth => 0);
      Diagnostic : Errors.Diagnostic;
      Started    : Ada.Real_Time.Time;
      Finished   : Ada.Real_Time.Time;
      Seconds    : Long_Float;
      Bytes      : Long_Float;
      GB_Per_S   : Long_Float;
      NS_Per_Call : Long_Float;
   begin
      Writers.Initialize (Writer, Diagnostic);
      Writers.Begin_Document (Writer, Diagnostic);
      Writers.Begin_String (Writer, Diagnostic);
      if Diagnostic.Code /= Errors.No_Error then
         raise Program_Error with "benchmark setup failed";
      end if;

      Started := Ada.Real_Time.Clock;
      for Call in 1 .. Calls loop
         if Guarded then
            Writers.Put_String_Fragment (Writer, Fragment, Diagnostic);
         else
            Writers.Put_String_Fragment_Unguarded_For_Test
              (Writer, Fragment, Diagnostic);
         end if;
      end loop;
      Finished := Ada.Real_Time.Clock;

      if Diagnostic.Code /= Errors.No_Error then
         raise Program_Error with "benchmark fragment call failed";
      end if;

      Seconds := Long_Float (Ada.Real_Time.To_Duration (Finished - Started));
      Bytes := Long_Float (Fragment'Length) * Long_Float (Calls);
      GB_Per_S := Bytes / Seconds / 1_000_000_000.0;
      NS_Per_Call := Seconds * 1_000_000_000.0 / Long_Float (Calls);
      Ada.Text_IO.Put_Line
        (Label
         & " GB/s=" & Long_Float'Image (GB_Per_S)
         & " ns/call=" & Long_Float'Image (NS_Per_Call));

      Writers.Abort_Document (Writer, Diagnostic);
   end Run;

begin
   for Sample in 1 .. Samples loop
      if Sample mod 2 = 1 then
         Run ("large baseline", False, Large_Fragment, Large_Calls);
         Run ("large guarded ", True, Large_Fragment, Large_Calls);
         Run ("small baseline", False, Small_Fragment, Small_Calls);
         Run ("small guarded ", True, Small_Fragment, Small_Calls);
      else
         Run ("large guarded ", True, Large_Fragment, Large_Calls);
         Run ("large baseline", False, Large_Fragment, Large_Calls);
         Run ("small guarded ", True, Small_Fragment, Small_Calls);
         Run ("small baseline", False, Small_Fragment, Small_Calls);
      end if;
   end loop;
end Flyology_JSON.Writer_Guard_Benchmark;
