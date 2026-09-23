# Autopilot GDAP Tool

WPF-tool voor IT-hulpmedewerkers om Windows Autopilot-apparaten via GDAP en Microsoft Graph aan klanttenants toe te voegen.

## Nieuwe CaptureTech desktop-app

Naast de bestaande PowerShell/WPF-tool staat er een moderne, portable Windows-desktop-app in [`tauri-app`](tauri-app). Deze gebruikt dezelfde browseraanmelding, delegated Graph-rechten en Autopilot-flow, maar heeft een CaptureTech-interface voor klantselectie, profielkeuze, groepsafhandeling, live voortgang en herstart.

De eerste Tauri-release is bedoeld voor Windows 10/11 x64 en vraagt altijd administratorrechten. De EXE is portable: installatie is niet nodig. Windows SmartScreen kan een waarschuwing tonen zolang de EXE niet code-signed is.

Benodigd op het apparaat:

- Windows PowerShell 5.1 of nieuwer;
- Microsoft Edge WebView2 Evergreen Runtime (standaard aanwezig op recente Windows 11-installaties);
- internettoegang naar Microsoft-aanmelding, Microsoft Graph, Partner Center en PSGallery;
- een actief GDAP/PIM-profiel volgens de rechtenmatrix hieronder.

### Lokale ontwikkeling

```powershell
cd .\tauri-app
npm install
npm run tauri dev
```

De browser-preview van `npm run dev` gebruikt veilige voorbeelddata. De werkelijke Microsoft-, Graph- en PowerShell-koppeling is alleen beschikbaar vanuit de gebouwde Tauri-desktopapp.

### Portable EXE publiceren

Een GitHub Actions-workflow bouwt de Windows x64-EXE op een Windows-runner. Publiceer een release door een tag in dit patroon te pushen:

```text
tauri-v0.1.0
```

De workflow voegt `capturetech-autopilot-gdap.exe` toe aan de bijbehorende GitHub Release. De huidige `Get-AutopilotGDAP.ps1` blijft beschikbaar als fallback voor OOBE, herstel en diagnose.

## Eerste inrichting

De tool gebruikt een eigen multi-tenant App Registration van IT-Hulp. Er worden geen secrets opgeslagen of gepubliceerd.

Voer de setup éénmalig uit op een beheerpc met Azure CLI en Global Administrator-rechten:

```powershell
irm "https://raw.githubusercontent.com/mvthul/Autopilot-GDAP/refs/heads/master/Setup-AutopilotApp.ps1" -OutFile .\Setup-AutopilotApp.ps1
.\Setup-AutopilotApp.ps1 -PartnerTenantId "<PARTNER-TENANT-ID>"
```

Het setupscript maakt een multi-tenant public-client app aan, configureert de delegated Graph-permissies, maakt de Enterprise Application aan en toont ook de Partner Center-consentlink voor de volledige klantenlijst. Er wordt geen client secret aangemaakt.

De tool gebruikt Partner Center `/v1/customers` voor de klantenlijst. Daardoor worden ook klanten zichtbaar die niet in Graph `/contracts` staan, zoals Hanab. Graph wordt daarna gebruikt voor Intune en Autopilot. De eerste keer zijn twee resource-aanmeldingen nodig: Graph en Partner Center.

De Partner Center-refresh-token wordt uitsluitend lokaal per Windows-gebruiker met DPAPI versleuteld opgeslagen. De eerste Partner Center-aanmelding gebruikt een normale browser met dezelfde Microsoft SSO-sessie als de Graph-aanmelding; device code wordt niet gebruikt. Op een nieuwe pc blijft een eerste browser-aanmelding per gebruiker vereist.

De huidige partner-app-client-id is al ingevuld in `Get-AutopilotGDAP.ps1`. Als je een nieuwe app aanmaakt, vervang je daar de waarde bij `PublicClientId` en publiceer je die versie. De runtime-tool vraagt op andere computers alleen nog om de IT-hulp-login.

