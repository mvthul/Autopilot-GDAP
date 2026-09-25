# CaptureTech Autopilot GDAP

Deze wiki beschrijft het veilig registreren van Windows-apparaten in een
klanttenant via GDAP, Microsoft Graph en Windows Autopilot.

## Snel beginnen

1. Controleer de [GDAP- en PIM-rechten](Permissions-and-GDAP).
2. Doe de eenmalige [app-inrichting](Installation-and-releases).
3. Gebruik in OOBE de [Tauri-app of WPF-fallback](OOBE).
4. Configureer voor CaptureTech-beheerde apparaten indien nodig de tijdelijke
   [MDE-allow voor v0.1.4](Temporary-MDE-Allow-v0.1.4).
5. Raadpleeg de [troubleshootingstappen](Troubleshooting) bij consent-, Graph-
   of groepsfouten.

## Belangrijke uitgangspunten

- De tool gebruikt alleen delegated toegang van het aangemelde IT-Hulp-account.
- De app wijzigt geen GDAP- of PIM-rollen.
- `-Online`, `-TenantId` en `-Assign` zijn verplicht voor een registratie.
- Dynamische groepen worden nooit handmatig gemuteerd. Een eenduidige
  `[OrderID]:tag`-regel levert automatisch `-GroupTag tag` tijdens registratie.
- `-AddToGroup` is uitsluitend toegestaan voor een unieke, geschikte statische
  security group.

De broncode, downloads en security policy staan in de
[hoofdrepository](https://github.com/mvthul/Autopilot-GDAP).
