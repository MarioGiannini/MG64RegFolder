unit uRegistrySearchThread;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Registry, Windows;

type
  { Event types for updating the UI }
  TRegistrySearchProgressEvent = procedure(const ACurrentPath: string; AFoundCount: Integer) of object;

  { Threaded Registry Searcher }

  { TRegistrySearchThread }

  TRegistrySearchThread = class(TThread)
  private
    fStartPaths: TStringList;
    fSearchText: string;
    fReplaceText: string;
    fAsFolder: boolean;
    fIgnoreGPO: boolean;
    fResults: TStringList;
    fFoundCount: Integer;
    fCurrentPath: string;
    fOnProgress: TRegistrySearchProgressEvent;

    procedure DoProgressSync;
    procedure ParseRootAndSubPath(const AFullPath: string; out ARootKey: HKEY; out ASubPath: string);
    procedure SearchRegistryKey(ARootKey: HKEY; const ASubPath: string);
    function ContainsSearchText(const AText: string): Boolean;
  protected
    fPauseEvent: PRTLEvent;
    fIsPaused: Boolean;
    procedure Execute; override;
  public
    constructor Create(AStartPaths: TStringList; const ASearchText: string; const AReplaceText: String; AAsFolder: boolean; AIgnoreGPO: Boolean; OnProgressCallback: TRegistrySearchProgressEvent = nil);
    destructor Destroy; override;

    procedure Pause;
    procedure Resume;
    procedure CheckPaused;

    { Thread-safe access to results upon completion }
    property Terminated;
    property Results: TStringList read fResults;
    property FoundCount: Integer read fFoundCount;
  end;

implementation

constructor TRegistrySearchThread.Create(AStartPaths: TStringList; const ASearchText: string; const AReplaceText: String; AAsFolder: boolean; AIgnoreGPO: Boolean; OnProgressCallback: TRegistrySearchProgressEvent);
begin
  inherited Create(False);
  FreeOnTerminate := False; // We want the main form to be able to read the results after we're done

  fStartPaths := TStringList.Create;
  if Assigned(AStartPaths) then
    fStartPaths.Assign(AStartPaths);

  fSearchText := UpperCase(ASearchText); // Case-insensitive comparison
  fReplaceText := AReplaceText;
  fAsFolder := AAsFolder;
  fIgnoreGPO := AIgnoreGPO;

  fResults := TStringList.Create;
  fFoundCount := 0;
  fOnProgress := OnProgressCallback;
end;

destructor TRegistrySearchThread.Destroy;
begin
  fStartPaths.Free;
  fResults.Free;
  inherited Destroy;
end;

procedure TRegistrySearchThread.Pause;
begin
  if not fIsPaused then
  begin
    fIsPaused := True;
    RTLEventResetEvent(FPauseEvent); // Clear event -> Causes RTLEventWaitFor to block
  end;
end;

procedure TRegistrySearchThread.Resume;
begin
  if fIsPaused then
    begin
      fIsPaused := False;
      RTLEventSetEvent(FPauseEvent); // Signal event -> Unblocks RTLEventWaitFor
    end;
end;

procedure TRegistrySearchThread.CheckPaused;
begin
  // If paused, wait here indefinitely until ResumeProcess sets the event or Terminated is signaled
  while FIsPaused and not Terminated do
  begin
    RTLEventWaitFor(FPauseEvent, 100); // Check every 100ms so Terminated isn't blocked
  end;
end;

procedure TRegistrySearchThread.DoProgressSync;
begin
  if Assigned(fOnProgress) then
    fOnProgress(FCurrentPath, FFoundCount);
end;

function TRegistrySearchThread.ContainsSearchText(const AText: string): Boolean;
begin
  Result := Pos(fSearchText, UpperCase(AText)) > 0;
end;

procedure TRegistrySearchThread.ParseRootAndSubPath(const AFullPath: string; out ARootKey: HKEY; out ASubPath: string);
var
  CleanPath, RootStr: string;
  SlashPos: Integer;
