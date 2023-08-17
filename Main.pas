﻿{
WinXCorners
Author: Victor Alberto Gil <vhanla>
A rewrite from scratch of Win7sé for Windows 10

TODO:
HiDPI support - Works 75%

Hook DLL - Advantages, less CPU usage
           Cons: doesn't trigger from privileged focused programs
            current approach using WM_COPYDATA breaks on software delay like using rest
              connection
           Needs more tests and improvement, disabled for now.

Features requested:
- Detect Fullscreen applications
- Blacklist applications
- Win+Home (done)
- Disable Sleep Mode
- Windows Start
- Disable Screen Saver
- Hotkey from command
- Minimize
- Ctrl-Esc or Win+X
- Virtual Desktop Screen switcher

CHANGELOG:
- 23-08-16
  fixed StayOnTop issue on FMX.PlatformWin.pas

- 23-04-10
  frmMouseShake added with Animated Gif to show the mouse cursor position on Ctrl hold + mouse shake

- 22-06-06
  Refactor actions handling, and define scripting functions

- 20-09-03
  Added PascalScript for extending custom actions via pascal scripts
  Moved actions to actionsManager.pas
- 20-08-13
  Added custom window list gui to pick and support drag&drop features from origin to picked window
  Added knocking door like gesture to desktop sides in order to trigger actions
  Added function to detect fullscreen UWP apps
  Modified settings window to give a Windows 10 like design
  Added update tray icon on WM_DWMCOLORIZATIONCOLORCHANGED in frmSettings
  Replaced systray menu with custom UCL.Popup to give a Windows 10 look alike
- 19-06-06
  Detect DarkMode/LightMode Windows 10 May Update 2019
- 18-09-03
  Detect Lock/Unlock to disable temporarily
  Removed incomplete update checker to release memory usage from 8MB to 6MB
  Reduced speed of hotspot timer from 100 to 250
  Hacky workaround to avoid activating TopLeft hotscreen on LogonUI (Ctrl+Alt+Del)
    checking GetForeground, which fails and returns 0 as well we make sure is zero
    if not return on exception.

- 17-06-02
  Added feature, Win+Home to hide/show background windows
   Suggested by Anthony Dodd at comments
   Solution found at https://blogs.msdn.microsoft.com/oldnewthing/20170530-00/?p=96246
   Raymond Chen says that restoring might not preserve z-order if one windows is not responding
   Known limitation: some apps capture win+home and won't allow to trigger it
  Added Multimonitor Support. I wanted to use generic collections, but it wasn't necessary :P
  Fixed XCheckbox HiDpi rendering (see XCheckbox.pas changelog)

- 16-08-08
  Fixed incorrect delay timer, which wasn't reset after it triggers the selected hotaction
- 16-08-07
  Fixed showing animation while holding mouse button :P
  A workaround using switch to this window to override UAC windows in foreground
  //if GetForegroundWindow <> FindWindow('MultitaskingViewFrame','Vista Tareas') then
  to avoid switching to the alt-tab window so it won't be called again due to lost focus

- 16-08-05
  Updated and modified trayicon to update it accordingly, i.e. if temporarily disabled, a grayed icon is set
  Added main.pas to uses in frmsettings and created a public procedure (UpdateTrayIcon)

  Fixed "bug" (feature :P ) that ignored mouse pressed before detecting hot corners events
  Now it is disabled so if user is selecting a text and reaches a hot corner it won't trigger the event

  Added CountDown animation (kinda)
  Added advanced options for delaying response of hotcorners
  Added execution of command line

- 16-02-27
  Fix systray dissapearance under Windows 10, it seems previous workaround doesn't match this
  new windows version, well it was the message string, now set correctly to "TaskbarCreated"
- 15-12-01
  Added support to trigger default action of taskbar's button 'task views'
- 15-11-02
  DPI Aware support, since Delphi offers a bad support with custom components
- 15-10-12
  A complete rewrite in order to only use it on Windows 10

}
unit Main;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, ShellApi, Vcl.Menus, Registry, System.Generics.Collections,
  madExceptVcl, System.Actions, Vcl.ActnList, UWP.Classes,
  UWP.ListButton, UWP.Form, UCL.Popup, UWP.ColorManager, UWP.PopupMenu,
  VirtualDesktopManager,
  UWP.Panel, actionsManager, taskbarHelper;

const
  WM_DPICHANGED = $02E0;
  INTERVAL = 300; //double tap time span to qualify

  ShakeThreshold = 100;
  MaxShakeCounter = 6;

type

