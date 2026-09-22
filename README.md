# Autopilot GDAP Tool voor MSP's

Een GUI gebaseerde PowerShell tool ontwikkeld voor IT-Hulp / Partner dienstverleners om veilig, snel en efficiënt Windows apparaten (tijdens OOBE) toe te voegen aan Microsoft Intune (Autopilot) van klanten, met behulp van Microsoft Graph en GDAP.

## Voordelen
* **Geen eigen App Registraties nodig:** Maakt gebruik van de public/built-in Microsoft Graph Command Line Tools Client-ID. Zero secrets!
* **Volledig Grafisch (WPF):** Geen commando's of typfouten tijdens de Windows Out-of-Box Experience (OOBE).
* **Multi-Tenant (GDAP):** Log één keer in, haal al je klanten op, selecteer de klant en koppel de hardware hash.
* **Auto-Consent Fix:** Als de Graph-app nog nooit in de klant-tenant is gebruikt, maakt het script op de achtergrond slim een Service Principal aan en opent de browser om eenmalig toestemming (Admin Consent) te vragen.
* **Auto-Groep Toewijzing:** Herkent de toegewezen Autopilot Entra ID / Microsoft 365 groepen en toont deze ter referentie in de GUI.

## Hoe te gebruiken (Tijdens Windows Setup)

Start een computer op (uit de doos) en wacht tot je in het allereerste Windows welkomstscherm komt (Selecteer je land).

1. Druk op `Shift + F10` om de Command Prompt te openen.
2. Controleer of de computer internet heeft.
3. Typ `powershell` en druk op Enter.
4. Voer het volgende snelle installatiecommando in:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; irm https://raw.githubusercontent.com/mvthul/Autopilot-GDAP/main/Get-AutopilotGDAP.ps1 | iex
```

## Wat gebeurt er dan?

1. De WPF interface opent in de CaptureTech huisstijl.
2. Klik op **1. Log in met IT-Hulp Account**. Log in met je Partner werkaccount.
3. De lijst met al jullie tenants/klanten verschijnt. Selecteer de juiste klant (bijv. *CaptureTech* of *ValueBlue*).
4. Klik op **2. Verbind met Klant**.
   * *Edge Case:* Mocht dit de allereerste keer zijn bij deze specifieke klant, dan zal de browser zich openen en vragen om een Admin goedkeuring. Laat een Global Admin deze éénmalig per klant aftekenen. Klik hierna gewoon nogmaals op de knop!
5. Kies het juiste Autopilot-profiel.
6. Klik op **3. Registreer dit apparaat**.

De tool vraagt lokaal de unieke Hardware Hash (WMI) op, uploadt deze veilig naar Intune via de Graph API, verzoekt een synchronisatie en geeft de computer een seintje als het gereed is. Rebooten en Autopilot neemt het over!
