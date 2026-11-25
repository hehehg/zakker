[Setup]
AppId={{B7E2C1A4-5D3F-4F8A-9C21-7A6E0D4B1F32}
AppName=Zakker
AppVersion=1.0
DefaultDirName={autopf}\Zakker
DefaultGroupName=Zakker
OutputDir=..\dist
OutputBaseFilename=zakker-windows-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\Zakker"; Filename: "{app}\zakker.exe"
Name: "{autodesktop}\Zakker"; Filename: "{app}\zakker.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\zakker.exe"; Description: "Launch Zakker"; Flags: nowait postinstall skipifsilent