{  TScreens = class(TObject)
    rect: TRect;
  public
    constructor Create(myRect: TRect);overload;
  end;}

  TShakeDirection = (sdNone, sdLeft, sdRight);

  TfrmMain = class(TUWPForm)
    tmrHotSpot: TTimer;
    tmrDelay: TTimer;
    MadExceptionHandler1: TMadExceptionHandler;
    ActionList1: TActionList;
    actCtrlAltTab: TAction;
    actShowTaskView: TAction;
    actShowActionCenterSidebar: TAction;
    actShowDesktop: TAction;
    ulbExit: TUWPListButton;
    ulbSettings: TUWPListButton;
    ulbAbout: TUWPListButton;
    ulbStartWithWindows: TUWPListButton;
    UPanel1: TUWPPanel;
    tmrSideGestures: TTimer;
    actShowStartMenu: TAction;
    tmrShakeMouse: TTimer;
    procedure tmrHotSpotTimer(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure emporarydisabled1Click(Sender: TObject);
    procedure tmrDelayTimer(Sender: TObject);
    procedure actCtrlAltTabExecute(Sender: TObject);
    procedure actShowTaskViewExecute(Sender: TObject);
    procedure actShowActionCenterSidebarExecute(Sender: TObject);
    procedure actShowDesktopExecute(Sender: TObject);
    procedure ulbAboutClick(Sender: TObject);
    procedure ulbStartWithWindowsClick(Sender: TObject);
    procedure ulbSettingsClick(Sender: TObject);
    procedure ulbExitClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure tmrSideGesturesTimer(Sender: TObject);
    procedure actShowStartMenuExecute(Sender: TObject);
    procedure tmrShakeMouseTimer(Sender: TObject);
  private
    { Private declarations }
    FSystray: TFormPopup;
    FShellTaskViewExists: Boolean;
    FShellShowDesktopExists: Boolean;
    FPrevHandle: HWND;
    iconData: TNotifyIconData;
    SystrayIcon: TIcon;
    OnHotSpot: Boolean;
    hotActionStr: String;
    hotActionDelay: Integer;
    hotActionDelayCounter: Integer;
    startTime: Uint64;
    isInArea: Boolean;
    tapCounter: Integer;
    FRegisteredSessionNotification: Boolean;
    procedure Iconito(var Msg: TMessage); message WM_USER + 1;
    procedure HotAction(hAction: string);
    procedure AutoStartState;
    procedure RegAutoStart(registerasrun: boolean = true);
    procedure WMDpiChanged(var Message: TMessage); message WM_DPICHANGED;
    procedure ShowPopup;
    procedure ClosePopup;
  private
    { Private Declarations }
    FPrevMousePos: TPoint;
    FShakeCounter: Integer;
    FShakeDirection: TShakeDirection;
    procedure HandleShaking(MPos: TPoint);
  protected
    procedure WndProc(var Msg: TMessage); override;
    //procedure WMCopyData(var Msg: TMessage); message WM_COPYDATA;
    procedure HotSpotAction(MPos: TPoint);
  public
    { Public declarations }
    FMainTaskbar: TMainTaskbar;
    FShaking: Boolean;
    procedure CreateParams(var Params: TCreateParams); override;
    procedure UpdateTrayIcon(grayed: boolean = False);
    property PrevHandle: HWND read FPrevHandle write FPrevHandle;

  end;

var
  frmMain: TfrmMain;
  CurrentForegroundHwnd: HWND;
  PrevSystrayTime: Int64 = 0;
  wmTaskbarRestartMsg: Cardinal;

//  Screens : TObjectList<TScreens>;

//  procedure SwitchToThisWindow(h1: hWnd; x: bool); stdcall;
//  external user32 Name 'SwitchToThisWindow' delayed;
//  procedure RunHook(Handle: HWND); cdecl; external 'WinXHelper.dll' name 'RunHook';
//  procedure KillHook; cdecl; external 'WinXHelper.dll' name 'KillHook';

implementation

uses
  functions, frmSettings, osdgui, frmAdvanced, XCombobox, frmWinTiles, frmMouseShake, fmxSettings;
{$R *.dfm}

const
  WM_MOUSE_COORDS = WM_USER + 9;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  if not isWindows10 then
  begin
    MessageDlg('Error. You need Windows 10 build 10240 or newer', mtError, [mbOK], 0);
    Application.Terminate;
  end;

  SetPriorityClass(GetCurrentProcess, $4000);
  { TODO : Just use keybd_event since it is faster, as of now }
  FShellTaskViewExists := False;//DetectShellTaskSwitch;
  FShellShowDesktopExists := False;//DetectShellShowDesktop;

  wmTaskbarRestartMsg := RegisterWindowMessage('TaskbarCreated');

  UpdateTrayIcon();

  ColorizationManager.ColorizationType := TUWPColorizationType.ctDark;
  //ugly workaround to allow custom popup
  Width := 10; Height := 10;
  SetWindowLong(Handle, GWL_EXSTYLE, GetWindowLong(Handle, GWL_EXSTYLE) or WS_EX_LAYERED or WS_EX_TOOLWINDOW or WS_EX_TRANSPARENT);
  SetLayeredWindowAttributes(Handle, 0, 0, LWA_ALPHA);

  FormStyle := fsStayOnTop;
  AutoStartState;

  //Screens := TObjectList<TScreens>.Create;
  FRegisteredSessionNotification := WTSRegisterSessionNotification(Handle, NOTIFY_FOR_THIS_SESSION);

//  RunHook(Handle);
  FMainTaskbar := TMainTaskbar.Create(nil);
//  FMainTaskbar.OnTaskbarRestarted :=
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  FMainTaskbar.Free;
  //Screens.Free;
//  KillHook;

  if iconData.Wnd <> 0 then
    Shell_NotifyIcon(NIM_DELETE, @iconData);

  SystrayIcon.Free;

  if FRegisteredSessionNotification then
    WTSUnRegisterSessionNotification(Handle);
end;

procedure TfrmMain.FormShow(Sender: TObject);
begin
  ShowWindow(Application.Handle, SW_HIDE);
end;

procedure TfrmMain.HandleShaking(MPos: TPoint);
begin
  // Let's show the ballon of the mouse
//  frmOSD.DrawBubble(IntToStr(hotActionDelay - hotActionDelayCounter));
//  frmOSD.Left := MPos.X;
//  frmOSD.Top := MPos.Y;
//  frmOSD.Show;
  frmMouseShake.formMouseShake.Left := MPos.X - frmMouseShake.formMouseShake.Width div 2;
  frmMouseShake.formMouseShake.Top := MPos.Y - frmMouseShake.formMouseShake.Height div 2;
   frmMouseShake.formMouseShake.Show;
  Winapi.Windows.ShowWindow(frmMouseShake.formMouseShake.Handle, SW_SHOWNOACTIVATE);
  frmMouseShake.formMouseShake.Timer1.Enabled := True;
  frmMouseShake.formMouseShake.tmrMousePos.Enabled := True;
  frmMouseShake.formMouseShake.JvGIFAnimator1.Animate := True;
//  FShaking := False;
end;

procedure TfrmMain.HotAction(hAction: string);
// this neat fun method comes from http://stackoverflow.com/questions/12960702/enum-from-string
const
  HotActions: Array[THotAction] of string = ('All Windows','Desktop','Screen Saver','Monitors Off','Action Center', 'Custom Command', 'Start Menu', 'Hide Windows', '');

  function GetAction(const str: string): THotAction;
  begin
    for Result := Low(Result) to High(Result) do
      if HotActions[Result]=str then
        Exit;
    // if nothing matches or is empty we return the no action
    Result := haNoAction;
  end;

//var
//  Shell_SecondaryTrayWnd: HWND;
//  procid: integer;
begin
  if frmTrayPopup.tempDisabled or DetectFullScreen3D or DetectFullScreenApp then
  begin
    Exit;
  end;

  // avoid usage if mouse is in use (buttons down e.g.)
  // if value is negative, it means is in use (aka held down)
{  if (GetKeyState(VK_LBUTTON) < 0)
  or (GetKeyState(VK_MBUTTON) < 0)
  or (GetKeyState(VK_RBUTTON) < 0)
  then
    Exit;}
  case GetAction(hAction) of
    haWindows:
    begin
      // let's first attempt using the taskview button
//      if not TaskbarTaskViewBtnClick then
      begin
        actShowTaskView.Execute;
        //actCtrlAltTab.Execute;
      end;
    end;
    haActionCenter:
      begin
        actShowActionCenterSidebar.Execute;
      end;
    haDesktop:
      begin
        actShowDesktop.Execute;
      end;
    haScreenSaver:
      begin
        SendMessage(Application.Handle, WM_SYSCOMMAND, SC_SCREENSAVE, 0);
      end;
    haMonitorOff:
      begin
        SendMessage(Application.Handle, WM_SYSCOMMAND, SC_MONITORPOWER,2);
      end;
    haStartMenu:
      begin
        actShowStartMenu.Execute;
      end;
    haCustomCmd:
    begin
      if frmAdvSettings.chkCustom.Checked then
      begin
        if frmAdvSettings.chkHidden.Checked then
          ShellExecute(0, 'OPEN', PChar(frmAdvSettings.edCommand.Text),PChar(frmAdvSettings.edParams.Text),'', SW_HIDE)
        else
          ShellExecute(0, 'OPEN', PChar(frmAdvSettings.edCommand.Text),PChar(frmAdvSettings.edParams.Text),'', SW_SHOWNORMAL);
      end;
    end;
    haToggleOtherWindows:
    begin
      keybd_event(VK_LWIN,MapVirtualKey(VK_LWIN,0),0,0);
      Sleep(10);
      keybd_event(VK_HOME,MapVirtualKey(VK_HOME,0),0,0);
      Sleep(10);
      keybd_event(VK_HOME,MapVirtualKey(VK_HOME,0),KEYEVENTF_KEYUP,0);
      Sleep(100);
      keybd_event(VK_LWIN,MapVirtualKey(VK_LWIN,0),KEYEVENTF_KEYUP,0);
      Sleep(100);

      // to minimize, not yet included xD
      {Shell_SecondaryTrayWnd := FindWindow('Shell_SecondaryTrayWnd', nil);
      if IsWindow(GetForegroundWindow)
      and (GetForegroundWindow <> Shell_SecondaryTrayWnd)
       then
        PostMessage(GetForegroundWindow, WM_SYSCOMMAND, SC_MINIMIZE, 0);}
    end;
    haNoAction:
    begin
    end;
  end;
end;

procedure TfrmMain.HotSpotAction(MPos: TPoint);
const
  HotArea = 10;
var
  Screen1 : TRect;
  I: Integer;
begin
//Screens.Clear;
  for I := 0 to Screen.MonitorCount - 1 do
  begin
    //Screens.Add(TScreens.Create(Screen.Monitors[I].WorkareaRect));

    Screen1 := Screen.Monitors[I].BoundsRect;
    //Screen1 := GetRectOfPrimaryMonitor(False);
    if (MPos.X >= Screen1.Left)
    and (MPos.X < Screen1.Right)
    and (MPos.Y >= Screen1.Top)
    and (MPos.Y < Screen1.Bottom)
    then
    begin


      if (MPos.X >= Screen1.Left)
      and (MPos.X < Screen1.Left+HotArea)
      and (MPos.Y >= Screen1.Top)
      and (MPos.Y < Screen1.Top+HotArea) then
      begin
        if not OnHotSpot then
        begin
          OnHotSpot := True;
          hotActionStr := frmTrayPopup.XCombo1.Caption;
          if Trim(hotActionStr) = '' then Exit;
          if not frmTrayPopup.XCheckbox1.Checked then Exit;
          // avoid usage if mouse is in use (buttons down e.g.)
          // if value is negative, it means is in use (aka held down)
          if (GetKeyState(VK_LBUTTON) < 0)
          or (GetKeyState(VK_MBUTTON) < 0)
          or (GetKeyState(VK_RBUTTON) < 0)
          then
            Exit;

          if frmAdvSettings.chkDelayGlobal.Checked or frmAdvSettings.chkDelayTopLeft.Checked then
          begin
            hotActionDelay := StrToInt(frmAdvSettings.valDelayGlobal.Text);
            if frmAdvSettings.chkDelayTopLeft.Enabled then
              hotActionDelay := StrToInt(frmAdvSettings.valDelayTopLeft.Text);

            hotActionDelayCounter := 0;
            tmrDelay.Enabled := True;
            if frmAdvSettings.chkShowCount.Checked then
            begin
              frmOSD.DrawBubble(IntToStr(hotActionDelay - hotActionDelayCounter));
              frmOSD.Left := Screen1.Left;
              frmOSD.Top := Screen1.Top;
              frmOSD.Show;
            end;
          end
          else
            HotAction(hotActionStr);
        end;
      end

      else if(MPos.X > Screen1.Right - HotArea)
      and (MPos.X <= Screen1.Right - 1)
      and (MPos.Y >= Screen1.Top)
      and (MPos.Y < Screen1.Top + HotArea) then
      begin
        if not OnHotSpot then
        begin
          OnHotSpot := True;
          //HotAction(frmTrayPopup.XCombo2.Caption);
          hotActionStr := frmTrayPopup.XCombo2.Caption;
          if Trim(hotActionStr) = '' then Exit;
          if not frmTrayPopup.XCheckbox1.Checked then Exit;
          // avoid usage if mouse is in use (buttons down e.g.)
          // if value is negative, it means is in use (aka held down)
          if (GetKeyState(VK_LBUTTON) < 0)
          or (GetKeyState(VK_MBUTTON) < 0)
          or (GetKeyState(VK_RBUTTON) < 0)
          then
            Exit;

          if frmAdvSettings.chkDelayGlobal.Checked or frmAdvSettings.chkDelayTopRight.Checked then
          begin
            hotActionDelay := StrToInt(frmAdvSettings.valDelayGlobal.Text);
            if frmAdvSettings.chkDelayTopRight.Enabled then
              hotActionDelay := StrToInt(frmAdvSettings.valDelayTopRight.Text);

            hotActionDelayCounter := 0;
            tmrDelay.Enabled := True;
            if frmAdvSettings.chkShowCount.Checked then
            begin
              frmOSD.DrawBubble(IntToStr(hotActionDelay - hotActionDelayCounter));
              frmOSD.Left := Screen1.Right - frmOSD.Width;
              frmOSD.Top := Screen1.Top;
              frmOSD.Show;
            end;
          end
          else
            HotAction(hotActionStr);
        end;
      end

      else if(MPos.X >= Screen1.Left)
      and (MPos.X < Screen1.Left + HotArea)
      and (MPos.Y <= Screen1.Bottom - 1)
      and (MPos.Y > Screen1.Bottom - HotArea) then
      begin
        if not OnHotSpot then
        begin
          OnHotSpot := True;
          //HotAction(frmTrayPopup.XCombo3.Caption);
          hotActionStr := frmTrayPopup.XCombo3.Caption;
          if Trim(hotActionStr) = '' then Exit;
          if not frmTrayPopup.XCheckbox1.Checked then Exit;
          // avoid usage if mouse is in use (buttons down e.g.)
          // if value is negative, it means is in use (aka held down)
          if (GetKeyState(VK_LBUTTON) < 0)
          or (GetKeyState(VK_MBUTTON) < 0)
          or (GetKeyState(VK_RBUTTON) < 0)
          then
            Exit;

          if frmAdvSettings.chkDelayGlobal.Checked or frmAdvSettings.chkDelayBotLeft.Checked then
          begin
            hotActionDelay := StrToInt(frmAdvSettings.valDelayGlobal.Text);
            if frmAdvSettings.chkDelayBotLeft.Enabled then
              hotActionDelay := StrToInt(frmAdvSettings.valDelayBotLeft.Text);

            hotActionDelayCounter := 0;
            tmrDelay.Enabled := True;
            if frmAdvSettings.chkShowCount.Checked then
            begin
              frmOSD.DrawBubble(IntToStr(hotActionDelay - hotActionDelayCounter));
              frmOSD.Left := Screen1.Left;
              frmOSD.Top := Screen1.Bottom - frmOSD.Height;
              frmOSD.Show;
            end;
          end
          else
            HotAction(hotActionStr);
        end;
      end

      else if(MPos.X <= Screen1.Right - 1)
      and (MPos.X > Screen1.Right - HotArea)
      and (MPos.Y <= Screen1.Bottom - 1)
      and (MPos.Y > Screen1.Bottom - HotArea) then
      begin
        if not OnHotSpot then
        begin
          OnHotSpot := True;
          //HotAction(frmTrayPopup.XCombo4.Caption);
          hotActionStr := frmTrayPopup.XCombo4.Caption;
          if Trim(hotActionStr) = '' then Exit;
          if not frmTrayPopup.XCheckbox1.Checked then Exit;
          // avoid usage if mouse is in use (buttons down e.g.)
          // if value is negative, it means is in use (aka held down)
          if (GetKeyState(VK_LBUTTON) < 0)
          or (GetKeyState(VK_MBUTTON) < 0)
          or (GetKeyState(VK_RBUTTON) < 0)
          then
            Exit;

          if frmAdvSettings.chkDelayGlobal.Checked or frmAdvSettings.chkDelayBotRight.Checked then
          begin
            hotActionDelay := StrToInt(frmAdvSettings.valDelayGlobal.Text);
            if frmAdvSettings.chkDelayBotRight.Enabled then
              hotActionDelay := StrToInt(frmAdvSettings.valDelayBotRight.Text);

            hotActionDelayCounter := 0;
            tmrDelay.Enabled := True;
            if frmAdvSettings.chkShowCount.Checked then
            begin
              frmOSD.DrawBubble(IntToStr(hotActionDelay - hotActionDelayCounter));
              frmOSD.Left := Screen1.Right - frmOSD.Width;
              frmOSD.Top := Screen1.Bottom - frmOSD.Height;
              frmOSD.Show;
            end;
          end
          else
            HotAction(hotActionStr);
        end;
      end

      else
      begin
        OnHotSpot := False;
        frmOSD.Hide;
      end;

    end;
  end;

{  if CurrentForegroundHwnd <> GetForegroundWindow then
  begin
    CurrentForegroundHwnd := GetForegroundWindow;
    Caption := GetProcessNameFromWnd(CurrentForegroundHwnd);
  end;}
end;

procedure TfrmMain.Iconito(var Msg: TMessage);
var
  coord: TPoint;
begin
  if Msg.LParam = WM_RBUTTONDOWN then
  begin
    GetCursorPos(coord);
{    if IsWindowVisible(Form2.Handle) then
      About1.Enabled := False
    else
      About1.Enabled := True;}
    frmTrayPopup.tmrTaskbarFocus.Enabled := False; // this will fix twice clicks on popup menu if form2 is visble
    frmTrayPopup.Close;
    //PopupMenu1.Popup(coord.X, coord.Y);
    // don't rush the popup, or it will show glitches on continuous creation
    if (GetTickCount64 - PrevSystrayTime) > 500 then
    begin
      PrevSystrayTime := GetTickCount64;
      ShowPopup;
    end;
    PostMessage(Handle, WM_NULL, 0, 0);
  end
  else if Msg.LParam = WM_LBUTTONDOWN then
  begin
    if not IsWindowVisible(frmTrayPopup.Handle) then
    begin
      fmxSettingsForm.Show;
//      frmTrayPopup.Show;
//      frmTrayPopup.Image1Click(frmTrayPopup);
    end
    else
      fmxSettingsForm.Focus;
//      fmxSettingsForm.Close;
//      frmTrayPopup.Close
  end;

end;

procedure TfrmMain.RegAutoStart(registerasrun: boolean);
var
  reg : TRegistry;
begin
  reg := TRegistry.Create;
  try
    reg.RootKey := HKEY_CURRENT_USER;
    reg.OpenKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Run', False);
    try
      if not registerasrun then
        reg.DeleteValue('WinXCorners')
      else
        reg.WriteString('WinXCorners',ParamStr(0));
    except
    end;
    reg.CloseKey;
  finally
    reg.Free;
  end;
end;

procedure TfrmMain.ShowPopup;
begin
  Visible := True;
  if Assigned(FSystray) then
  begin
    try
      FSystray.Close;
    except

    end;
   Sleep(100);
  end;

  try
    FSystray := TFormPopup.CreatePopup(Self, UPanel1, nil, Mouse.CursorPos.X, Mouse.CursorPos.Y, []);
  except
    if Assigned(FSystray) then
      FreeAndNil(FSystray);
  end;
  SwitchToThisWindow(FSystray.Handle, False);
end;

procedure TfrmMain.tmrDelayTimer(Sender: TObject);
begin
  Inc(hotActionDelayCounter);
  if hotActionDelay = hotActionDelayCounter then
  begin
    if OnHotSpot then
      HotAction(hotActionStr);
    frmOSD.Hide;
    tmrDelay.Enabled := False;
  end;
  frmOSD.DrawBubble(IntToStr(hotActionDelay - hotActionDelayCounter));
end;

procedure TfrmMain.tmrHotSpotTimer(Sender: TObject);
var
  MPos: TPoint;
//  Desk: HDESK;
  Cur: THandle;
begin

//  Desk := OpenInputDesktop(0, False, READ_CONTROL or DESKTOP_READOBJECTS);
//  if Desk <> NULL then
//  begin
    Cur := 0;
    try
      MPos := GetCursorXY; // Mouse.CursorPos;
      // LogonUI (Ctrl+Alt+Del) doesn't return GetForegroundWindow
      Cur := GetForegroundWindow;
    except
      Cur := 0;
//      CloseHandle(Desk);
      Exit;
    end;
    if cur = 0 then
     Exit;
//    CloseHandle(Desk);
//  end
//  else Exit;

  HotSpotAction(MPos);

end;

procedure TfrmMain.tmrShakeMouseTimer(Sender: TObject);
var
  MousePos: TPoint;
  NewDirection: TShakeDirection;
begin
  if not GetKeyState(VK_CONTROL)<0 then Exit;

  MousePos := GetCursorXY;

  if MousePos.X < FPrevMousePos.X then
    NewDirection := sdLeft
  else if MousePos.X > FPrevMousePos.X then
    NewDirection := sdRight
  else
    NewDirection := sdNone;

  if (NewDirection <> sdNone) and (NewDirection <> FShakeDirection) then
  begin
    FShakeDirection := NewDirection;
    Inc(FShakeCounter);
  end
  else if NewDirection = sdNone then
  begin
    FShakeCounter := 0;
  end;

  if not FShaking and (FShakeCounter >= MaxShakeCounter) then
  begin
    FShaking := True;
    HandleShaking(MousePos);
    FShakeCounter := 0;
  end;

  FPrevMousePos := MousePos;
end;

procedure TfrmMain.tmrSideGesturesTimer(Sender: TObject);
var
  mpos: TPoint;
  curTime: UInt64;
begin
  curTime := GetTickCount64;
  curTime := curTime - startTime;


  if not Winapi.Windows.GetCursorPos(mpos) then
    mpos := Point(110, 110);

  if (mpos.Y = 0) and not(isInArea) then
  begin
    // let's make it aware that is has been tapped one
    isInArea := True;
    if tapCounter = 0 then
      startTime := GetTickCount64;

    Inc(tapCounter);

    if (tapCounter = 2) and (curTime < INTERVAL) then
    begin
      tapCounter := 0; // reset counter
      // doaction
    end;

    if tapCounter = 2 then tapCounter := 0;
  end
  // clear counter if area is left
  else if (mpos.Y > 10) then
  begin
    if (curTime > INTERVAL) and (tapCounter = 1) then
      tapCounter := 0;
    isInArea := False;
  end;

end;

procedure TfrmMain.ulbExitClick(Sender: TObject);
begin
  ClosePopup;
  Close;
end;

procedure TfrmMain.ulbSettingsClick(Sender: TObject);
begin
  ClosePopup;
  frmAdvSettings.Show;
end;

procedure TfrmMain.ulbAboutClick(Sender: TObject);
begin
  ClosePopup;
{  frmTrayPopup.XCombo1.Visible := False;
  frmTrayPopup.XCombo2.Visible := False;
  frmTrayPopup.XCombo3.Visible := False;
  frmTrayPopup.XCombo4.Visible := False;
  frmTrayPopup.XCheckbox1.Visible := False;
  frmTrayPopup.XComboAsLabel.Visible := False;
  if not frmTrayPopup.Visible then
  frmTrayPopup.Show;
  frmTrayPopup.Image1.Visible := True;
  frmTrayPopup.Image1.Left := (frmTrayPopup.Width - frmTrayPopup.Image1.Width) div 2;
  frmTrayPopup.Image1.Top := (frmTrayPopup.Height - frmTrayPopup.Image1.Height) div 2;
}
  frmAdvSettings.Show;
  frmAdvSettings.ulbtnAboutClick(Self);
  frmAdvSettings.ulbtnAbout.Selected := True;
end;

procedure TfrmMain.ulbStartWithWindowsClick(Sender: TObject);
begin
  ClosePopup;
  if ulbStartWithWindows.FontIcon = '' then
  begin
    ulbStartWithWindows.FontIcon := '';
    RegAutoStart;
  end
  else
  begin
    ulbStartWithWindows.FontIcon := '';
    RegAutoStart(False)
  end;

end;

procedure TfrmMain.UpdateTrayIcon(grayed: boolean);
var
  toUpdate: Boolean;
begin
  if SystrayIcon = nil then
    SystrayIcon := TIcon.Create;

  if grayed then
    if SystemUsesLightTheme then
    SystrayIcon.Handle := LoadIcon(HInstance, 'Icon_1')
    else
    SystrayIcon.Handle := LoadIcon(HInstance, 'Icon_2')
  else
    if SystemUsesLightTheme then
    SystrayIcon.Handle := LoadIcon(HInstance, 'Icon_3')
    else
    SystrayIcon.Handle := LoadIcon(HInstance, 'Icon_1');

  toUpdate := False;
  if iconData.Wnd <> 0 then
    toUpdate := True;

  with iconData do
  begin
    cbSize := iconData.SizeOf;
    Wnd := Handle;
    uID := 100;
    uFlags := NIF_MESSAGE + NIF_ICON + NIF_TIP;
    uCallbackMessage := WM_USER + 1;
    hIcon := SysTrayIcon.Handle;
    StrCopy(szTip, 'WinXCorners');
  end;

  if toUpdate then
    Shell_NotifyIcon(NIM_MODIFY, @iconData)
  else
    Shell_NotifyIcon(NIM_ADD, @iconData);
end;


{procedure TfrmMain.WMCopyData(var Msg: TMessage);
var
  FMsg: PCopyDataStruct;
  Data: PMouseHookStruct;
begin
  Msg.Result := 0;
  FMsg := PCopyDataStruct(Msg.LParam);
  if FMsg = nil then
    Exit;

  Data := PMouseHookStruct(FMsg.lpData);
//  Str := String(UTF8String(PAnsiChar(FMsg^.lpData)));
//  MsgID := FMsg^.dwData;
//  case MsgID of
//    WM_MOUSE_COORDS:
//    begin
//
//    end;
//  end;

  frmTrayPopup.Label1.Caption := IntToStr(Data^.pt.X);
  Inc(Data^.pt.X);
  Inc(Data^.pt.Y);
  HotSpotAction(Data^.pt);

  Msg.Result := 1;
end;}

{-$DEFINE DELPHI_STYLE_SCALING}
procedure TfrmMain.WMDpiChanged(var Message: TMessage);
  {$IFDEF DELPHI_STYLE_SCALING}
  function FontHeightAtDpi(aDPI, aFontSize: integer): integer;
  var
    tmpCanvas: TCanvas;
  begin
    tmpCanvas := TCanvas.Create;
    try
      tmpCanvas.Handle := GetDC(0);
      tmpCanvas.Font.Assign(Self.Font);
      tmpCanvas.Font.PixelsPerInch := aDPI; // must be set before SIZE
      tmpCanvas.Font.Size := aFontSize;
      result := tmpCanvas.TextHeight('0');
    finally
      tmpCanvas.Free;
    end;
  end;
  {$ENDIF}
begin
  inherited;
  {$IFDEF DELPHI_STYLE_SCALING}
  ChangeScale(FontHeightAtDpi(LOWORD(Message.wParam), self.Font.Size), FontHeightAtDpi(self.PixelsPerInch, self.Font.Size));
  {$ELSE}
  ChangeScale(LOWORD(Message.wParam), self.PixelsPerInch);
  {$ENDIF}
  Self.PixelsPerInch := LOWORD(Message.WParam);
end;

procedure TfrmMain.WndProc(var Msg: TMessage);
var
  cur: HWND;
begin
  if Msg.Msg = wmTaskbarRestartMsg then
  begin
    Shell_NotifyIcon(NIM_ADD, @iconData);
  end;

  if Msg.Msg = WM_WTSSESSION_CHANGE then
  begin
    {TODO -oOwner -cGeneral : Improve enabling it after unlock if was manually disabled before lock}
    case Msg.WParam of
      WTS_SESSION_LOCK:
        begin
          if not frmTrayPopup.tempDisabled then
            frmTrayPopup.tempDisabled := True;
        end;
      WTS_SESSION_UNLOCK:
        begin
          frmTrayPopup.tempDisabled := False;
        end;
    end;
  end;

  if Msg.msg = WM_DISPLAYCHANGE then
  begin
    // update all to make it work on multimonitor if changed
    {TODO -oOwner -cGeneral : Improve to better detect restore functionality after monitor changes}
    cur := GetForegroundWindow;
    frmTrayPopup.Show;
    SetForegroundWindow(frmTrayPopup.Handle);
    sleep(10);
    frmTrayPopup.Hide;
    SetForegroundWindow(cur);
  end;

  inherited WndProc(Msg);
end;

procedure TfrmMain.actCtrlAltTabExecute(Sender: TObject);
begin
  FPrevHandle := GetForegroundWindow;
  if IsWindowVisible(wndListWindows.Handle) then
  begin
    SwitchToThisWindow(wndListWindows.Handle, False);
    Exit;
  end;

  // hide start menu if visible
  if IsStartMenuVisible then
  begin
    keybd_event(VK_LWIN, 0, 0, 0);
    keybd_event(VK_LWIN, 0, KEYEVENTF_KEYUP, 0);
  end;

  wndListWindows.Show;
  SwitchToThisWindow(wndListWindows.Handle, False);
  //exit;
//PerformCtrlAltTab; <~this is buggy
    keybd_event(VK_CONTROL,MapVirtualKey(VK_CONTROL,0),0,0);
//    Sleep(10);
    keybd_event(VK_MENU,MapVirtualKey(VK_MENU,0),0,0);
//    Sleep(10);
    keybd_event(VK_TAB,MapVirtualKey(VK_TAB,0),0,0);
    Sleep(10);
    keybd_event(VK_TAB,MapVirtualKey(VK_TAB,0),KEYEVENTF_KEYUP,0);
//    Sleep(100);
    keybd_event(VK_MENU,MapVirtualKey(VK_MENU,0),KEYEVENTF_KEYUP,0);
//    Sleep(100);
    keybd_event(VK_CONTROL,MapVirtualKey(VK_CONTROL,0),KEYEVENTF_KEYUP,0);
    Sleep(10);
// back
    keybd_event(VK_SHIFT,MapVirtualKey(VK_SHIFT,0),0,0);
//    Sleep(10);
    keybd_event(VK_TAB,MapVirtualKey(VK_TAB,0),0,0);
    Sleep(5);
    keybd_event(VK_TAB,MapVirtualKey(VK_TAB,0),KEYEVENTF_KEYUP,0);
//    Sleep(100);
    keybd_event(VK_SHIFT,MapVirtualKey(VK_SHIFT,0),KEYEVENTF_KEYUP,0);
//    PerformShiftTab;
    Sleep(100);
end;

procedure TfrmMain.actShowActionCenterSidebarExecute(Sender: TObject);
begin
  SwitchToThisWindow(Application.Handle, True);
  keybd_event(VK_LWIN,MapVirtualKey(VK_LWIN,0),0,0);
  Sleep(10);
  keybd_event(Ord('A'),MapVirtualKey(Ord('A'),0),0,0);
  Sleep(10);
  keybd_event(Ord('A'),MapVirtualKey(Ord('A'),0),KEYEVENTF_KEYUP,0);
  Sleep(100);
  keybd_event(VK_LWIN,MapVirtualKey(VK_LWIN,0),KEYEVENTF_KEYUP,0);
  Sleep(100);
end;

procedure TfrmMain.actShowDesktopExecute(Sender: TObject);
begin
  if FShellShowDesktopExists then
    ShellExecute(0, PChar('OPEN'), PChar('explorer.exe'), PChar('shell:::{3080F90D-D7AD-11D9-BD98-0000947B0257}'), nil, SW_SHOWNORMAL)
  else
  begin
    SwitchToThisWindow(Application.Handle, True);
    keybd_event(VK_LWIN,MapVirtualKey(VK_LWIN,0),0,0);
    Sleep(10);
    keybd_event(Ord('D'),MapVirtualKey(Ord('D'),0),0,0);
    Sleep(10);
    keybd_event(Ord('D'),MapVirtualKey(Ord('D'),0),KEYEVENTF_KEYUP,0);
    Sleep(100);
    keybd_event(VK_LWIN,MapVirtualKey(VK_LWIN,0),KEYEVENTF_KEYUP,0);
    Sleep(100);
  end;
end;

procedure TfrmMain.actShowStartMenuExecute(Sender: TObject);
begin
  Perform(WM_SYSCOMMAND, SC_TASKLIST, 0);
end;

procedure TfrmMain.actShowTaskViewExecute(Sender: TObject);
//const
//  TaskSwitch = $19B;
//var
//  taskbar: HWND;
//  pid: Cardinal;
begin

//  frmWinTiles.wndListWindows.Show;
//  fmxStageManager.Form1.Show;
//  exit;
//  taskbar := FindWindow('Shell_TrayWnd', nil);
//  if taskbar > 0 then
//  begin
////    GetWindowThreadProcessId(taskbar, @pid);
////    AllowSetForegroundWindow(pid);
//    PostMessage(taskbar, $111, TaskSwitch, 0);
//  end;
//  Exit;
  if FShellTaskViewExists then
    ShellExecute(0, PChar('OPEN'), PChar('explorer.exe'), PChar('shell:::{3080F90E-D7AD-11D9-BD98-0000947B0257}'), nil, SW_SHOWNORMAL)
  else // the old method which is hacky
  begin
    //this method works but ironically fails because it only works if app is elevated :V
    //GetWindowThreadProcessId(GetForegroundWindow, @procid);
    //if ProcessIsElevated(OpenProcess(PROCESS_ALL_ACCESS, False, procid)) then
      //SwitchToThisWindow(Application.Handle, True);

    //if GetForegroundWindow <> FindWindow('MultitaskingViewFrame','Vista Tareas') then
    if GetForegroundWindow <> FindWindow('MultitaskingViewFrame',nil) then
      SwitchToThisWindow(Application.Handle, True);

    keybd_event(VK_LWIN,MapVirtualKey(VK_LWIN,0),0,0);
    Sleep(10);
    keybd_event(VK_TAB,MapVirtualKey(VK_TAB,0),0,0);
    Sleep(10);
    keybd_event(VK_TAB,MapVirtualKey(VK_TAB,0),KEYEVENTF_KEYUP,0);
    Sleep(100);
    keybd_event(VK_LWIN,MapVirtualKey(VK_LWIN,0),KEYEVENTF_KEYUP,0);
    Sleep(100);
  end;
end;

procedure TfrmMain.AutoStartState;
var
  reg: TRegistry;
begin
  reg := TRegistry.Create;
  try
    reg.RootKey := HKEY_CURRENT_USER;
    reg.OpenKeyReadOnly('SOFTWARE\Microsoft\Windows\CurrentVersion\Run');
    try
    if reg.ReadString('WinXCorners')<> '' then
    begin
      ulbStartWithWindows.FontIcon := '';
    end;
    except
    end;
    reg.CloseKey;
  finally
    reg.Free;
  end;
end;

procedure TfrmMain.ClosePopup;
begin
  if Assigned(FSystray) then
    FSystray.Close;
  Visible := False;
end;

procedure TfrmMain.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  Params.WinClassName := 'WinXCorners';
end;

procedure TfrmMain.emporarydisabled1Click(Sender: TObject);
begin

end;

{ TScreens }

{constructor TScreens.Create(myRect: TRect);
begin
  rect := myRect;
end;}

end.
