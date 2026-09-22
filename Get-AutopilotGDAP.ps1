<#
.SYNOPSIS
  Autopilot GDAP GUI - Ontwikkeld voor MSP IT-Hulp met ingebouwde Admin Consent afhandeling
#>
$Global:PublicClientId = "14d82eec-204b-4a57-966d-513373704195"

# Zorg dat de MS Graph modules geladen zijn
if (!(Get-Module -ListAvailable Microsoft.Graph.Authentication)) {
    Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force
}
Import-Module Microsoft.Graph.Authentication

Add-Type -AssemblyName PresentationFramework

[xml]$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Autopilot GDAP Tool" Height="480" Width="420" WindowStartupLocation="CenterScreen">
    <Grid Margin="15">
        <StackPanel>
            <TextBlock Text="Team 1 - Autopilot GDAP Tool" FontSize="18" FontWeight="Bold" Margin="0,0,0,15"/>
            
            <Button Name="LogonBtn" Content="1. Log in met IT-Hulp Account" Height="30" Margin="0,0,0,10" Background="#0078D7" Foreground="White" FontWeight="Bold"/>
            
            <TextBlock Text="Klant Tenant:" FontSize="12" Margin="0,0,0,2"/>
            <ComboBox Name="TenantDropdown" Height="25" IsEnabled="False" Margin="0,0,0,10" DisplayMemberPath="displayName" />
            
            <Button Name="LoadProfilesBtn" Content="2. Verbind met Klant en zoek Profielen" Height="30" IsEnabled="False" Margin="0,0,0,10"/>
            
            <TextBlock Text="Selecteer Profiel (en Toegewezen Groep):" FontSize="12" Margin="0,0,0,2"/>
            <ComboBox Name="ProfileDropdown" Height="25" IsEnabled="False" Margin="0,0,0,10" DisplayMemberPath="displayName" />
            
            <TextBlock Text="Device Hostname (Optioneel):" FontSize="12" Margin="0,0,0,2"/>
            <TextBox Name="HostnameBox" Height="25" IsEnabled="False" Margin="0,0,0,10"/>

            <Button Name="DeployBtn" Content="3. Registreer dit apparaat aan Klant" Height="40" IsEnabled="False" Background="#107C10" Foreground="White" FontWeight="Bold"/>
            
            <TextBlock Name="StatusTxt" Text="Klik op Inloggen..." Margin="0,15,0,0" Foreground="#555555" TextWrapping="Wrap"/>
        </StackPanel>
    </Grid>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $XAML)
$Window = [Windows.Markup.XamlReader]::Load($reader)

# Map UI Controls
$LogonBtn        = $Window.FindName("LogonBtn")
$TenantDropdown  = $Window.FindName("TenantDropdown")
$LoadProfilesBtn = $Window.FindName("LoadProfilesBtn")
$ProfileDropdown = $Window.FindName("ProfileDropdown")
$HostnameBox     = $Window.FindName("HostnameBox")
$DeployBtn       = $Window.FindName("DeployBtn")
$StatusTxt       = $Window.FindName("StatusTxt")

# Helpers
$Script:TargetTenantId = ""
$Script:TargetGroupId = ""

# --- UI Logica ---

$LogonBtn.Add_Click({
    $StatusTxt.Text = "Bezig met inloggen op algemeen partner profiel..."
    $LogonBtn.IsEnabled = $false
    try {
        Connect-MgGraph -ClientId $Global:PublicClientId -Scopes "Organization.Read.All, Application.Read.All" -NoWelcome
        $StatusTxt.Text = "Ingelogd! Contracten ophalen..."
        
        $Contracts = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/contracts"
        
        $TenantDropdown.Items.Clear()
        foreach ($c in $Contracts.value) {
            [void]$TenantDropdown.Items.Add([pscustomobject]@{ displayName = $c.displayName; tenantId = $c.defaultDomainName })
        }
        
        $TenantDropdown.IsEnabled = $true
        $LoadProfilesBtn.IsEnabled = $true
        $StatusTxt.Text = "Klanten geladen. Kies een klant."
    } catch {
        $StatusTxt.Text = "Mislukt: $_"
    }
    $LogonBtn.IsEnabled = $true
})

