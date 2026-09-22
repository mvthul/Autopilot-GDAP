<#
.SYNOPSIS
  Autopilot GDAP GUI - Ontwikkeld voor MSP IT-Hulp met ingebouwde Admin Consent afhandeling
#>
$Global:PublicClientId = "6a87f18c-ab0a-4ef9-bb1c-587ae884b8e0"

if ($Global:PublicClientId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$') {
    throw "De eigen App Registration is nog niet geconfigureerd. Voer Setup-AutopilotApp.ps1 eenmalig uit en vervang PublicClientId in dit script."
}

# Zorg dat de MS Graph modules geladen zijn
if (!(Get-Module -ListAvailable Microsoft.Graph.Authentication)) {
    Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force
}
Import-Module Microsoft.Graph.Authentication

Add-Type -AssemblyName PresentationFramework

[xml]$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Autopilot GDAP Registratie" Height="550" Width="500" WindowStartupLocation="CenterScreen"
        FontFamily="Segoe UI" Background="#F4F6F9">
    
    <!-- Venster Styling (Ronde hoeken etc) -->
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#00355f" />
            <Setter Property="Foreground" Value="White" />
            <Setter Property="FontWeight" Value="SemiBold" />
            <Setter Property="BorderThickness" Value="0" />
            <Setter Property="Padding" Value="10,5" />
            <Setter Property="Cursor" Value="Hand" />
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#00b0ca" />
                </Trigger>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Background" Value="#cccccc" />
                    <Setter Property="Foreground" Value="#777777" />
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Padding" Value="5" />
            <Setter Property="BorderBrush" Value="#cccccc" />
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Padding" Value="5" />
            <Setter Property="BorderBrush" Value="#cccccc" />
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="*" />
        </Grid.RowDefinitions>

        <!-- Header met CaptureTech Vector Logo -->
        <Border Grid.Row="0" Background="#00355f" Padding="20">
            <Viewbox Height="40" HorizontalAlignment="Center">
                <Canvas Width="255" Height="45">
                    <Path Fill="#FFFFFF" Data="M762.449,50.781h-5.808V66.858h-5.916V50.781h-5.808v-5.3h17.532Z">
                        <Path.RenderTransform><TranslateTransform X="-562.736" Y="-34.356"/></Path.RenderTransform>
                    </Path>
                    <Path Fill="#FFFFFF" Data="M825.015,70.239h-6.667a3.193,3.193,0,0,1,3.267-2.538,3.314,3.314,0,0,1,3.4,2.538m5.6,1.642h0c0-4.837-3.681-8.63-9-8.63a8.789,8.789,0,1,0,0,17.574,8.687,8.687,0,0,0,8.551-5.877h-5.729a3.383,3.383,0,0,1-2.822,1.308,3.2,3.2,0,0,1-3.367-2.87h12.247a10.393,10.393,0,0,0,.117-1.5">
                        <Path.RenderTransform><TranslateTransform X="-613.909" Y="-47.781"/></Path.RenderTransform>
                    </Path>
                    <Path Fill="#FFFFFF" Data="M910.579,70.481a8.383,8.383,0,0,0-8.7-7.126c-5.324,0-9.125,3.635-9.125,8.738s3.817,8.809,9.107,8.809h0a8.547,8.547,0,0,0,8.776-7.312h-5.622a3.3,3.3,0,0,1-3.155,2.221,3.448,3.448,0,0,1-3.417-3.7,3.409,3.409,0,0,1,3.417-3.666A3.347,3.347,0,0,1,905,70.481Z">
                        <Path.RenderTransform><TranslateTransform X="-674.419" Y="-47.861"/></Path.RenderTransform>
                    </Path>
                    <Path Fill="#FFFFFF" Data="M992.35,53.622v9.932h-5.681V54.282c0-1.9-.668-2.872-2.151-2.872-1.719,0-2.79,1.22-2.79,3.337v8.807h-5.681V41.1h5.681v7.041a7.037,7.037,0,0,1,4.4-1.573c3.786,0,6.22,2.774,6.22,7.049">
                        <Path.RenderTransform><TranslateTransform X="-737.339" Y="-31.052"/></Path.RenderTransform>
                    </Path>
                    <Path Fill="#FFFFFF" Data="M242.138,52.076a10.6,10.6,0,0,0-10.748-8.808,11.231,11.231,0,1,0,0,22.461h0A10.656,10.656,0,0,0,242.2,56.6h-6.056a4.881,4.881,0,0,1-4.746,3.612c-3.027,0-5.248-2.4-5.248-5.7s2.22-5.745,5.248-5.745a5.021,5.021,0,0,1,4.714,3.3Z">
                        <Path.RenderTransform><TranslateTransform X="-166.212" Y="-32.686"/></Path.RenderTransform>
                    </Path>
                    <Path Fill="#FFFFFF" Data="M330.559,72.111a3.693,3.693,0,1,0-3.692,3.762,3.623,3.623,0,0,0,3.692-3.762m5.4-8.259V80.344H331.57l-.486-1.166a7.813,7.813,0,0,1-4.976,1.724,8.41,8.41,0,0,1-8.648-8.805,8.369,8.369,0,0,1,8.648-8.743,7.822,7.822,0,0,1,5.039,1.773l.581-1.276Z">
                        <Path.RenderTransform><TranslateTransform X="-239.82" Y="-47.86"/></Path.RenderTransform>
                    </Path>
                    <Path Fill="#FFFFFF" Data="M420.313,72.036a3.693,3.693,0,1,0-3.692,3.775,3.63,3.63,0,0,0,3.692-3.775m5.716,0a8.4,8.4,0,0,1-8.648,8.8,7.714,7.714,0,0,1-4.021-1.1v6.493h-5.616V63.79h3.864l.712,1.31a7.638,7.638,0,0,1,5.062-1.851,8.388,8.388,0,0,1,8.648,8.787">
                        <Path.RenderTransform><TranslateTransform X="-308.024" Y="-47.781"/></Path.RenderTransform>
                    </Path>
                    <Path Fill="#FFFFFF" Data="M498.129,62.082v4.976H494.22c-3.647,0-5.864-2.23-5.864-5.895V54.939h-3.019V53.611l7.39-7.869h1.167v4.822h4.143v4.375h-4v5.249a1.75,1.75,0,0,0,1.911,1.894Z">
                        <Path.RenderTransform><TranslateTransform X="-366.64" Y="-34.555"/></Path.RenderTransform>
                    </Path>
                    <Path Fill="#FFFFFF" Data="M547.6,74.873V65.46h5.681v9.166c0,1.74.936,2.764,2.454,2.764s2.436-1.041,2.436-2.764V65.46h5.681v9.413c0,4.615-3.245,7.621-8.117,7.621s-8.135-3.006-8.135-7.621">
                        <Path.RenderTransform><TranslateTransform X="-413.678" Y="-49.451"/></Path.RenderTransform>
                    </Path>
                    <Path Fill="#FFFFFF" Data="M638.512,65.139v5.2h-2.205c-2.011,0-2.853.882-2.853,2.985v8.388h-5.681V65.217h3.806l.886,1.831a5.507,5.507,0,0,1,4.543-1.909Z">
                        <Path.RenderTransform><TranslateTransform X="-474.241" Y="-49.208"/></Path.RenderTransform>
                    </Path>
                    <Path Fill="#FFFFFF" Data="M687.777,70.239H681.11a3.193,3.193,0,0,1,3.267-2.538,3.314,3.314,0,0,1,3.4,2.538m5.6,1.642h0c0-4.837-3.681-8.63-9-8.63a8.791,8.791,0,1,0,8.551,11.7H687.2a3.383,3.383,0,0,1-2.822,1.308,3.2,3.2,0,0,1-3.367-2.87h12.247a10.419,10.419,0,0,0,.117-1.5">
                        <Path.RenderTransform><TranslateTransform X="-510.234" Y="-47.781"/></Path.RenderTransform>
                    </Path>
                    <Path Fill="#00baff" Data="M103.455,70.887H94.971V59.3h-5.76V50.812h20V59.3h-5.76Z">
                        <Path.RenderTransform><TranslateTransform X="-67.393" Y="-38.385"/></Path.RenderTransform>
                    </Path>
                    <Path Fill="#00baff" Data="M9.32,45a31.82,31.82,0,0,1,0-45l7.5,7.5a21.216,21.216,0,0,0,0,30Z" />
                </Canvas>
            </Viewbox>
        </Border>

        <!-- Formulier / StackPanel -->
        <StackPanel Grid.Row="1" Margin="25">
            <TextBlock Text="Autopilot Deployment Tool" FontSize="18" FontWeight="Light" Foreground="#00355f" Margin="0,0,0,20" HorizontalAlignment="Center" />

            <Button Name="LogonBtn" Content="1. Log in met IT-Hulp Account" Height="35" Margin="0,0,0,15" />
            
            <TextBlock Text="Klant Tenant:" FontSize="13" Foreground="#333333" Margin="0,0,0,4"/>
            <TextBox Name="TenantSearchBox" Height="28" IsEnabled="False" Margin="0,0,0,6" ToolTip="Zoek op klantnaam" />
            <ComboBox Name="TenantDropdown" Height="30" IsEnabled="False" Margin="0,0,0,15" DisplayMemberPath="displayName" />
            
            <Button Name="LoadProfilesBtn" Content="2. Verbind met Klant &amp; Zoek Profielen" Height="35" IsEnabled="False" Margin="0,0,0,15" />
            
            <TextBlock Text="Selecteer Profiel (en toegewezen groep):" FontSize="13" Foreground="#333333" Margin="0,0,0,4"/>
            <ComboBox Name="ProfileDropdown" Height="30" IsEnabled="False" Margin="0,0,0,15" DisplayMemberPath="displayName" />

            <CheckBox Name="AddToGroupBox" Content="Voeg apparaat na import toe aan de toegewezen groep" IsEnabled="False" Margin="0,0,0,15" />
            
            <TextBlock Text="Device Hostname (Optioneel):" FontSize="13" Foreground="#333333" Margin="0,0,0,4"/>
            <TextBox Name="HostnameBox" Height="30" IsEnabled="False" Margin="0,0,0,25"/>

            <!-- Primaire Actie Knop gestylet in de Cyaan kleur -->
            <Button Name="DeployBtn" Content="3. Registreer Apparaat" Height="45" FontSize="15" IsEnabled="False" Background="#00b0ca" />
            
            <Border Background="#ffffff" BorderBrush="#dddddd" BorderThickness="1" CornerRadius="4" Padding="15" Margin="0,20,0,0">
                <TextBlock x:Name="StatusTxt" Text="Klaar voor aanmelding..." Foreground="#555555" TextWrapping="Wrap" TextAlignment="Center" />
            </Border>
        </StackPanel>
    </Grid>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $XAML)
