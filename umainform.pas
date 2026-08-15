unit uMainForm;

{$mode objfpc}{$H+}

interface


uses

  Classes, SysUtils, DateUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, ComCtrls,
  StdCtrls, Clipbrd, Registry, uRegistryTreeView, uRegistrySearchThread;

type

  { TmainForm }

  TmainForm = class(TForm)
    btnSearch: TButton;
    btnCopy: TButton;
    btnExport: TButton;
    btnReplace: TButton;
    btnDelete: TButton;
    btnUndo: TButton;
    btnClearSelected: TButton;
    cbAsFolder: TCheckBox;
    cbIgnoreGPO: TCheckBox;
    lblStatus: TLabel;
    leSearchFor: TLabeledEdit;
    leReplaceWith: TLabeledEdit;
    lvResults: TListView;
    Panel1: TPanel;
    Panel2: TPanel;
    Panel3: TPanel;
    Splitter1: TSplitter;
    tvRegistrySpotHolder: TTreeView;
    procedure btnCopyClick(Sender: TObject);
    procedure btnDeleteClick(Sender: TObject);
    procedure btnExportClick(Sender: TObject);
    procedure btnReplaceClick(Sender: TObject);
    procedure btnSearchClick(Sender: TObject);
    procedure btnUndoClick(Sender: TObject);
    procedure btnClearSelectedClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    tvRegistry: TRegistryTreeView;
    fSearchThread: TRegistrySearchThread;
    lastProgress: TDateTime;

    procedure OnSearchProgress(const ACurrentPath: string; AFoundCount: Integer);
    procedure OnSearchTerminated(Sender: TObject);
    procedure ProcessRegistryValue( Path: String; Value: String; delete: Boolean );
    procedure SetRegistryValue( Path: String; Value: String );
    procedure DeleteRegistryValue( Path: String );
    function GetRootKey( path: String ) : QWord;
    procedure doProcess( AsReplace: Boolean );
    function ShouldShowDisclaimer: Boolean;
    procedure SaveDisclaimerPreference(AHide: Boolean);
    procedure ShowDisclaimerForm;

  public

  end;

const
  REG_KEY = 'Software\MG64\MG64RegFolder';
var
  mainForm: TmainForm;

implementation

{$R *.lfm}

{ TmainForm }

procedure TmainForm.btnSearchClick(Sender: TObject);
var
  paths: TStringList;
begin
  if( btnSearch.Caption = 'Search' ) then
  begin
    paths := tvRegistry.GetSelectedRegistryPaths;
    if( paths.Count = 0 ) then
        MessageDlg('Information', 'No items selected', mtInformation, [mbok], 0)
    else if( Trim(leSearchFor.Text)='') then
         MessageDlg('Information', 'You must include Search For text', mtInformation, [mbok], 0)
    else
    begin
      btnSearch.Caption := 'Cancel';
      lastProgress := IncSecond(Now, -10);
      fSearchThread := TRegistrySearchThread.Create(paths, leSearchFor.Text, leReplaceWith.Text, cbAsFolder.Checked, cbIgnoreGPO.Checked, @OnSearchProgress);
      fSearchThread.OnTerminate := @OnSearchTerminated;
    end;
    paths.free;
  end
  else
  begin
    fSearchThread.Pause;
    if( MessageDlg('Confirmation', 'Quit searching?', mtConfirmation, [mbYes,mbNo], 0) = mrYes ) then
    begin
      LblStatus.Caption := 'Cancelling search...';
      fSearchThread.Terminate; // Signal thread to abort loop
    end;
    fSearchThread.Resume;
  end;
end;

procedure TmainForm.OnSearchProgress(const ACurrentPath: string; AFoundCount: Integer);
var
  currentTime: TDateTime;
begin
  currentTime := Now;
  if SecondsBetween(currentTime, lastProgress) >= 1 then begin
    lastProgress := currentTime;
    LblStatus.Caption := Format('Found %d, on %s', [AFoundCount, ACurrentPath]);

  end;
end;

