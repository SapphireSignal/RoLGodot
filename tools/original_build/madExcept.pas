unit madExcept;

// Build stub for the commercial madExcept library (not installed): the reference build of the original only needs
// the calls the game server and client make to compile. Bug reports become the exception text.

interface

uses
  System.SysUtils;

type
  TExceptType = (etNormal, etFrozen, etHidden);

  TMESettings = class
    public
      MailFrom : string;
      HttpServer : AnsiString;
      HttpPort : integer;
  end;

function MESettings : TMESettings;
function CreateBugReport(ExceptType : TExceptType) : string;
procedure AutoSendBugReport(const BugReport : string; Screenshot : Pointer);
procedure AutoSaveBugReport(const BugReport : string; Screenshot : Pointer);
procedure PauseMadExcept(Pause : boolean = True);

implementation

var
  FSettings : TMESettings;

function MESettings : TMESettings;
begin
  if not assigned(FSettings) then FSettings := TMESettings.Create;
  Result := FSettings;
end;

function CreateBugReport(ExceptType : TExceptType) : string;
begin
  if ExceptObject is Exception then
    Result := Exception(ExceptObject).Message
  else
    Result := 'unknown exception';
end;

procedure AutoSendBugReport(const BugReport : string; Screenshot : Pointer);
begin
end;

procedure AutoSaveBugReport(const BugReport : string; Screenshot : Pointer);
begin
end;

procedure PauseMadExcept(Pause : boolean);
begin
end;

end.
