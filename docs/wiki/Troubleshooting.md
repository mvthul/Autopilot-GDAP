# Troubleshooting

## `AADSTS90099`

De Enterprise Application is nog niet in de klanttenant geautoriseerd. Laat een
Global Administrator van de klanttenant de consentflow afronden.

## `403 Forbidden` bij profielen of groepen

Controleer of de GDAP-relatie actief is en of het IT-Hulp-account de juiste
PIM-activatie heeft: minimaal Intune Administrator en, voor groepen, Groups
Administrator.

## Browsercallback werkt niet

Sluit andere toolinstanties en controleer of poort `8765` (Partner Center) of
`8766` (Graph) niet door een ander proces wordt gebruikt. De tool gebruikt de
systeembrowser en geen device code.

## Tauri-app start niet in OOBE

Controleer Windows x64, PowerShell 5.1+, internettoegang en WebView2 Evergreen.
Gebruik anders de WPF-fallback uit de [OOBE-pagina](OOBE).

## Registratie lijkt mislukt na een succesvolle import

Controleer de Autopilot-import en profilestatus in Intune. Bij dynamische groepen
kan Entra tijd nodig hebben om de membership-regel opnieuw te evalueren; de tool
voegt een apparaat nooit handmatig toe aan een dynamische groep.