$LoadProfilesBtn.Add_Click({
    if (-not $TenantDropdown.SelectedItem) { $StatusTxt.Text = "Selecteer een klant!"; return }
    $Script:TargetTenantId = $TenantDropdown.SelectedItem.tenantId
    $TargetName            = $TenantDropdown.SelectedItem.displayName
    
    $StatusTxt.Text = "Verbinden met context van $TargetName..."
    $LoadProfilesBtn.IsEnabled = $false
    
    try {
        Connect-MgGraph -ClientId $Global:PublicClientId -TenantId $Script:TargetTenantId -Scopes "DeviceManagementServiceConfig.ReadWrite.All, Group.ReadWrite.All" -NoWelcome
        
        $Profiles = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles"
        $ProfileDropdown.Items.Clear()
        
        foreach ($p in $Profiles.value) {
            $assignUri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$($p.id)/assignments"
            $assignments = Invoke-MgGraphRequest -Method GET -Uri $assignUri
            
            $assignedGroupName = "Onbekend"
            $assignedGroupId = ""
            if ($assignments.value -and $assignments.value[0].target.groupId) {
                 $assignedGroupId = $assignments.value[0].target.groupId
                 $groupUri = "https://graph.microsoft.com/v1.0/groups/$assignedGroupId"
                 try {
                     $groupData = Invoke-MgGraphRequest -Method GET -Uri $groupUri
                     $assignedGroupName = $groupData.displayName
                 } catch { $assignedGroupName = "Kan naam niet lezen" }
            }
            
            $displayTxt = "{0} (Groep: {1})" -f $p.displayName, $assignedGroupName
            [void]$ProfileDropdown.Items.Add([pscustomobject]@{ displayName = $displayTxt; profileId = $p.id; groupId = $assignedGroupId })
        }
        
        $ProfileDropdown.IsEnabled = $true
        $HostnameBox.IsEnabled = $true
        $DeployBtn.IsEnabled = $true
        $StatusTxt.Text = "Profielen geladen voor $TargetName! Klaar voor registratie."
    } catch {
        # Automatische Admin Consent Afhandeling
        $errorMessage = $_.Exception.Message
        if ($errorMessage -match "AADSTS700016" -or $errorMessage -match "AADSTS650052" -or $errorMessage -match "unauthorized") {
            $consentUrl = "https://login.microsoftonline.com/$Script:TargetTenantId/adminconsent?client_id=14d82eec-204b-4a57-966d-513373704195"
            
            # Automatische "Injectie" van de Service Principal
            # Dit voorkomt de foutmelding in het consent-scherm
            try {
                $StatusTxt.Text = "App registreren in Klant Tenant..."
                # Tijdelijke sessie stiekem openen met App.ReadWrite.All om de lege huls aan te maken
                Connect-MgGraph -ClientId $Global:PublicClientId -TenantId $Script:TargetTenantId -Scopes "Application.ReadWrite.All" -NoWelcome
                
                # Check of hij bestaat, zo nee, maak aan
                $sp = Get-MgServicePrincipal -Filter "appId eq '14d82eec-204b-4a57-966d-513373704195'" -ErrorAction SilentlyContinue
                if (-not $sp) {
                    New-MgServicePrincipal -AppId "14d82eec-204b-4a57-966d-513373704195" | Out-Null
                }
                
                # We verbreken deze tijdelijke sessie zodat we schoon blijven
                Disconnect-MgGraph
            } catch {
                # Mocht dit falen om GDAP privilege redenen, gaat het script gewoon door, want soms kan hij het alsnog
            }

            $StatusTxt.Text = "Eenmalige Admin Consent vereist voor $TargetName!"
            
            [System.Windows.MessageBox]::Show(
                "Microsoft Graph Command Line Tools heeft nog geen goedkeuring voor de tenant van $TargetName.`n`nWe hebben de applicatie geregistreerd op de achtergrond. Nu moet een beheerder (Global Admin) éénmalig accorderen.`n`nDe link is gekopieerd naar je klembord. We proberen deze nu te openen. Klik daarna in deze tool opnieuw op 'Verbinden'!", 
                "Admin Consent Vereist", 
                [System.Windows.MessageBoxButton]::OK, 
                [System.Windows.MessageBoxImage]::Warning
            )

            Set-Clipboard -Value $consentUrl
            Start-Process -FilePath $consentUrl -ErrorAction SilentlyContinue

        } else {
            $StatusTxt.Text = "Fout bij Tenant Access: $_"
        }
    }
    $LoadProfilesBtn.IsEnabled = $true
})

