# OOBE: apparaat registreren

Open tijdens Windows Setup een verhoogde PowerShell met `Shift + F10`.

## Tauri-app (aanbevolen)

```powershell
$exe = Join-Path $env:TEMP "CaptureTech-Autopilot-GDAP.exe"
irm "https://github.com/mvthul/Autopilot-GDAP/releases/latest/download/capturetech-autopilot-gdap.exe" -OutFile $exe
Start-Process -FilePath $exe
```

De portable app heeft Windows 10/11 x64, PowerShell 5.1+ en WebView2 Evergreen
nodig. Meld aan in de browser met het IT-Hulp-account; device code en WAM worden
niet gebruikt.

## WPF-fallback

Gebruik deze route wanneer WebView2 ontbreekt of wanneer gerichte diagnose nodig
is:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
irm "https://raw.githubusercontent.com/mvthul/Autopilot-GDAP/refs/heads/master/Get-AutopilotGDAP.ps1" | iex
```

## Daarna

1. Kies de klant uit Partner Center.
2. Verbind met de klanttenant en rond, indien gevraagd, klantconsent af.
3. Kies een Autopilot-profiel.
4. Kies alleen een statische groepskandidaat wanneer de tool daarom vraagt.
5. Registreer het apparaat en wacht op import en profieltoewijzing.
6. Herstart pas wanneer de app dat na succesvolle afronding toestaat.
