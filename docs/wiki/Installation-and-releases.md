# Installatie en releases

## Eenmalige partnerinrichting

Voer op een beheerpc met Azure CLI en Global Administrator-rechten uit:

```powershell
irm "https://raw.githubusercontent.com/mvthul/Autopilot-GDAP/refs/heads/master/Setup-AutopilotApp.ps1" -OutFile .\Setup-AutopilotApp.ps1
.\Setup-AutopilotApp.ps1 -PartnerTenantId "<PARTNER-TENANT-ID>"
```

Geef daarna klantconsent per klanttenant en controleer de GDAP/PIM-activatie.

## Portable Tauri-release

Een tag in de vorm `tauri-v*` start de Windows x64-build. De workflow publiceert
de portable `capturetech-autopilot-gdap.exe` aan de GitHub Release. De EXE is
nog niet code-signed; controleer daarom altijd release, tag en checksum.

### Tijdelijke CaptureTech-managed uitzondering

Zolang Public Trust code signing nog niet beschikbaar is, is alleen
`tauri-v0.1.4` gericht toegestaan op CaptureTech-beheerde apparaten. Volg
hiervoor de [tijdelijke MDE-allowprocedure](Temporary-MDE-Allow-v0.1.4). Deze
regeling gebruikt een exacte release-URL en SHA-256, is geen generieke
GitHub-allowlist en maakt de EXE niet code-signed.

## Ontwikkelen

```powershell
cd .\tauri-app
npm install
npm run tauri dev
```

De browserpreview gebruikt demodata. Alleen de Tauri-desktopapp start de
PowerShell-worker en de echte Microsoft-aanmeldingen.