$Window = [Windows.Markup.XamlReader]::Load($reader)

# Map UI Controls
$LogonBtn        = $Window.FindName("LogonBtn")
$TenantSearchBox = $Window.FindName("TenantSearchBox")
$TenantDropdown  = $Window.FindName("TenantDropdown")
$LoadProfilesBtn = $Window.FindName("LoadProfilesBtn")
$ProfileDropdown = $Window.FindName("ProfileDropdown")
$AddToGroupBox   = $Window.FindName("AddToGroupBox")
$HostnameBox     = $Window.FindName("HostnameBox")
$DeployBtn       = $Window.FindName("DeployBtn")
$StatusTxt       = $Window.FindName("StatusTxt")

# Helpers
$Script:TargetTenantId = ""
$Script:TargetGroupId = ""
$Script:AllContracts = [System.Collections.Generic.List[object]]::new()
$Script:PartnerCenterAccessToken = $null
$Script:PartnerCenterTokenPath = Join-Path $(if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { $env:TEMP }) "CaptureTech\AutopilotGDAP\partnercenter.token"

function Save-PartnerCenterToken {
    param([object]$Token)
    if ([string]::IsNullOrWhiteSpace([string]$Token.refresh_token)) { return }
    $folder = Split-Path -Parent $Script:PartnerCenterTokenPath
    New-Item -Path $folder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    $protected = ConvertTo-SecureString ($Token | ConvertTo-Json -Compress) -AsPlainText -Force |
        ConvertFrom-SecureString
    Set-Content -Path $Script:PartnerCenterTokenPath -Value $protected -Force
}