begin
  CleanPath := Trim(AFullPath);
  SlashPos := Pos('\', CleanPath);

  if SlashPos > 0 then
  begin
    RootStr := UpperCase(Copy(CleanPath, 1, SlashPos - 1));
    ASubPath := Copy(CleanPath, SlashPos + 1, Length(CleanPath));
  end
  else
  begin
    RootStr := UpperCase(CleanPath);
    ASubPath := '';
  end;

  if (RootStr = 'HKLM') or (RootStr = 'HKEY_LOCAL_MACHINE') then
    ARootKey := HKEY_LOCAL_MACHINE
  else if (RootStr = 'HKCU') or (RootStr = 'HKEY_CURRENT_USER') then
    ARootKey := HKEY_CURRENT_USER
  else if (RootStr = 'HKCR') or (RootStr = 'HKEY_CLASSES_ROOT') then
    ARootKey := HKEY_CLASSES_ROOT
  else if (RootStr = 'HKU') or (RootStr = 'HKEY_USERS') then
    ARootKey := HKEY_USERS
  else
    ARootKey := HKEY_CURRENT_USER; // Default fallback
end;

procedure TRegistrySearchThread.SearchRegistryKey(ARootKey: HKEY; const ASubPath: string);
var
  Reg: TRegistry;
  SubKeys, ValueNames: TStringList;
  KeyName, ValName, ValData, FullKeyPath, State, Altered: string;
  exists: Boolean;
  I, Index, specialSep: Integer;
begin
  // Check for cancellation request
  if Terminated then Exit;
  CheckPaused;

  Reg := TRegistry.Create(KEY_READ);
  SubKeys := TStringList.Create;
  ValueNames := TStringList.Create;
  try
    Reg.RootKey := ARootKey;

    if Reg.OpenKeyReadOnly(ASubPath) then
    begin
      // Construct path string for results
      if ARootKey = HKEY_LOCAL_MACHINE then
        FullKeyPath := 'HKLM\' + ASubPath
      else if ARootKey = HKEY_CURRENT_USER then
        FullKeyPath := 'HKCU\' + ASubPath
      else
        FullKeyPath := ASubPath;

      // Update current status for UI reporting
      fCurrentPath := FullKeyPath;
      Synchronize(@DoProgressSync);

      // 1. SEARCH CURRENT KEY NAME
      if ContainsSearchText(ASubPath) then
      begin
        fResults.Add(FullKeyPath + #9 + '[Key Match]');
        Inc(FFoundCount);
      end;

      // 2. SEARCH VALUE NAMES AND VALUE DATA
      Reg.GetValueNames(ValueNames);
      for I := 0 to ValueNames.Count - 1 do
      begin
        if Terminated then Exit;

        ValName := ValueNames[I];
        ValData := '';

        try
          case Reg.GetDataType(ValName) of
            rdString, rdExpandString: ValData := Reg.ReadString(ValName);
            rdInteger: ValData := IntToStr(Reg.ReadInteger(ValName));
            rdBinary: ValData := '[Binary Data]';
          end;
        except
          ValData := '[Unreadable]';
        end;

        if ContainsSearchText(ValName) or ContainsSearchText(ValData) then
        begin
          if ValName = '' then ValName := '(Default)';
          if( fAsFolder ) then
          begin
            altered := StringReplace( ValData, fSearchText, fReplaceText, [ rfIgnoreCase ] );
            exists := FileExists(altered) or DirectoryExists(altered);
            specialSep := Pos( ']*\\', altered );
            if ( exists = false ) and (specialSep > 1 ) then
            begin
                // [F00000000][T01DC9775C1E2B420][O00000000]*\\Files23\Transfer\repl.csv
                altered := Copy( altered, specialSep + 2 );
                exists := FileExists(altered) or DirectoryExists(altered);
            end;
            if( exists ) then
              State := 'OK'
            else
              State := 'Missing';
          end
          else
              State := 'N/A';
          fResults.Add(FullKeyPath + '\' + ValName + #9 + State + #9 + ValData);
          Inc(FFoundCount);
        end;
      end;

      Reg.GetKeyNames(SubKeys);
      Reg.CloseKey;

      for I := 0 to SubKeys.Count - 1 do
      begin
        if Terminated then Exit;

        KeyName := SubKeys[I];
        index := Pos( 'Group Policy Object', keyName );
        if fIgnoreGPO and ( index > 0 ) then
        begin
           continue;
        end;

        if ASubPath = '' then
          SearchRegistryKey(ARootKey, KeyName)
        else
          SearchRegistryKey(ARootKey, ASubPath + '\' + KeyName);
      end;
    end;
  finally
    ValueNames.Free;
    SubKeys.Free;
    Reg.Free;
  end;
end;

procedure TRegistrySearchThread.Execute;
var
  I: Integer;
  RootKey: HKEY;
  SubPath: string;
begin
  if (FStartPaths.Count = 0) or (FSearchText = '') then
    Exit;

  for I := 0 to fStartPaths.Count - 1 do
  begin
    if Terminated then Break;

    ParseRootAndSubPath(FStartPaths[I], RootKey, SubPath);
    SearchRegistryKey(RootKey, SubPath);
  end;

  fCurrentPath := 'Search Complete';
  Synchronize(@DoProgressSync);
end;

end.
