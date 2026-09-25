# Tijdelijke MDE-allow voor Tauri v0.1.4

> Deze procedure is uitsluitend een tijdelijke CaptureTech-route totdat een
> publiek code-signed release beschikbaar is. Zij maakt van de EXE geen
> ondertekende Windows-publisher.

## Scope en vaste waarden

Voer deze stappen uit in de **CaptureTech.com** Microsoft Defender XDR-tenant.
De MDE-scope is apparaatgericht; kies daarom **All devices**. Daarmee ontvangen
alle CaptureTech-beheerde apparaten de uitzondering, onafhankelijk van de
aangemelde gebruiker.

| Waarde | Inhoud |
| --- | --- |
| Release | `tauri-v0.1.4` |
| Directe EXE-URL | `https://github.com/mvthul/Autopilot-GDAP/releases/download/tauri-v0.1.4/capturetech-autopilot-gdap.exe` |
| SHA-256 | `62a0570d9d93f25d4e7e8297e37c4242f5a06024554201727661c732adf02e46` |
| Vervaldatum | Geen; verwijder de uitzondering zodra een Public Trust-signed release is gevalideerd. |

Gebruik bewust **niet** `releases/latest/download`, een domeinregel voor
`github.com`, `objects.githubusercontent.com` of een algemene `.exe`-allow.
Daarmee zouden ook toekomstige of niet-gerelateerde downloads ruimere toegang
krijgen.

## Defender XDR: URL- en file-indicatoren

1. Meld je aan bij [Microsoft Defender XDR](https://security.microsoft.com) en
   controleer rechtsboven dat de directory **CaptureTech.com** actief is.
2. Open **Settings > Endpoints > Advanced features** en schakel **Custom
   network indicators** in wanneer deze nog niet actief is.
3. Open **Settings > Endpoints > Indicators > URLs/Domains** en voeg een item
   toe met de exacte EXE-URL uit de tabel.
   - Kies actie **Allowed**.
   - Kies scope **All devices**.
   - Stel geen vervaldatum in.
   - Noteer dat dit een tijdelijke `tauri-v0.1.4`-uitzondering is.
4. Open **Settings > Endpoints > Indicators > File hashes** en voeg de
   SHA-256 uit de tabel toe.
   - Kies actie **Allowed**.
   - Kies scope **All devices**.
   - Stel geen vervaldatum in.

De importtemplate
[`capturetech-autopilot-gdap-v0.1.4-indicators.csv`](../mde/capturetech-autopilot-gdap-v0.1.4-indicators.csv)
bevat beide verplichte indicatorwaarden. Importeer hem via **Indicators >
Import** en controleer vervolgens per item de actie, de scope **All devices**
en de ontbrekende vervaldatum. De CSV bevat bewust geen device-scope: die wordt
in Defender XDR expliciet gecontroleerd tijdens of na de import.

URL-indicatoren kunnen tijd nodig hebben om door te werken. Houd rekening met
maximaal 48 uur, al werkt dit normaal eerder. File-indicatoren kunnen gemiddeld
binnen een half uur, maar uiterlijk binnen enkele uren actief zijn.

## Intune: file-hashberekening inschakelen

Maak in de **CaptureTech.com** Intune-tenant een nieuw Windows
Settings-catalogprofiel en configureer Microsoft Defender Antivirus:

| Instelling | Waarde | Toewijzing |
| --- | --- | --- |
| `Enable File Hash Computation` | Enabled | All devices |

Deze computerinstelling zorgt dat Defender de SHA-256 file-indicator
betrouwbaar kan toepassen. Controleer in Intune dat de policy op de bedoelde
Windows-apparaten als geslaagd rapporteert.

## Controleren op een beheerd Windows-apparaat

1. Download in Microsoft Edge uitsluitend vanaf de directe URL in de tabel.
2. Vergelijk de gedownloade EXE met de verwachte SHA-256:

```powershell
$expectedHash = '62a0570d9d93f25d4e7e8297e37c4242f5a06024554201727661c732adf02e46'
$actualHash = (Get-FileHash -LiteralPath "$env:USERPROFILE\Downloads\capturetech-autopilot-gdap.exe" -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $expectedHash) { throw "Onverwachte EXE-hash: $actualHash" }
```

3. Start de app en bevestig dat Edge en Defender de download niet blokkeren.
4. **Verwacht gedrag:** de app is nog niet code-signed. Windows/UAC kan dus
   tijdelijk **Unknown publisher** tonen. Een MDE-allow is geen vervanging voor
   een Authenticode-handtekening.

Als de download na de exacte URL-indicator toch wordt geblokkeerd door de
GitHub-CDN-redirect, breid de uitzondering dan niet uit naar een GitHub-domein.
Gebruik in dat geval een beheerde Intune Win32-distributie totdat Public Trust
signing beschikbaar is.

## Opruimen

Nadat een Public Trust-signed release op een schoon Windows-apparaat is
geverifieerd:

1. verwijder de URL-indicator;
2. verwijder de SHA-256 file-indicator;
3. verwijder of zet het Intune-profiel voor file-hashberekening terug volgens
   het CaptureTech Defender-baselinebeleid;
4. archiveer deze tijdelijke procedure samen met de releasevalidatie.