function Get-CachedPartnerCenterToken {
    if (-not (Test-Path -LiteralPath $Script:PartnerCenterTokenPath)) { return $null }
    try {
        $protected = Get-Content -LiteralPath $Script:PartnerCenterTokenPath -Raw
        $plain = [System.Net.NetworkCredential]::new('', (ConvertTo-SecureString $protected)).Password
        $cached = $plain | ConvertFrom-Json
        if ([string]::IsNullOrWhiteSpace([string]$cached.refresh_token)) { return $null }
        return $cached
    }
    catch { return $null }
}

function Get-PartnerCenterAccessToken {
    $scope = "https://api.partnercenter.microsoft.com/user_impersonation offline_access"
    $tokenUri = "https://login.microsoftonline.com/organizations/oauth2/v2.0/token"

    $cached = Get-CachedPartnerCenterToken
    if ($cached) {
        try {
            $renewed = Invoke-RestMethod -Method POST -Uri $tokenUri `
                -Body @{
                    grant_type = "refresh_token"
                    client_id = $Global:PublicClientId
                    refresh_token = $cached.refresh_token
                    scope = $scope
                } `
                -ContentType "application/x-www-form-urlencoded" `
                -ErrorAction Stop
            Save-PartnerCenterToken $renewed
            return $renewed.access_token
        }
        catch {
            Remove-Item -LiteralPath $Script:PartnerCenterTokenPath -Force -ErrorAction SilentlyContinue
        }
    }

    $deviceCode = Invoke-RestMethod -Method POST `
        -Uri "https://login.microsoftonline.com/organizations/oauth2/v2.0/devicecode" `
        -Body @{ client_id = $Global:PublicClientId; scope = $scope } `
        -ContentType "application/x-www-form-urlencoded" `
        -ErrorAction Stop

    Start-Process $deviceCode.verification_uri -ErrorAction SilentlyContinue
    [System.Windows.MessageBox]::Show(
        "Eenmalige Partner Center-aanmelding vereist.`n`nOpen: $($deviceCode.verification_uri)`nCode: $($deviceCode.user_code)`n`nMeld aan met het IT-Hulp-account. Als consent wordt gevraagd, accepteer dit.",
        "Partner Center aanmelden",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Information
    ) | Out-Null

    do {
        Start-Sleep -Seconds ([int]$deviceCode.interval)
        try {
            $token = Invoke-RestMethod -Method POST -Uri $tokenUri `
                -Body @{
                    grant_type = "urn:ietf:params:oauth:grant-type:device_code"
                    client_id = $Global:PublicClientId
                    device_code = $deviceCode.device_code
                } `
                -ContentType "application/x-www-form-urlencoded" `
                -ErrorAction Stop
            Save-PartnerCenterToken $token
            return $token.access_token
        }
        catch {
            $body = $_.ErrorDetails.Message
            if ($body -notmatch 'authorization_pending|slow_down') {
                throw "Partner Center-aanmelding mislukt: $body"
            }
        }
    } while ($true)
}

function Get-PartnerCenterCustomers {
    if ([string]::IsNullOrWhiteSpace($Script:PartnerCenterAccessToken)) {
        $Script:PartnerCenterAccessToken = Get-PartnerCenterAccessToken
    }

    $headers = @{ Authorization = "Bearer $Script:PartnerCenterAccessToken"; Accept = "application/json" }
    $uri = "https://api.partnercenter.microsoft.com/v1/customers"
    $customers = [System.Collections.Generic.List[object]]::new()
    do {
        $page = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers -ErrorAction Stop
        foreach ($item in @($page.items)) {
            $profile = $item.companyProfile
            $tenantId = [string]$profile.tenantId
            $domain = [string]$profile.domain
            $name = [string]$profile.companyName
            if ([string]::IsNullOrWhiteSpace($tenantId)) { $tenantId = [string]$item.id }
            [void]$customers.Add([pscustomobject]@{
                displayName = ("{0} [{1}] — {2}" -f $name, $domain, $tenantId)
                customerName = $name
                tenantId = $tenantId
                tenantDomain = $domain
            })
        }
        $next = $page.links.next.uri
        if ([string]::IsNullOrWhiteSpace([string]$next)) { $uri = $null }
        elseif ($next -match '^https?://') { $uri = $next }
        else { $uri = "https://api.partnercenter.microsoft.com$next" }
    } while ($uri)
    return @($customers | Sort-Object tenantId -Unique)
}

function Update-TenantDropdown {
    $filter = [string]$TenantSearchBox.Text.Trim()
    $TenantDropdown.Items.Clear()
    $matches = foreach ($tenant in @($Script:AllContracts)) {
        $name = [string]$tenant.customerName
        if ([string]::IsNullOrWhiteSpace($name)) { $name = [string]$tenant.displayName }
        $domain = [string]$tenant.tenantDomain
        $id = [string]$tenant.tenantId
        if ([string]::IsNullOrWhiteSpace($filter) -or
            $name.IndexOf($filter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $domain.IndexOf($filter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $id.IndexOf($filter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $tenant
        }
    }
    foreach ($tenant in @($matches)) {
        [void]$TenantDropdown.Items.Add($tenant)
    }
    if ($TenantSearchBox.IsEnabled) {
        $StatusTxt.Text = "$( @($matches).Count ) klant(en) gevonden."
    }
}

$TenantSearchBox.Add_TextChanged({ Update-TenantDropdown })

# --- UI Logica ---

$LogonBtn.Add_Click({
    $StatusTxt.Text = "Bezig met inloggen op algemeen partner profiel..."
    $LogonBtn.IsEnabled = $false
    try {
        Connect-MgGraph -ClientId $Global:PublicClientId -Scopes @(
            "Directory.Read.All"
        ) -NoWelcome -ErrorAction Stop
        $StatusTxt.Text = "Graph aangemeld. Partner Center-klanten ophalen..."
        $Script:AllContracts = Get-PartnerCenterCustomers
        Update-TenantDropdown
        
        $TenantSearchBox.IsEnabled = $true
        $TenantDropdown.IsEnabled = $true
        $LoadProfilesBtn.IsEnabled = $true
        $StatusTxt.Text = "Klanten geladen vanuit Partner Center. Zoek op klantnaam of tenantdomein."
    }
    catch {
        $err = $_.Exception.Message
        if ($err -match "canceled|cancelled|closed") {
            $StatusTxt.Text = "Aanmelding afgebroken."
        } elseif ($err -match "AADSTS700016|AADSTS65001|consent|Application.*not found") {
            $StatusTxt.Text = "Partner-app ontbreekt of heeft nog geen consent. Voer de eenmalige setup uit."
            [System.Windows.MessageBox]::Show("De partner-tenant is nog niet ingericht voor deze tool. Voer Setup-AutopilotApp.ps1 uit als Global Administrator en geef admin consent.", "Partner-app niet ingericht", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
        else {
            $StatusTxt.Text = "Login mislukt: $err"
        }
    }
    finally {
        $LogonBtn.IsEnabled = $true
    }
})

$LoadProfilesBtn.Add_Click({
    if (-not $TenantDropdown.SelectedItem) { $StatusTxt.Text = "Selecteer een klant!"; return }
    $Script:TargetTenantId = $TenantDropdown.SelectedItem.tenantId
    $TargetName            = $TenantDropdown.SelectedItem.displayName
    
    $StatusTxt.Text = "Verbinden met context van $TargetName..."
    $LoadProfilesBtn.IsEnabled = $false
    
    try {
        Connect-MgGraph -ClientId $Global:PublicClientId -TenantId $Script:TargetTenantId -Scopes @(
            "DeviceManagementServiceConfig.ReadWrite.All",
            "DeviceManagementServiceConfig.Read.All",
            "Group.Read.All",
            "GroupMember.ReadWrite.All"
        ) -NoWelcome -ErrorAction Stop
        
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
        $AddToGroupBox.IsEnabled = $true
        $HostnameBox.IsEnabled = $true
        $DeployBtn.IsEnabled = $true
        $StatusTxt.Text = "Profielen geladen voor $TargetName! Klaar voor registratie."
    } catch {
        $err = $_.Exception.Message
        
        # Scenario 1: Rechten probleem (Geen PIM geactiveerd)
        if ($err -match "Forbidden" -or $err -match "Authorization_RequestDenied" -or $err -match "403") {
             [System.Windows.MessageBox]::Show(
                "Toegang geweigerd (403 Forbidden).`n`nJe hebt geen rechten om Autopilot informatie in te zien in de tenant van $TargetName.`n`nOplossing: Controleer of je jouw PIM rol (GDAP Intune Administrator) wel actief hebt voor deze klant in jullie Partner Portal!",
                "Geen GDAP/PIM Rechten",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
            $StatusTxt.Text = "Geen toegang. Activeer je PIM rollen."
        # Scenario 2: klantconsent ontbreekt of de login is afgebroken
        } elseif ($err -match "canceled|cancelled|closed|failed|AADSTS700016|AADSTS65001|consent|Application.*not found") {
            $res = [System.Windows.MessageBox]::Show(
                "De klanttenant heeft nog geen consent gegeven voor de eigen Autopilot-app, of de login is afgebroken.`n`nWil je de tenant-specifieke admin-consentpagina openen? Hiervoor is een Global Administrator van de klanttenant nodig.",
                "Admin consent voor klanttenant",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Question
            )
            if ($res -eq 'Yes') {
                $StatusTxt.Text = "Consentlink voor klanttenant openen..."
                $consentUrl = "https://login.microsoftonline.com/$Script:TargetTenantId/adminconsent?client_id=$Global:PublicClientId&redirect_uri=http%3A%2F%2Flocalhost"
                Set-Clipboard -Value $consentUrl -ErrorAction SilentlyContinue
                
                try {
                    Start-Process -FilePath "msedge.exe" -ArgumentList $consentUrl -ErrorAction Stop
                    $StatusTxt.Text = "Browser geopend voor eenmalig Consent! Klik daarna weer op Verbinden."
                } catch {
                    [System.Windows.MessageBox]::Show("Link staat op je klembord (Ctrl+V).`n`nOpen hem om eenmalig goedkeuring te geven!`n`nLink: $consentUrl", "Handmatige Actie")
                    $StatusTxt.Text = "Link gekopieerd. Graag accepteren via beheerder."
                }
            } else {
                $StatusTxt.Text = "Selectie afgebroken."
            }
        } else {
            $StatusTxt.Text = "Fout: $err"
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
        
        $StatusTxt.Text = "3/4 Wachten op Intune-import... ($($autopilotDevice.id))"
        $imported = $null
        for ($attempt = 1; $attempt -le 20; $attempt++) {
            Start-Sleep -Seconds 6
            $imported = Invoke-MgGraphRequest -Method GET -Uri "$uri/$($autopilotDevice.id)"
            if ($imported.state.deviceImportStatus -eq "complete") { break }
            if ($imported.state.deviceImportStatus -eq "error") {
                throw "Intune kon de hardwarehash niet importeren. Controleer de hardwarehash en tenantrechten."
            }
            $StatusTxt.Text = "3/4 Wachten op Intune-import... poging $attempt/20"
        }
        if ($imported.state.deviceImportStatus -ne "complete") {
            throw "Timeout: Intune heeft de hardwarehash nog niet afgerond. Controleer de import later in Intune."
        }

        if ($AddToGroupBox.IsChecked -and [string]::IsNullOrWhiteSpace($Script:TargetGroupId)) {
            throw "Het geselecteerde profiel heeft geen toegewezen Entra-groep."
        }

        if ($AddToGroupBox.IsChecked) {
            $deviceObjectId = $imported.state.deviceRegistrationId
            if ([string]::IsNullOrWhiteSpace($deviceObjectId)) {
                throw "Intune heeft nog geen Entra device-object-id teruggegeven. Probeer later opnieuw."
            }
            $StatusTxt.Text = "4/5 Apparaat toevoegen aan de geselecteerde groep..."
            $memberBody = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$deviceObjectId" } | ConvertTo-Json
            Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/groups/$Script:TargetGroupId/members/`$ref" -Body $memberBody -ContentType "application/json" -ErrorAction Stop
        }
        
        $StatusTxt.Text = "4/5 Intune-sync aanvragen..."
        $syncUri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotSettings/sync"
        Invoke-MgGraphRequest -Method POST -Uri $syncUri -ErrorAction Stop

        $StatusTxt.Text = "GEREED! Apparaat ($serial) is geregistreerd. Herstart de computer om OOBE opnieuw te beginnen."
        
    } catch {
       $StatusTxt.Text = "Registratie Mislukt: $_" 
    }
    $DeployBtn.IsEnabled = $true
})

# Laat window zien
$Window.ShowDialog() | Out-Null
