# Rechten, GDAP en PIM

## Eenmalig: app en klanttenant

De Enterprise Application **CaptureTech Autopilot GDAP** moet in iedere
klanttenant bestaan en namens een klant-Global Administrator consent hebben voor:

- `DeviceManagementServiceConfig.Read.All`
- `DeviceManagementServiceConfig.ReadWrite.All`
- `Directory.Read.All`
- `Group.Read.All`
- `GroupMember.ReadWrite.All`

Zonder klantconsent verschijnt `AADSTS90099`. App-consent autoriseert alleen de
app; het vervangt GDAP niet.

## Tijdens gebruik

| Handeling | Actieve GDAP/PIM-rol |
| --- | --- |
| Profielen lezen, hardwarehash importeren en `-Assign` | Intune Administrator |
| Assignments, dynamische regels en nested groepen lezen | Groups Administrator |
| Een statische groep verwerken met `-AddToGroup` | Groups Administrator |

De technicus moet lid zijn van de security group achter de GDAP-relatie en de
vereiste PIM-activatie vóór het openen van de klanttenant activeren.

## Groepsregels

- Geen assignment: geen handmatige groepsactie.
- Dynamische group: geen `-AddToGroup`; Entra verwerkt de membership-regel.
- Statische security group: alleen een unieke kandidaat mag worden gekozen.
- Meerdere geldige statische kandidaten: de technicus kiest expliciet één groep.
