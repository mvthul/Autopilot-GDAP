# Autopilot GDAP Tool

WPF-tool voor IT-hulpmedewerkers om Windows Autopilot-apparaten via GDAP en Microsoft Graph aan klanttenants toe te voegen.

## Eerste inrichting

De tool gebruikt een eigen multi-tenant App Registration van IT-Hulp. Er worden geen secrets opgeslagen of gepubliceerd.

Maak éénmalig in de partner-tenant een app met:

- Naam: `CaptureTech Autopilot GDAP`
- Accounts: accounts in any organizational directory (multi-tenant)
- Public client/device-code flow: ingeschakeld
- Geen client secret

Voeg deze delegated Microsoft Graph-permissies toe:

- `DeviceManagementServiceConfig.ReadWrite.All`
- `DeviceManagementServiceConfig.Read.All`
- `Group.Read.All`
- `GroupMember.ReadWrite.All`
- `Organization.Read.All`

Geef admin consent in de partner-tenant. Start daarna de tool, plak de **Application (client) ID** in het configuratievak en klik op **Opslaan en controleren**.

De tool bewaart uitsluitend de publieke client-id lokaal in:

```text
%LOCALAPPDATA%\CaptureTech\AutopilotGDAP\config.json
```

Iedere klanttenant moet afzonderlijk admin consent geven. GDAP/PIM blijft vereist; app-consent verleent geen Intune-rol.

## Gebruik tijdens Windows Setup

1. Druk in OOBE op `Shift + F10`.
2. Start PowerShell.
3. Voer uit:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
irm "https://raw.githubusercontent.com/mvthul/Autopilot-GDAP/refs/heads/master/Get-AutopilotGDAP.ps1?v=9d54906" | iex
```

4. Configureer bij eerste gebruik de eigen client-id.
5. Meld aan met het IT-hulpaccount.
6. Selecteer de klanttenant en verbind met de klantcontext.
7. Geef klantconsent wanneer de tool daarom vraagt.
8. Selecteer het Autopilot-profiel en registreer het apparaat.
9. Vink desgewenst aan dat het apparaat na import aan de toegewezen groep moet worden toegevoegd.

## Beveiliging

- Geen client secrets, wachtwoorden of tokens in GitHub.
- Alleen delegated permissions; geen app-only toegang.
- Geen automatische appregistratie of verborgen bootstrap-account.
- PIM/GDAP-rollen worden niet door de tool gewijzigd.
