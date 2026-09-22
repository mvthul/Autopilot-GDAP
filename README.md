# Autopilot GDAP Tool

WPF-tool voor IT-hulpmedewerkers om Windows Autopilot-apparaten via GDAP en Microsoft Graph aan klanttenants toe te voegen.

## Eerste inrichting

De tool gebruikt een eigen multi-tenant App Registration van IT-Hulp. Er worden geen secrets opgeslagen of gepubliceerd.

Voer de setup éénmalig uit op een beheerpc met Azure CLI en Global Administrator-rechten:

```powershell
irm "https://raw.githubusercontent.com/mvthul/Autopilot-GDAP/refs/heads/master/Setup-AutopilotApp.ps1" -OutFile .\Setup-AutopilotApp.ps1
.\Setup-AutopilotApp.ps1 -PartnerTenantId "<PARTNER-TENANT-ID>"
```

Het setupscript maakt een multi-tenant public-client app aan, configureert de delegated Graph-permissies, maakt de Enterprise Application aan en opent de admin-consentpagina. Er wordt geen client secret aangemaakt.

De app gebruikt `Directory.Read.All` voor het uitlezen van klantrelaties via `/contracts`; de aangemelde beheerder heeft hiervoor een ondersteunde directoryrol nodig.

De huidige partner-app-client-id is al ingevuld in `Get-AutopilotGDAP.ps1`. Als je een nieuwe app aanmaakt, vervang je daar de waarde bij `PublicClientId` en publiceer je die versie. De runtime-tool vraagt op andere computers alleen nog om de IT-hulp-login.

Iedere klanttenant moet afzonderlijk admin consent geven. GDAP/PIM blijft vereist; app-consent verleent geen Intune-rol.

## Gebruik tijdens Windows Setup

1. Druk in OOBE op `Shift + F10`.
2. Start PowerShell.
3. Voer uit:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
irm "https://raw.githubusercontent.com/mvthul/Autopilot-GDAP/refs/heads/master/Get-AutopilotGDAP.ps1" | iex
```

4. Meld aan met het IT-hulpaccount.
5. Gebruik het zoekveld boven de klantlijst om bijvoorbeeld `Hanab` te zoeken. De lijst wordt volledig geladen via Graph-paginering.
6. Selecteer de klanttenant en verbind met de klantcontext.
7. Geef klantconsent wanneer de tool daarom vraagt.
8. Selecteer het Autopilot-profiel en registreer het apparaat.
9. Vink desgewenst aan dat het apparaat na import aan de toegewezen groep moet worden toegevoegd.

## Beveiliging

- Geen client secrets, wachtwoorden of tokens in GitHub.
- Alleen delegated permissions; geen app-only toegang.
- Geen automatische appregistratie of verborgen bootstrap-account.
- PIM/GDAP-rollen worden niet door de tool gewijzigd.