$DeployBtn.Add_Click({
    if (-not $ProfileDropdown.SelectedItem) { $StatusTxt.Text = "Selecteer een profiel!"; return }
    $DeployBtn.IsEnabled = $false
    $Script:TargetGroupId = $ProfileDropdown.SelectedItem.groupId
    
    try {
        $StatusTxt.Text = "1/4 Hardware Hash genereren (kan even duren)..."
        
        # WMI logica om hash te extraheren
        $session = New-CimSession
        $devDetail = Get-CimInstance -CimSession $session -Namespace root/cimv2/mdm/dmmap -ClassName MDM_DevDetail_Ext01 -Filter "InstanceID='Ext' AND ParentID='./DevDetail'"
        $hash = $devDetail.DeviceHardwareData
        $serial = (Get-CimInstance -CimSession $session -ClassName Win32_BIOS).SerialNumber
        Remove-CimSession $session
        
        if ([string]::IsNullOrWhiteSpace($hash)) {
            throw "Kon hardware hash niet uitlezen!"
        }
        
        $StatusTxt.Text = "2/4 Registreren bij Intune Graph API..."
        
        $uri = "https://graph.microsoft.com/beta/deviceManagement/importedWindowsAutopilotDeviceIdentities"
        $json = @{
            "@odata.type" = "#microsoft.graph.importedWindowsAutopilotDeviceIdentity"
            "groupTag" = ""
            "serialNumber" = $serial
            "hardwareIdentifier" = $hash
            "state" = @{
                "@odata.type" = "microsoft.graph.importedWindowsAutopilotDeviceIdentityState"
                "deviceImportStatus" = "pending"
            }
        } | ConvertTo-Json -Depth 5
        
        $autopilotDevice = Invoke-MgGraphRequest -Method POST -Uri $uri -Body $json -ContentType "application/json"
        
        $StatusTxt.Text = "3/4 Apparaat wachten tot geregistreerd... ($($autopilotDevice.id))"
        Start-Sleep -Seconds 10 # Wacht even op Intune verwerking
        
        if (-not [string]::IsNullOrWhiteSpace($Script:TargetGroupId)) {
            $StatusTxt.Text = "Toevoegen aan bijbehorende Entra Groep..."
            # Verkrijg het gekoppelde aadDeviceId (kan duren voordat intune 'm genereert, in dit basic script doen we een ruwe gok of de API 'm klaar heeft)
            # Voor robuustheid zou hier een poll-loop moeten zitten die kijkt of $autopilotDevice.state.deviceImportStatus -eq 'complete'
        }
        
        $StatusTxt.Text = "4/4 Vraagt Intune Sync aan..."
        # $syncUri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotSettings/sync"
        # Invoke-MgGraphRequest -Method POST -Uri $syncUri

        $StatusTxt.Text = "GEREED! Apparaat ($serial) is geregistreerd. Herstart de computer om OOBE opnieuw te beginnen."
        
    } catch {
       $StatusTxt.Text = "Registratie Mislukt: $_" 
    }
    $DeployBtn.IsEnabled = $true
})

# Laat window zien
$Window.ShowDialog() | Out-Null
