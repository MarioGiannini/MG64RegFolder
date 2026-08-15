unit uRegistryTreeView;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, ComCtrls, Graphics, ImgList, Registry, Windows;

type
  PRegistryNodeData = ^TRegistryNodeData;
  TRegistryNodeData = record
    RootKey: HKEY;
    Path: string;
    Loaded: Boolean;
  end;

  { TRegistryTreeView }

  TRegistryTreeView = class(TTreeView)
  private
    FCheckImages: TImageList;
    FLoadedRoots: Boolean;
    procedure CreateCheckboxImages;
    procedure FreeNodeData(ANode: TTreeNode);
    procedure ClearAllData;
    function EnumerateSubKeys(ARootKey: HKEY; const APath: string; AParentNode: TTreeNode): Boolean;
    procedure ToggleNodeCheck(ANode: TTreeNode);
  protected
    procedure CreateWnd; override;
    procedure Loaded; override;
    function CanExpand(Node: TTreeNode): Boolean; override;
    procedure Delete(Node: TTreeNode); override;
    procedure Click; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure PopulateRegistry;
    function GetSelectedRegistryPaths: TStringList;
  published
    property Align;
    property Anchors;
    property BorderStyle;
    property Color;
    property Enabled;
    property Font;
    property Options;
    property OnChange;
    property OnClick;
    property OnDblClick;
    property OnExpanding;
    property OnSelectionChanged;
    property Visible;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('Custom', [TRegistryTreeView]);
end;

{ TRegistryTreeView }

constructor TRegistryTreeView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLoadedRoots := False;

  Options := [tvoAutoItemHeight, tvoHideSelection, tvoShowButtons, tvoShowLines, tvoShowRoot,tvoKeepCollapsedNodes];
  ReadOnly := True;

  CreateCheckboxImages;
end;

destructor TRegistryTreeView.Destroy;
begin
  ClearAllData;
  FCheckImages.Free;
  inherited Destroy;
end;

procedure TRegistryTreeView.CreateCheckboxImages;
var
  Bmp: Graphics.TBitmap;
begin
  FCheckImages := TImageList.Create(Self);
  FCheckImages.Width := 16;
  FCheckImages.Height := 16;

  Bmp := Graphics.TBitmap.Create; // Create checked and unchecked bitmaps
  try
    Bmp.SetSize(16, 16);
    Bmp.Canvas.Brush.Color := clWindow;
    Bmp.Canvas.Pen.Color := clWindowFrame;
    Bmp.Canvas.Rectangle(1, 1, 15, 15);
    FCheckImages.Add(Bmp, nil);
    Bmp.Canvas.Rectangle(1, 1, 15, 15);
    Bmp.Canvas.Pen.Color := clHighlight;
    Bmp.Canvas.Pen.Width := 2;
    Bmp.Canvas.Line(4, 8, 7, 11);
    Bmp.Canvas.Line(7, 11, 12, 5);
    FCheckImages.Add(Bmp, nil);
  finally
    Bmp.Free;
  end;

  StateImages := FCheckImages;
end;

procedure TRegistryTreeView.ToggleNodeCheck(ANode: TTreeNode);
begin
  if Assigned(ANode) then
  begin
    if ANode.StateIndex = 0 then
      ANode.StateIndex := 1
    else
      ANode.StateIndex := 0;
  end;
end;

procedure TRegistryTreeView.Click;
var
  Pt: TPoint;
  HitNode: TTreeNode;
  HitTest: THitTests;
begin
  inherited Click;

  Pt := ScreenToClient(Mouse.CursorPos);
  HitTest := GetHitTestInfoAt(Pt.X, Pt.Y);
  HitNode := GetNodeAt(Pt.X, Pt.Y);

  if (htOnStateIcon in HitTest) and Assigned(HitNode) then
  begin
    ToggleNodeCheck(HitNode);
  end;
end;

procedure TRegistryTreeView.CreateWnd;
begin
  inherited CreateWnd;

  if not (csDesigning in ComponentState) and (Items.Count = 0) then
  begin
    PopulateRegistry;
  end;
end;

procedure TRegistryTreeView.Loaded;
begin
  inherited Loaded;
  if not (csDesigning in ComponentState) and (Items.Count = 0) and HandleAllocated then
  begin
    PopulateRegistry;
  end;
end;

procedure TRegistryTreeView.Delete(Node: TTreeNode);
begin
  FreeNodeData(Node);
  inherited Delete(Node);
end;

procedure TRegistryTreeView.FreeNodeData(ANode: TTreeNode);
var
  PData: PRegistryNodeData;
begin
  if Assigned(ANode) and Assigned(ANode.Data) then
  begin
    PData := PRegistryNodeData(ANode.Data);
    Dispose(PData);
    ANode.Data := nil;
  end;
end;