Iedere klanttenant moet afzonderlijk admin consent geven. GDAP/PIM blijft vereist; app-consent verleent geen Intune-rol.

## Benodigde rechten

De tool werkt met **delegated permissions**: de app geeft dus nooit zelfstandig toegang. De aangemelde IT-Hulp-gebruiker moet op het moment van uitvoeren via een actieve GDAP/PIM-toewijzing rechten hebben in de geselecteerde klanttenant.

### Eenmalig: partner-tenant en app-inrichting

| Onderdeel | Minimale rol / vereiste | Waarvoor |
| --- | --- | --- |
| Uitvoeren van `Setup-AutopilotApp.ps1` | Global Administrator in de IT-Hulp partner-tenant | Multi-tenant app registreren, delegated permissions configureren en partner-consent geven. |
| Partner Center-klantenlijst | Partner Center-rol die klanten mag bekijken, normaal **Admin agent** | De klantlijst ophalen via Partner Center. |
| Eerste Partner Center-consent | Een account dat Partner Center-consent mag verlenen | Eenmalige browserconsent voor `user_impersonation`; daarna gebruikt iedere technicus zijn eigen lokale, versleutelde token. |

De app vraagt uitsluitend deze delegated Microsoft Graph-scopes aan:

- `DeviceManagementServiceConfig.Read.All`
- `DeviceManagementServiceConfig.ReadWrite.All`
- `Directory.Read.All`
- `Group.Read.All`
- `GroupMember.ReadWrite.All`

### Eenmalig per klanttenant: app autoriseren

De Enterprise Application **CaptureTech Autopilot GDAP** moet in iedere klanttenant bestaan en admin consent hebben voor de bovenstaande Graph-scopes. Hiervoor is een **Global Administrator van de klanttenant** nodig. Dit is noodzakelijk vóór een GDAP-beheerder de app in die klant kan gebruiken; zonder deze stap verschijnt `AADSTS90099`.

> App-consent vervangt GDAP niet. Het autoriseert de applicatie; de handelingen blijven namens de aangemelde partnergebruiker en diens GDAP-rollen plaatsvinden.

### Tijdens gebruik: IT-Hulp-account / GDAP-PIM in de klanttenant

| Functie in deze tool | Minimale actieve GDAP-rol in de klanttenant |
| --- | --- |
| Autopilot-profielen lezen, apparaat importeren en `-Assign` uitvoeren | **Intune Administrator** |
| Toegewezen groepen, dynamische query’s en nested groepen lezen | **Groups Administrator** |
| Apparaat via `-AddToGroup` aan een statische groep toevoegen | **Groups Administrator** |

Praktisch betekent dit:

1. De GDAP-relatie met de klant moet actief zijn én minimaal **Intune Administrator** en **Groups Administrator** bevatten.
2. Het IT-Hulp-account moet lid zijn van de security group waarop deze GDAP-relatie is gebaseerd.
3. Wanneer die group PIM-managed is, moet de technicus de juiste PIM-activatie vóór stap 2 van de tool uitvoeren.
4. Voor een profiel zonder statische groepsactie is alleen **Intune Administrator** nodig; voor een dynamische groep wordt nooit handmatig membership gewijzigd.

Groepen die niet door Groups Administrator beheerd kunnen worden (bijvoorbeeld role-assignable groups, of groepen waarvoor klantbeleid aanvullende beperkingen oplegt) worden niet automatisch aangepast. Gebruik hiervoor een expliciet geautoriseerde beheerdersroute.

## Gebruik tijdens Windows Setup

1. Druk in OOBE op `Shift + F10`.
2. Start PowerShell.
3. Voer uit:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
irm "https://raw.githubusercontent.com/mvthul/Autopilot-GDAP/refs/heads/master/Get-AutopilotGDAP.ps1" | iex
```

4. Meld aan met het IT-hulpaccount.
5. Bevestig bij eerste gebruik ook de Partner Center-browseraanmelding. De setup registreert hiervoor `http://localhost:8765/` als loopback redirect.
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