procedure TmainForm.OnSearchTerminated(Sender: TObject);
var
  found: String;
  Item: TListItem;
  Parts: TStringArray;
begin
  if Assigned(fSearchThread) then
  begin
    if fSearchThread.Terminated then
      LblStatus.Caption := Format('Search cancelled. Found %d match(es).', [FSearchThread.FoundCount])
    else
    begin
      LblStatus.Caption := Format('Done. Found %d match(es).', [FSearchThread.FoundCount]);
      lvResults.Items.Clear;
      for found in fSearchThread.Results do
      begin
        Parts := found.Split([#9]);
        if( Length( Parts )  = 3 ) then
        begin
          Item := lvResults.Items.Add;
          Item.Checked := false;
          Item.Caption := parts[0];
          Item.SubItems.Add( parts[1] );
          Item.SubItems.Add( parts[2] );
          Item.SubItems.Add( StringReplace( parts[2], leSearchFor.Text, leReplaceWith.Text, [rfIgnoreCase] ) );
        end;
      end;
    end;

    // Free the thread manually since FreeOnTerminate := False
    FreeAndNil(fSearchThread);
  end;
  btnSearch.Caption := 'Search';

end;

function TmainForm.GetRootKey( path: String ) : QWord;
begin
  if( Pos( 'HKLM\', Path ) = 1 ) then Result := HKEY_LOCAL_MACHINE
  else if( Pos( 'HKCR\', Path ) = 1 ) then Result :=  HKEY_CLASSES_ROOT
  else if( Pos( 'HKU\', Path ) = 1 ) then Result :=  HKEY_USERS
  else
    result :=  HKEY_CURRENT_USER;
end;

procedure TmainForm.doProcess( AsReplace: Boolean );
var
  lines: TStringList;
  log: TStringList;
  item: TListItem;
  i, items, processed: integer;
  SaveDialog: TSaveDialog;
  operation: String;
begin
  Items := 0;
  processed := 0;
  for i := 0 to lvResults.Items.Count -1 do
  begin
    if( lvResults.Items[i].Checked ) then Inc( Items );
  end;
  if( Items = 0 ) then
  begin
       MessageDlg('Information', 'No items found or selected to process', mtInformation, [mbOk], 0);
       exit;
  end;
  if( AsReplace ) then
      operation := 'replace'
  else
      operation := 'delete';
  if( MessageDlg('Confirmation', 'Are you sure you want to ' + operation + ' the selected items?', mtConfirmation, [mbYes,mbNo], 0) <> mrYes ) then
      exit;
  lines := TStringList.Create;
  Log := TStringList.Create;
  Items := 0;

  for i := 0 to lvResults.Items.Count -1 do
  begin
    item := lvResults.Items[i];
    if( item.Checked ) then
    begin
      inc( processed );
      if( asReplace ) then
      begin
        log.Add( 'REPLACE' + #9 + item.caption + #9 + Item.SubItems[1] + #9 + Item.SubItems[2]);
        SetRegistryValue( item.caption, Item.SubItems[2] );
      end
      else
      begin
        log.Add( 'DELETE' + #9 + item.caption + #9 + Item.SubItems[1] + #9 + Item.SubItems[2]);
        DeleteRegistryValue( item.caption );
      end;
    end;
  end;

  SaveDialog := TSaveDialog.Create(nil);
  try
    SaveDialog.Title := 'Save Log File';
    SaveDialog.Filter := 'Log Files (*.log)|*.log|All Files (*.*)|*.*';
    SaveDialog.DefaultExt := 'log';
    SaveDialog.FileName := 'Process_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.Log';
    SaveDialog.Options := SaveDialog.Options + [ofOverwritePrompt]; // Warns before overwriting files

    if SaveDialog.Execute then
    begin
      log.SaveToFile(SaveDialog.FileName);
    end;
  finally
    SaveDialog.Free;
    Lines.Free;
    Log.Free;
    lblStatus.Caption := 'Items processed: ' + IntToStr( processed );
  end;

end;

function TmainForm.ShouldShowDisclaimer: Boolean;
var
  Reg: TRegistry;
begin
  Result := True;
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly(REG_KEY) then
    begin
      if Reg.ValueExists('HideDisclaimer') then
        Result := Reg.ReadInteger('HideDisclaimer') = 0;
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;

end;

procedure TmainForm.SaveDisclaimerPreference(AHide: Boolean);
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey(REG_KEY, True) then
    begin
      if AHide then
        Reg.WriteInteger('HideDisclaimer', 1)
      else
        Reg.WriteInteger('HideDisclaimer', 0);
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;

end;

procedure TmainForm.ShowDisclaimerForm;
var
  Dlg: TForm;
  lblWarning: TLabel;
  chkNeverShow: TCheckBox;
  btnOK: TButton;
begin
  Dlg := TForm.Create(nil);
  try
    Dlg.Caption := 'Warning / Disclaimer';
    Dlg.Width := 500;
    Dlg.Height := 460;
    Dlg.Position := poScreenCenter;
    Dlg.BorderStyle := bsDialog;
    Dlg.BorderIcons := [];

    lblWarning := TLabel.Create(Dlg);
    lblWarning.Parent := Dlg;
    lblWarning.Left := 24;
    lblWarning.Top := 24;
    lblWarning.Width := 450;
    lblWarning.AutoSize := False;
    lblWarning.Height := 310;
    lblWarning.WordWrap := True;
    lblWarning.Caption := 'DISCLAIMER & TERMS OF USE:' + sLineBreak + sLineBreak +
      'This software is provided "as is", without warranty of any kind, express or implied. ' +
      'In no event shall the author or developers be liable for any claim, damages, or other ' +
      'liability arising from the use of this software.' + sLineBreak + sLineBreak +
      'Altering the registry is a risky operation.' + sLineBreak + sLineBreak +
      'Please proceed only if you understand and accept these terms.';

    chkNeverShow := TCheckBox.Create(Dlg);
    chkNeverShow.Parent := Dlg;
    chkNeverShow.Left := 24;
    chkNeverShow.Top := 355;
    chkNeverShow.Caption := 'Do not show this warning again';
    chkNeverShow.AutoSize := True;

    btnOK := TButton.Create(Dlg);
    btnOK.Parent := Dlg;
    btnOK.Caption := 'I Accept';
    btnOK.Width := 110;
    btnOK.Height := 32;
    btnOK.Left := (Dlg.ClientWidth - btnOK.Width) div 2;
    btnOK.Top := 400;
    btnOK.ModalResult := mrOk;

    Dlg.DefaultMonitor := dmMainForm;

    if Dlg.ShowModal = mrOk then
    begin
      if chkNeverShow.Checked then
        SaveDisclaimerPreference(True);
    end;

  finally
    Dlg.Free;
  end;
end;

procedure TmainForm.ProcessRegistryValue( Path: String; Value: String; delete: Boolean );
var
  Reg: TRegistry;
  p: integer;
  regName: String;
begin
  Reg := TRegistry.Create(KEY_WRITE);
  try
    Reg.RootKey := GetRootKey( path );
    P := Pos( '\', path );
    Path := Copy( Path, P );
    regName := ExtractFileName(Path);
    Path := ExtractFilePath(Path);

    if Reg.OpenKey( path, false ) then
    begin
      try
        if( delete ) then
          Reg.DeleteValue( regName )
        else
          Reg.WriteString( regName,  value);
      finally
        Reg.CloseKey;
      end;
    end;
  finally
    Reg.Free;
  end;

end;

procedure TmainForm.SetRegistryValue(Path: String; Value: String);
begin
  ProcessRegistryValue( path, value, false );
end;

procedure TmainForm.DeleteRegistryValue(Path: String);
begin
    ProcessRegistryValue( path, '', true );
end;

procedure TmainForm.btnUndoClick(Sender: TObject);
var
  FileLines: TStringList;
  I, lineIndex: Integer;
  OpenDialog: TOpenDialog;
  Parts: TStringArray;
  restored: integer;
begin
  restored := 0;
  OpenDialog := TOpenDialog.Create(nil);
  OpenDialog.Filter := 'Log Files (*.log)|*.log|All Files (*.*)|*.*';
  OpenDialog.Title := 'Select a file to process';
  OpenDialog.Options := OpenDialog.Options + [ofAllowMultiSelect];

  if OpenDialog.Execute then
  begin

    FileLines := TStringList.Create;
    try
      try

        for I := 0 to OpenDialog.Files.Count - 1 do
        begin
          FileLines.LoadFromFile( OpenDialog.Files[I] );
          for lineIndex := 0 to FileLines.Count - 1 do
          begin
               parts :=FileLines[lineIndex].Split( #9 );
               if( Length( parts ) > 3 ) then
               begin
                 SetRegistryValue( parts[1], parts[2] );
                 inc( restored );
               end;
          end;
        end;

      except
        on E: Exception do
          MessageDlg('Error', e.message, mtError, [mbOk], 0);
      end;
    finally
      OpenDialog.free;
      FileLines.Free;
      ShowMessage('Items restored: ' + IntToStr( restored ) );
    end;
  end;

end;

procedure TmainForm.btnClearSelectedClick(Sender: TObject);
var
  I: Integer;
begin
  tvRegistry.Items.BeginUpdate;
  try
    for I := 0 to tvRegistry.Items.Count - 1 do
    begin
      tvRegistry.Items[I].StateIndex := 0;
    end;
  finally
    tvRegistry.Items.EndUpdate;
  end;
end;


procedure TmainForm.FormCreate(Sender: TObject);
begin
  tvRegistry := TRegistryTreeView.Create(Self);
  tvRegistry.Parent := tvRegistrySpotHolder.Parent;
  tvRegistry.BoundsRect := tvRegistrySpotHolder.BoundsRect;
  tvRegistry.Anchors := tvRegistrySpotHolder.Anchors;
  tvRegistry.Align := tvRegistrySpotHolder.Align;

  // Hide the original placeholder tree
  tvRegistrySpotHolder.Visible := False;

  if ShouldShowDisclaimer then
    ShowDisclaimerForm;
end;

procedure TmainForm.btnCopyClick(Sender: TObject);
var
  Item: TListItem;
begin
  Item := lvResults.Selected;
  if Assigned(Item) then
    begin
      Clipboard.AsText := Item.Caption + sLineBreak + Item.SubItems[0] + sLineBreak + Item.SubItems[1] + sLineBreak + Item.SubItems[2];
      ShowMessage('Copied to clipboard');
    end
    else
    begin
      ShowMessage('No item is selected.');
    end;

end;

procedure TmainForm.btnDeleteClick(Sender: TObject);
begin
    doProcess( false );
end;

procedure TmainForm.btnExportClick(Sender: TObject);
var
  lines: TStringList;
  item: TListItem;
  i: integer;
  SaveDialog: TSaveDialog;
begin
  if( lvResults.Items.Count = 0 ) then
  begin
       MessageDlg('Information', 'No items found to export', mtInformation, [mbOk], 0);
       exit;
  end;
  lines := TStringList.Create;

  for i := 0 to lvResults.Items.Count -1 do
  begin
    item := lvResults.Items[i];
    lines.Add( item.caption + #9 + Item.SubItems[1] + #9 + Item.SubItems[2]);
  end;

  SaveDialog := TSaveDialog.Create(nil);
  try
    SaveDialog.Title := 'Save Text File';
    SaveDialog.Filter := 'Text Files (*.txt)|*.txt|All Files (*.*)|*.*';
    SaveDialog.DefaultExt := 'txt';
    SaveDialog.Options := SaveDialog.Options + [ofOverwritePrompt]; // Warns before overwriting files

    // Display the dialog to the user
    if SaveDialog.Execute then
    begin
      // SaveToFile automatically writes each line of TStringList as a line in the text file
      lines.SaveToFile(SaveDialog.FileName);
//      ShowMessage('File saved successfully!');
    end;
  finally
    SaveDialog.Free;
  end;

end;

procedure TmainForm.btnReplaceClick(Sender: TObject);
begin
  doProcess( true );
end;

end.

