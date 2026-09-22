# Autopilot GDAP Tool

WPF-tool voor IT-hulpmedewerkers om Windows Autopilot-apparaten via GDAP en Microsoft Graph aan klanttenants toe te voegen.

## Eerste inrichting

De tool gebruikt een eigen multi-tenant App Registration van IT-Hulp. Er worden geen secrets opgeslagen of gepubliceerd.

Voer de setup éénmalig uit op een beheerpc met Azure CLI en Global Administrator-rechten:

```powershell
irm "https://raw.githubusercontent.com/mvthul/Autopilot-GDAP/refs/heads/master/Setup-AutopilotApp.ps1" -OutFile .\Setup-AutopilotApp.ps1
.\Setup-AutopilotApp.ps1 -PartnerTenantId "<PARTNER-TENANT-ID>"
```

Het setupscript maakt een multi-tenant public-client app aan, configureert de delegated Graph-permissies, maakt de Enterprise Application aan en toont ook de Partner Center-consentlink voor de volledige klantenlijst. Er wordt geen client secret aangemaakt.

De tool gebruikt Partner Center `/v1/customers` voor de klantenlijst. Daardoor worden ook klanten zichtbaar die niet in Graph `/contracts` staan, zoals Hanab. Graph wordt daarna gebruikt voor Intune en Autopilot. De eerste keer zijn twee resource-aanmeldingen nodig: Graph en Partner Center.

De Partner Center-refresh-token wordt uitsluitend lokaal per Windows-gebruiker met DPAPI versleuteld opgeslagen. Daardoor verschijnt de Partner Center-device-code op dezelfde pc niet bij iedere volgende start opnieuw. Op een nieuwe pc blijft een eerste aanmelding per gebruiker vereist.

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
5. Bevestig bij eerste gebruik ook de Partner Center-device-code-aanmelding.
6. Gebruik het zoekveld boven de klantlijst om bijvoorbeeld `Hanab` te zoeken. De lijst komt uit Partner Center. Elke keuze toont nu de klantnaam, het primaire tenantdomein en de tenant-ID; dubbele klantnamen zijn daardoor herkenbaar.
7. Selecteer de klanttenant en verbind met de klantcontext.
8. Geef klantconsent wanneer de tool daarom vraagt.
9. Selecteer het Autopilot-profiel en registreer het apparaat. De tool geeft altijd `-Online`, `-TenantId` en `-Assign` door aan de Community-scriptflow.
10. Statische profielgroepen worden automatisch via `-AddToGroup` verwerkt; dynamische groepen worden alleen gecontroleerd en nooit handmatig gemuteerd.
11. Bekijk de live uitvoer in de console en het WPF-logvenster. De rebootknop wordt pas na succesvolle import en assignment actief.

## Beveiliging

- Geen client secrets, wachtwoorden of tokens in GitHub.
- Alleen delegated permissions; geen app-only toegang.
- Geen automatische appregistratie of verborgen bootstrap-account.
- PIM/GDAP-rollen worden niet door de tool gewijzigd.