procedure TRegistryTreeView.ClearAllData;
var
  I: Integer;
begin
  for I := 0 to Items.Count - 1 do
    FreeNodeData(Items[I]);
end;

procedure TRegistryTreeView.PopulateRegistry;
var
  HKLMNode, HKCUNode: TTreeNode;
  DataHKLM, DataHKCU: PRegistryNodeData;
begin
  Items.BeginUpdate;
  try
    ClearAllData;
    Items.Clear;

    // HKEY_LOCAL_MACHINE
    New(DataHKLM);
    DataHKLM^.RootKey := HKEY_LOCAL_MACHINE;
    DataHKLM^.Path := '';
    DataHKLM^.Loaded := False;
    HKLMNode := Items.AddChildObject(nil, 'HKEY_LOCAL_MACHINE', DataHKLM);
    HKLMNode.StateIndex := 0;
    Items.AddChild(HKLMNode, ''); // Dummy node, for expansion

    // HKEY_CURRENT_USER
    New(DataHKCU);
    DataHKCU^.RootKey := HKEY_CURRENT_USER;
    DataHKCU^.Path := '';
    DataHKCU^.Loaded := False;
    HKCUNode := Items.AddChildObject(nil, 'HKEY_CURRENT_USER', DataHKCU);
    HKCUNode.StateIndex := 0;
    Items.AddChild(HKCUNode, ''); // Dummy node, for expansion

    FLoadedRoots := True;
  finally
    Items.EndUpdate;
  end;
end;

function TRegistryTreeView.EnumerateSubKeys(ARootKey: HKEY; const APath: string; AParentNode: TTreeNode): Boolean;
var
  Reg, SubReg: TRegistry;
  KeyList: TStringList;
  I: Integer;
  NewNode: TTreeNode;
  ChildData: PRegistryNodeData;
  SubPath: string;
  HasSubKeys: Boolean;
begin
  Result := False;
  Reg := TRegistry.Create(KEY_READ);
  KeyList := TStringList.Create;
  try
    Reg.RootKey := ARootKey;
    if Reg.OpenKeyReadOnly(APath) then
    begin
      Reg.GetKeyNames(KeyList);
      Reg.CloseKey;

      Items.BeginUpdate;
      try
        // Delete ONLY the dummy node (which has nil Data)
        if (AParentNode.Count > 0) and (AParentNode.Items[0].Data = nil) then
        begin
          AParentNode.Items[0].Delete;
        end;

        for I := 0 to KeyList.Count - 1 do
        begin
          if APath = '' then
            SubPath := KeyList[I]
          else
            SubPath := APath + '\' + KeyList[I];

          New(ChildData);
          ChildData^.RootKey := ARootKey;
          ChildData^.Path := SubPath;
          ChildData^.Loaded := False;

          NewNode := Items.AddChildObject(AParentNode, KeyList[I], ChildData);
          NewNode.StateIndex := 0; // Unchecked

          HasSubKeys := False;
          SubReg := TRegistry.Create(KEY_READ);
          try
            SubReg.RootKey := ARootKey;
            if SubReg.OpenKeyReadOnly(SubPath) then
            begin
              HasSubKeys := SubReg.HasSubKeys;
              SubReg.CloseKey;
            end;
          finally
            SubReg.Free;
          end;

          // If it has subkeys, give it a dummy node so LCL draws the expand [+] button natively
          if HasSubKeys then
            Items.AddChildObject(NewNode, '', nil);
        end;

        Result := True;
      finally
        Items.EndUpdate;
      end;
    end;
  finally
    KeyList.Free;
    Reg.Free;
  end;
end;

function TRegistryTreeView.CanExpand(Node: TTreeNode): Boolean;
var
  Data: PRegistryNodeData;
begin
  Result := inherited CanExpand(Node);

  if Result and Assigned(Node.Data) then
  begin
    Data := PRegistryNodeData(Node.Data);
    if not Data^.Loaded then
    begin
      if EnumerateSubKeys(Data^.RootKey, Data^.Path, Node) then
        Data^.Loaded := True;
    end;
  end;
end;

function TRegistryTreeView.GetSelectedRegistryPaths: TStringList;
var
  I: Integer;
  Node: TTreeNode;
  Data: PRegistryNodeData;
  RootName: string;
begin
  Result := TStringList.Create;
  for I := 0 to Items.Count - 1 do
  begin
    Node := Items[I];
    if Node.StateIndex = 1 then
    begin
      if Assigned(Node.Data) then
      begin
        Data := PRegistryNodeData(Node.Data);
        if Data^.RootKey = HKEY_LOCAL_MACHINE then
          RootName := 'HKLM\'
        else
          RootName := 'HKCU\';

        Result.Add(RootName + Data^.Path);
      end;
    end;
  end;
end;

initialization
  Classes.RegisterClass(TRegistryTreeView);

end.
