; Instalador de Aurora (Inno Setup 6, gratuito).
; Uso: iscc /DAppVersion=1.2.3 /DSourceDir=<carpeta Aurora-Windows> /DOutputDir=<salida> installer\aurora.iss
; SourceDir es la carpeta que genera scripts/package_windows.ps1 (exe + DLL + data + tools).
#ifndef AppVersion
  #error Define /DAppVersion=x.y.z
#endif
#ifndef SourceDir
  #error Define /DSourceDir=<carpeta del paquete>
#endif
#ifndef OutputDir
  #define OutputDir "..\dist"
#endif

[Setup]
; AppId fijo: permite que una versión nueva se instale sobre la anterior.
AppId={{6F1C2B7E-5A3D-4E8B-9C41-A0D7E2B53F10}
AppName=Aurora Music
AppVersion={#AppVersion}
AppPublisher=Aurora
; Sin UAC: se instala por usuario. Las actualizaciones silenciosas no piden elevación.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\Aurora
DefaultGroupName=Aurora
DisableProgramGroupPage=yes
UsePreviousAppDir=yes
OutputDir={#OutputDir}
OutputBaseFilename=Aurora-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Cierra Aurora si sigue abierta (la app ya se cierra sola antes de lanzar el instalador).
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\aurora_music.exe

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\Aurora"; Filename: "{app}\aurora_music.exe"
Name: "{autodesktop}\Aurora"; Filename: "{app}\aurora_music.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Crear un acceso directo en el escritorio"; Flags: unchecked

[Run]
; Instalación normal: casilla «Abrir Aurora». Silenciosa (actualización): relanza siempre.
Filename: "{app}\aurora_music.exe"; Description: "Abrir Aurora"; Flags: nowait postinstall skipifsilent
Filename: "{app}\aurora_music.exe"; Flags: nowait; Check: WizardSilent
