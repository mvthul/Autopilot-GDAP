<#
.SYNOPSIS
  Autopilot GDAP GUI - Ontwikkeld voor MSP IT-Hulp met ingebouwde Admin Consent afhandeling
#>
$Global:PublicClientId = "6a87f18c-ab0a-4ef9-bb1c-587ae884b8e0"
$Global:PartnerTenantId = "26aaae92-5737-48a2-b00c-27aff5b013e7"

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
        Title="Autopilot GDAP Registratie" Width="540" SizeToContent="Height" MinHeight="650" WindowStartupLocation="CenterScreen"
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
        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
        <StackPanel Margin="25">
            <TextBlock Text="Autopilot Deployment Tool" FontSize="18" FontWeight="Light" Foreground="#00355f" Margin="0,0,0,20" HorizontalAlignment="Center" />

            <Button Name="LogonBtn" Content="1. Log in met IT-Hulp Account" Height="35" Margin="0,0,0,15" />
            
            <TextBlock Text="Klant Tenant:" FontSize="13" Foreground="#333333" Margin="0,0,0,4"/>
            <TextBox Name="TenantSearchBox" Height="28" IsEnabled="False" Margin="0,0,0,6" ToolTip="Zoek op klantnaam" />
            <ComboBox Name="TenantDropdown" Height="30" IsEnabled="False" Margin="0,0,0,15" DisplayMemberPath="displayName" />
            
            <Button Name="LoadProfilesBtn" Content="2. Verbind met Klant &amp; Zoek Profielen" Height="35" IsEnabled="False" Margin="0,0,0,15" />
            
            <TextBlock Text="Selecteer Profiel (en toegewezen groep):" FontSize="13" Foreground="#333333" Margin="0,0,0,4"/>
            <ComboBox Name="ProfileDropdown" Height="30" IsEnabled="False" Margin="0,0,0,15" DisplayMemberPath="displayName" />

            <Border Background="#ffffff" BorderBrush="#dddddd" BorderThickness="1" CornerRadius="4" Padding="10" Margin="0,0,0,15">
                <TextBlock Name="GroupDecisionTxt" Text="Groepsinformatie verschijnt na het laden van de profielen." Foreground="#555555" TextWrapping="Wrap" />
            </Border>

            <TextBlock Name="GroupChoiceLabel" Text="Statische groep voor handmatige toevoeging:" FontSize="13" Foreground="#333333" Margin="0,0,0,4" Visibility="Collapsed" />
            <ComboBox Name="GroupChoiceDropdown" Height="30" IsEnabled="False" Margin="0,0,0,15" DisplayMemberPath="displayName" Visibility="Collapsed" />
            
            <TextBlock Text="Device Hostname (Optioneel):" FontSize="13" Foreground="#333333" Margin="0,0,0,4"/>
            <TextBox Name="HostnameBox" Height="30" IsEnabled="False" Margin="0,0,0,25"/>

            <!-- Primaire Actie Knop gestylet in de Cyaan kleur -->
            <Button Name="DeployBtn" Content="3. Registreer Apparaat" Height="45" FontSize="15" IsEnabled="False" Background="#00b0ca" />

            <Button Name="RebootBtn" Content="4. Herstart computer" Height="40" FontSize="14" IsEnabled="False" Margin="0,12,0,0" />

            <TextBlock Text="Uitvoer Community-script:" FontSize="13" Foreground="#333333" Margin="0,18,0,4" />
            <CheckBox Name="VerboseCheck" Content="Toon technische uitvoer (Graph GET/POST en modulemeldingen)" Margin="0,0,0,6" IsChecked="False" />
            <TextBox Name="LogBox" Height="170" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" FontFamily="Consolas" FontSize="11" />
            
            <Border Background="#ffffff" BorderBrush="#dddddd" BorderThickness="1" CornerRadius="4" Padding="15" Margin="0,20,0,0">
                <TextBlock x:Name="StatusTxt" Text="Klaar voor aanmelding..." Foreground="#555555" TextWrapping="Wrap" TextAlignment="Center" />
            </Border>
        </StackPanel>
        </ScrollViewer>
    </Grid>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $XAML)
$Window = [Windows.Markup.XamlReader]::Load($reader)
$Window.MaxHeight = [System.Windows.SystemParameters]::WorkArea.Height

# Map UI Controls
$LogonBtn        = $Window.FindName("LogonBtn")
$TenantSearchBox = $Window.FindName("TenantSearchBox")
$TenantDropdown  = $Window.FindName("TenantDropdown")
$LoadProfilesBtn = $Window.FindName("LoadProfilesBtn")
$ProfileDropdown = $Window.FindName("ProfileDropdown")
$GroupDecisionTxt = $Window.FindName("GroupDecisionTxt")
$GroupChoiceLabel = $Window.FindName("GroupChoiceLabel")
$GroupChoiceDropdown = $Window.FindName("GroupChoiceDropdown")
$HostnameBox     = $Window.FindName("HostnameBox")
$DeployBtn       = $Window.FindName("DeployBtn")
$RebootBtn       = $Window.FindName("RebootBtn")
$VerboseCheck    = $Window.FindName("VerboseCheck")
$LogBox          = $Window.FindName("LogBox")
$StatusTxt       = $Window.FindName("StatusTxt")

# Helpers
$Script:TargetTenantId = ""
$Script:AllContracts = [System.Collections.Generic.List[object]]::new()
$Script:PartnerCenterAccessToken = $null
$Script:PartnerCenterTokenPath = Join-Path $(if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { $env:TEMP }) "CaptureTech\AutopilotGDAP\partnercenter.v1.token"

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
    $partnerCenterResource = "https://api.partnercenter.microsoft.com"
    $tokenUri = "https://login.microsoftonline.com/common/oauth2/token"

    $cached = Get-CachedPartnerCenterToken
    if ($cached) {
        try {
            $renewed = Invoke-RestMethod -Method POST -Uri $tokenUri `
                -Body @{
                    grant_type = "refresh_token"
                    client_id = $Global:PublicClientId
                    refresh_token = $cached.refresh_token
                    resource = $partnerCenterResource
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

    # Graph and Partner Center are different OAuth resources, so the Graph
    # access token cannot be reused. This browser flow does reuse the user's
    # existing Microsoft SSO session and avoids device-code authentication.
    $redirectUri = "http://localhost:8765/"
    $listener = New-Object System.Net.HttpListener
    try {
        $listener.Prefixes.Add($redirectUri)
        $listener.Start()
    }
    catch {
        $listener.Close()
        throw "Partner Center-aanmelding kan de lokale callback niet starten op $redirectUri. Sluit een eventueel andere instantie van de tool en probeer opnieuw. Details: $($_.Exception.Message)"
    }

    try {
        $authorizeUri = "https://login.microsoftonline.com/common/oauth2/authorize?client_id=$([uri]::EscapeDataString($Global:PublicClientId))&response_type=code&redirect_uri=$([uri]::EscapeDataString($redirectUri))&response_mode=query&resource=$([uri]::EscapeDataString($partnerCenterResource))&prompt=select_account"
        Start-Process $authorizeUri -ErrorAction Stop
        $asyncResult = $listener.BeginGetContext($null, $null)
        if (-not $asyncResult.AsyncWaitHandle.WaitOne(300000)) {
            throw "De browser-aanmelding duurde langer dan vijf minuten."
        }
        $context = $listener.EndGetContext($asyncResult)
        $query = $context.Request.QueryString
        $html = if ($query["error"]) {
            "<html><body><h2>Aanmelding niet voltooid</h2><p>U kunt dit venster sluiten.</p></body></html>"
        } else {
            "<html><body><h2>Aanmelding voltooid</h2><p>U kunt dit venster sluiten en teruggaan naar de Autopilot-tool.</p></body></html>"
        }
        $bytes = [Text.Encoding]::UTF8.GetBytes($html)
        $context.Response.ContentType = "text/html; charset=utf-8"
        $context.Response.ContentLength64 = $bytes.Length
        $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $context.Response.OutputStream.Close()

        if ($query["error"]) {
            throw "Partner Center-aanmelding mislukt: $($query['error_description'])"
        }
        try {
            $token = Invoke-RestMethod -Method POST -Uri $tokenUri `
                -Body @{
                    grant_type = "authorization_code"
                    client_id = $Global:PublicClientId
                    code = $query["code"]
                    redirect_uri = $redirectUri
                    resource = $partnerCenterResource
                } `
                -ContentType "application/x-www-form-urlencoded" `
                -ErrorAction Stop
        }
        catch {
            $detail = $_.ErrorDetails.Message
            if ([string]::IsNullOrWhiteSpace($detail)) { $detail = $_.Exception.Message }
            throw "Partner Center-token ophalen mislukt: $detail"
        }
        Save-PartnerCenterToken $token
        return $token.access_token
    }
    catch {
        if ($_.Exception.Message -like "Partner Center-aanmelding mislukt:*") { throw }
        throw "Partner Center-aanmelding mislukt. Controleer of Partner Center-admin consent is verleend en of redirect URI $redirectUri in de app staat. Details: $($_.Exception.Message)"
    }
    finally {
        if ($listener.IsListening) { $listener.Stop() }
        $listener.Close()
    }
}

function Get-BrowserGraphAccessToken {
    param(
        [Parameter(Mandatory = $true)][string]$TenantId,
        [Parameter(Mandatory = $true)][string[]]$Scopes
    )
    $scope = (($Scopes + @("openid", "profile", "offline_access")) | Select-Object -Unique) -join " "
    $authority = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0"
    $redirectUri = "http://localhost:8766/"
    $listener = New-Object System.Net.HttpListener
    try {
        $listener.Prefixes.Add($redirectUri)
        $listener.Start()
    }
    catch {
        $listener.Close()
        throw "Graph-browseraanmelding kan de lokale callback niet starten op $redirectUri. Sluit een andere toolinstantie. Details: $($_.Exception.Message)"
    }
    try {
        $authorizeUri = "$authority/authorize?client_id=$([uri]::EscapeDataString($Global:PublicClientId))&response_type=code&redirect_uri=$([uri]::EscapeDataString($redirectUri))&response_mode=query&scope=$([uri]::EscapeDataString($scope))&prompt=select_account"
        Start-Process $authorizeUri -ErrorAction Stop
        $asyncResult = $listener.BeginGetContext($null, $null)
        if (-not $asyncResult.AsyncWaitHandle.WaitOne(300000)) {
            throw "De Graph-browseraanmelding duurde langer dan vijf minuten."
        }
        $context = $listener.EndGetContext($asyncResult)
        $query = $context.Request.QueryString
        $html = if ($query["error"]) {
            "<html><body><h2>Aanmelding niet voltooid</h2><p>U kunt dit venster sluiten.</p></body></html>"
        } else {
            "<html><body><h2>Aanmelding voltooid</h2><p>U kunt dit venster sluiten en teruggaan naar de Autopilot-tool.</p></body></html>"
        }
        $bytes = [Text.Encoding]::UTF8.GetBytes($html)
        $context.Response.ContentType = "text/html; charset=utf-8"
        $context.Response.ContentLength64 = $bytes.Length
        $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $context.Response.OutputStream.Close()
        if ($query["error"]) {
            throw "Graph-aanmelding mislukt: $($query['error_description'])"
        }
        try {
            $token = Invoke-RestMethod -Method POST -Uri "$authority/token" -Body @{
                grant_type = "authorization_code"
                client_id = $Global:PublicClientId
                code = $query["code"]
                redirect_uri = $redirectUri
                scope = $scope
            } -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
        }
        catch {
            $detail = $_.ErrorDetails.Message
            if ([string]::IsNullOrWhiteSpace($detail)) { $detail = $_.Exception.Message }
            throw "Graph-token ophalen mislukt: $detail"
        }
        return [string]$token.access_token
    }
    finally {
        if ($listener.IsListening) { $listener.Stop() }
        $listener.Close()
    }
}

function Connect-BrowserGraph {
    param(
        [Parameter(Mandatory = $true)][string]$TenantId,
        [Parameter(Mandatory = $true)][string[]]$Scopes
    )
    $accessToken = Get-BrowserGraphAccessToken -TenantId $TenantId -Scopes $Scopes
    $secureToken = ConvertTo-SecureString $accessToken -AsPlainText -Force
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    Connect-MgGraph -AccessToken $secureToken -ErrorAction Stop
}

function Get-PartnerCenterCustomers {
    if ([string]::IsNullOrWhiteSpace($Script:PartnerCenterAccessToken)) {
        $Script:PartnerCenterAccessToken = Get-PartnerCenterAccessToken
    }

    $headers = @{
        Authorization = "Bearer $Script:PartnerCenterAccessToken"
        Accept = "application/json"
        "MS-RequestId" = [guid]::NewGuid().ToString()
        "MS-CorrelationId" = [guid]::NewGuid().ToString()
        "MS-Contract-Version" = "v1"
    }
    $uri = "https://api.partnercenter.microsoft.com/v1/customers"
    $customers = [System.Collections.Generic.List[object]]::new()
    do {
        try {
            $page = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers -ErrorAction Stop
        }
        catch {
            $detail = $_.ErrorDetails.Message
            if ([string]::IsNullOrWhiteSpace($detail)) { $detail = $_.Exception.Message }
            throw "Partner Center-klantenlijst ophalen mislukt ($uri): $detail"
        }
        foreach ($item in @($page.items)) {
            $profile = $item.companyProfile
            $tenantId = [string]$profile.tenantId
            $domain = [string]$profile.domain
            $name = [string]$profile.companyName
            if ([string]::IsNullOrWhiteSpace($tenantId)) { $tenantId = [string]$item.id }
            [void]$customers.Add([pscustomobject]@{
                displayName = ("{0} [{1}] - {2}" -f $name, $domain, $tenantId)
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

function Write-ToolLog {
    param([AllowNull()][object]$Message)
    $text = if ($null -eq $Message) { "" } else { ($Message | Out-String).TrimEnd() }
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    Write-Host $text
    $LogBox.AppendText("$text`r`n")
    $LogBox.ScrollToEnd()
    $StatusTxt.Text = $text
    $Window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
}

function Write-CommunityOutput {
    param([AllowNull()][object]$Record)

    $text = if ($null -eq $Record) { "" } else { ($Record | Out-String).TrimEnd() }
    if ([string]::IsNullOrWhiteSpace($text)) { return }

    # The Community script emits Graph request details and module-import chatter
    # only useful for diagnostics. Keep normal progress/results visible by default.
    if (-not $VerboseCheck.IsChecked) {
        $technicalPatterns = @(
            '^Loading module from path ',
            '^Importing (cmdlet|function|alias) ',
            '^Version \d+ module detected',
            '^(GET|POST|PUT|PATCH|DELETE) https://graph\.microsoft\.com/',
            '^received \d+-byte response',
            '^Perform operation ',
            "^Operation '.*' (complete|with following parameters)",
            '^\s*ClientId\s+:',
            '^\{\s*$'
        )
        foreach ($pattern in $technicalPatterns) {
            if ($text -match $pattern) { return }
        }
    }
    Write-ToolLog $text
}

function Get-GraphCollection {
    param([Parameter(Mandatory = $true)][string]$Uri)
    $items = @()
    $next = $Uri
    while ($next) {
        $page = Invoke-MgGraphRequest -Method GET -Uri $next -OutputType PSObject -ErrorAction Stop
        $items += @($page.value)
        $next = $page.'@odata.nextLink'
    }
    return $items
}

function Get-GroupInfo {
    param([Parameter(Mandatory = $true)][string]$GroupId)
    if ([string]::IsNullOrWhiteSpace($GroupId)) {
        throw "Autopilot-profiel bevat een groepsassignment zonder groupId. Controleer de assignment-response in het log."
    }
    # Fetch the complete group object. Some Windows PowerShell versions and
    # Invoke-MgGraphRequest combinations incorrectly turn an encoded $select
    # query into /groups/$select=..., which Graph rejects.
    $group = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups/$GroupId" -OutputType PSObject -ErrorAction Stop
    $isDynamic = @($group.groupTypes) -contains "DynamicMembership"
    $escapedName = ([string]$group.displayName).Replace("'", "''")
    $sameNameGroups = @(Get-GraphCollection -Uri "https://graph.microsoft.com/v1.0/groups" | Where-Object { $_.displayName -eq $group.displayName })
    $children = @()
    $parents = @()
    try {
        $children = @(Get-GraphCollection -Uri "https://graph.microsoft.com/v1.0/groups/$GroupId/members/microsoft.graph.group")
    } catch { }
    try {
        $parents = @(Get-GraphCollection -Uri "https://graph.microsoft.com/v1.0/groups/$GroupId/transitiveMemberOf/microsoft.graph.group")
    } catch { }
    [pscustomobject]@{
        id = [string]$group.id
        name = [string]$group.displayName
        isDynamic = $isDynamic
        type = if ($isDynamic) { "Dynamisch" } else { "Statisch" }
        membershipRule = [string]$group.membershipRule
        membershipRuleProcessingState = [string]$group.membershipRuleProcessingState
        securityEnabled = [bool]$group.securityEnabled
        mailEnabled = [bool]$group.mailEnabled
        matchingGroupCount = @($sameNameGroups).Count
        childGroups = @($children)
        parentGroups = @($parents)
        hasNested = (@($children).Count -gt 0 -or @($parents).Count -gt 0)
    }
}

function Get-ProfileAssignments {
    param([Parameter(Mandatory = $true)][object]$Profile)
    $assignments = Get-GraphCollection -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$($Profile.id)/assignments"
    $groups = @()
    foreach ($assignment in @($assignments)) {
        $target = $assignment.target
        $targetType = [string]$target.'@odata.type'
        $groupId = [string]$target.groupId
        if ([string]::IsNullOrWhiteSpace($groupId)) { continue }
        $info = Get-GroupInfo -GroupId $groupId
        $info | Add-Member -NotePropertyName isExclusion -NotePropertyValue ($targetType -match 'exclusion')
        $groups += $info
    }
    return @($groups)
}

function Get-ProfileGroupCandidates {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Groups)
    $candidates = [System.Collections.Generic.List[object]]::new()

    foreach ($group in @($Groups | Where-Object { -not $_.isDynamic -and -not $_.isExclusion })) {
        [void]$candidates.Add([pscustomobject]@{
            id = $group.id
            name = $group.name
            source = "Direct toegewezen statische groep"
            displayName = "$($group.name) - direct statisch"
            groupInfo = $group
        })
    }

    foreach ($dynamicGroup in @($Groups | Where-Object { $_.isDynamic -and -not $_.isExclusion })) {
        foreach ($child in @($dynamicGroup.childGroups)) {
            if (@($child.groupTypes) -contains "DynamicMembership") { continue }
            if ([string]::IsNullOrWhiteSpace([string]$child.id)) { continue }
            [void]$candidates.Add([pscustomobject]@{
                id = [string]$child.id
                name = [string]$child.displayName
                source = "Nested onder dynamische groep '$($dynamicGroup.name)'"
                displayName = "$($child.displayName) - nested statisch onder $($dynamicGroup.name)"
                groupInfo = $null
            })
        }
    }

    return @($candidates | Group-Object id | ForEach-Object { $_.Group[0] } | Sort-Object displayName)
}

function Get-LocalSerialNumber {
    return [string](Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop).SerialNumber
}

function Get-DirectoryDeviceObjectId {
    param([Parameter(Mandatory = $true)][string]$SerialNumber)
    $escapedSerial = $SerialNumber.Replace("'", "''")
    $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities?%24filter=serialNumber eq '$escapedSerial'"
    $autopilot = @(Get-GraphCollection -Uri $uri | Select-Object -First 1)
    $aadDeviceId = [string]$autopilot.azureActiveDirectoryDeviceId
    if ([string]::IsNullOrWhiteSpace($aadDeviceId)) { return $null }
    $deviceUri = "https://graph.microsoft.com/v1.0/devices?%24filter=deviceId eq '$aadDeviceId'"
    return [string](@(Get-GraphCollection -Uri $deviceUri | Select-Object -First 1).id)
}

function Test-DeviceInGroup {
    param(
        [Parameter(Mandatory = $true)][string]$GroupId,
        [Parameter(Mandatory = $true)][string]$DeviceObjectId
    )
    try {
        Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups/$GroupId/members/$DeviceObjectId/`$ref" -ErrorAction Stop | Out-Null
        return $true
    }
    catch { return $false }
}

function Wait-ForDynamicGroupMembership {
    param(
        [Parameter(Mandatory = $true)][object[]]$Groups,
        [Parameter(Mandatory = $true)][string]$SerialNumber
    )
    if ($Groups.Count -eq 0) { return }
    $deviceObjectId = $null
    for ($deviceAttempt = 1; $deviceAttempt -le 10; $deviceAttempt++) {
        $deviceObjectId = Get-DirectoryDeviceObjectId -SerialNumber $SerialNumber
        if (-not [string]::IsNullOrWhiteSpace($deviceObjectId)) { break }
        Write-ToolLog "Wachten op Entra-device-object voor dynamische groepscontrole ($deviceAttempt/10)..."
        Start-Sleep -Seconds 30
    }
    if ([string]::IsNullOrWhiteSpace($deviceObjectId)) {
        Write-ToolLog "Dynamische groepscontrole: Entra-device-object voor serienummer $SerialNumber is niet beschikbaar."
        return
    }
    foreach ($group in $Groups) {
        $isMember = $false
        for ($attempt = 1; $attempt -le 10; $attempt++) {
            $isMember = Test-DeviceInGroup -GroupId $group.id -DeviceObjectId $deviceObjectId
            if ($isMember) { break }
            Write-ToolLog "Wachten op dynamische membership '$($group.name)' ($attempt/10)..."
            Start-Sleep -Seconds 30
        }
        if ($isMember) {
            Write-ToolLog "Dynamische groep '$($group.name)': apparaat is lid geworden."
        } else {
            Write-ToolLog "Dynamische groep '$($group.name)': apparaat is na controle nog geen lid. Query: $($group.membershipRule)"
        }
    }
}

function Get-CommunityScriptPath {
    $command = Get-Command Get-WindowsAutopilotInfoCommunity.ps1 -ErrorAction SilentlyContinue
    if (-not $command) { $command = Get-Command Get-WindowsAutopilotInfoCommunity -ErrorAction SilentlyContinue }
    if (-not $command) {
        Write-ToolLog "Community-script ontbreekt; installeren vanuit PSGallery..."
        Install-Script -Name Get-WindowsAutopilotInfoCommunity -Scope CurrentUser -Force -ErrorAction Stop
        $command = Get-Command Get-WindowsAutopilotInfoCommunity.ps1 -ErrorAction SilentlyContinue
        if (-not $command) { $command = Get-Command Get-WindowsAutopilotInfoCommunity -ErrorAction Stop }
    }
    return $command.Source
}

function Invoke-CommunityOnline {
    param(
        [Parameter(Mandatory = $true)][string]$TenantId,
        [Parameter(Mandatory = $true)][object]$Profile,
        [AllowNull()][object]$SelectedAddToGroup
    )
    $context = Get-MgContext
    if (-not $context -or $context.TenantId -ne $TenantId) {
        throw "De actieve Graph-sessie hoort niet bij klanttenant $TenantId."
    }

    $source = Get-CommunityScriptPath
    $tempPath = Join-Path $env:TEMP ("Get-WindowsAutopilotInfoCommunity-{0}.ps1" -f ([guid]::NewGuid()))
    $scriptText = Get-Content -LiteralPath $source -Raw -ErrorAction Stop
    # The current PSGallery script invokes Connect-ToGraph twice during -Online
    # processing. Patch its internal Connect-MgGraph call, rather than letting
    # it prompt with WAM after this tool has already authenticated the user.
    $reuseBlock = @'
                    $existingContext = Get-MgContext
                    if ($existingContext) {
                        $graph = $existingContext
                        Write-Host "Using existing browser Graph session for tenant $($existingContext.TenantId)"
                    }
                    else {
                        throw "No existing browser Graph session is available for the Community script."
                    }
'@
    $connectRegex = [regex]::new('(?m)^\s*\$graph\s*=\s*Connect-MgGraph\s+-Scopes\s+\$scopes\s*$')
    $patchedText = $connectRegex.Replace($scriptText, $reuseBlock.TrimEnd(), 1)
    if ($patchedText -eq $scriptText) {
        throw "De actuele Community-scriptversie heeft een onbekende Graph-loginstructuur. Er is niet naar WAM teruggevallen."
    }
    $scriptText = $patchedText
    $scriptText = $scriptText.Replace('setx MSAL_FORCE_WAM 0', '# WAM disabled: existing browser Graph session is reused')
    $scriptText = $scriptText.Replace('setx MSAL_FORCE_WAM 1', '# WAM setting is not changed by this tool')
    Set-Content -LiteralPath $tempPath -Value $scriptText -Encoding UTF8

    $dynamicGroups = @($Profile.groups | Where-Object { $_.isDynamic -and -not $_.isExclusion })
    $candidates = @($Profile.groupCandidates)
    if ($candidates.Count -gt 1 -and -not $SelectedAddToGroup) {
        throw "Kies eerst een statische groep voor -AddToGroup."
    }
    if ($candidates.Count -eq 1) { $SelectedAddToGroup = $candidates[0] }
    if ($SelectedAddToGroup -and -not ($SelectedAddToGroup.name -in @($candidates | ForEach-Object name))) {
        throw "De gekozen groep is geen geldige kandidaat voor dit profiel."
    }

    $commandInfo = Get-Command -Name $tempPath -ErrorAction Stop
    $requiredParameters = @("Online", "TenantId", "Assign")
    $missingParameters = @($requiredParameters | Where-Object { -not $commandInfo.Parameters.ContainsKey($_) })
    if ($missingParameters.Count -gt 0) {
        throw "Community-script '$source' ondersteunt vereiste parameter(s) niet: $($missingParameters -join ', '). Gevonden: $($commandInfo.Parameters.Keys -join ', ')."
    }

    $communityParameters = @{
        Online = $true
        TenantId = $TenantId
        Assign = $true
    }
    if ($VerboseCheck.IsChecked) { $communityParameters['Verbose'] = $true }
    if (-not [string]::IsNullOrWhiteSpace($HostnameBox.Text)) { $communityParameters['AssignedComputerName'] = $HostnameBox.Text.Trim() }
    if ($SelectedAddToGroup) { $communityParameters['AddToGroup'] = [string]$SelectedAddToGroup.name }
    Write-ToolLog "Community-script: $source"
    Write-ToolLog "Parameters worden uitsluitend nu, na klik op Registreer Apparaat, doorgegeven: $($communityParameters.Keys -join ', ')"
    if ($SelectedAddToGroup) { Write-ToolLog "Statische groepsactie: -AddToGroup '$($SelectedAddToGroup.name)'." }
    if ($dynamicGroups.Count -gt 0) {
        foreach ($group in $dynamicGroups) { Write-ToolLog "Dynamische groep '$($group.name)': geen handmatige toevoeging (correct). Entra beoordeelt: $($group.membershipRule)" }
    }
    try {
        & $tempPath @communityParameters *>&1 | ForEach-Object { Write-CommunityOutput $_ }
    }
    finally {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
    return $dynamicGroups
}

function Update-GroupDecisionText {
    $profile = $ProfileDropdown.SelectedItem
    $GroupChoiceDropdown.Items.Clear()
    $GroupChoiceDropdown.IsEnabled = $false
    $GroupChoiceDropdown.Visibility = [System.Windows.Visibility]::Collapsed
    $GroupChoiceLabel.Visibility = [System.Windows.Visibility]::Collapsed
    if (-not $profile) {
        $GroupDecisionTxt.Text = "Groepsinformatie verschijnt na het laden van de profielen."
        return
    }
    $groups = @($profile.groups)
    if ($groups.Count -eq 0) {
        $GroupDecisionTxt.Text = "Geen toegewezen groep. Autopilot koppelt het profiel automatisch; -AddToGroup wordt niet gebruikt."
        return
    }
    $lines = foreach ($group in $groups) {
        $kind = if ($group.isDynamic) { "Dynamisch" } else { "Statisch" }
        $suffix = if ($group.isExclusion) { " (uitsluiting)" } else { "" }
        $rule = if ($group.isDynamic) { " Query: $($group.membershipRule)" } else { "" }
        "- $($group.name): $kind$suffix$rule"
    }
    $candidates = @($profile.groupCandidates)
    if ($candidates.Count -eq 0) {
        $action = "Geen geschikte statische groep. Geen -AddToGroup; dynamische groepen worden door Entra geevalueerd."
    }
    elseif ($candidates.Count -eq 1) {
        $action = "Een statische kandidaat: '$($candidates[0].name)'. Deze wordt bij Registreren via -AddToGroup gebruikt."
    }
    else {
        foreach ($candidate in $candidates) { [void]$GroupChoiceDropdown.Items.Add($candidate) }
        $GroupChoiceLabel.Visibility = [System.Windows.Visibility]::Visible
        $GroupChoiceDropdown.Visibility = [System.Windows.Visibility]::Visible
        $GroupChoiceDropdown.IsEnabled = $true
        $GroupChoiceDropdown.SelectedIndex = 0
        $action = "$($candidates.Count) statische kandidaten gevonden. Kies hieronder precies een groep voor -AddToGroup."
    }
    $GroupDecisionTxt.Text = (($lines -join "`n") + "`n`n" + $action)
}

$TenantSearchBox.Add_TextChanged({ Update-TenantDropdown })
$ProfileDropdown.Add_SelectionChanged({ Update-GroupDecisionText })

# --- UI Logica ---

$LogonBtn.Add_Click({
    $StatusTxt.Text = "Bezig met inloggen op algemeen partner profiel..."
    $LogonBtn.IsEnabled = $false
    try {
        Connect-BrowserGraph -TenantId $Global:PartnerTenantId -Scopes @(
            "Directory.Read.All"
        )
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
        # Force a clean tenant switch. Partner Center uses its own token, so
        # the partner Graph context is not needed while reading the customer.
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        Connect-BrowserGraph -TenantId $Script:TargetTenantId -Scopes @(
            "DeviceManagementServiceConfig.ReadWrite.All",
            "Group.Read.All",
            "GroupMember.ReadWrite.All",
            "Directory.Read.All"
        )
        $graphContext = Get-MgContext
        Write-ToolLog "Graph-account: $($graphContext.Account)"
        Write-ToolLog "Graph-tenant: $($graphContext.TenantId) (verwacht: $Script:TargetTenantId)"
        Write-ToolLog "Graph-scopes: $($graphContext.Scopes -join ', ')"
        if ([string]$graphContext.TenantId -ne [string]$Script:TargetTenantId) {
            throw "Graph heeft de verkeerde tenantcontext geopend: $($graphContext.TenantId). Verwacht: $Script:TargetTenantId."
        }
        
        $Profiles = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles"
        $ProfileDropdown.Items.Clear()
        
        foreach ($p in $Profiles.value) {
            $groups = @(Get-ProfileAssignments -Profile $p)
            $groupCandidates = if ($groups.Count -gt 0) { @(Get-ProfileGroupCandidates -Groups $groups) } else { @() }
            $groupSummary = if ($groups.Count -eq 0) { "Geen groep" } else { (($groups | ForEach-Object { "$($_.name) [$($_.type)]" }) -join "; ") }
            $displayTxt = "{0} (Groep: {1})" -f $p.displayName, $groupSummary
            [void]$ProfileDropdown.Items.Add([pscustomobject]@{ displayName = $displayTxt; profileId = $p.id; groups = $groups; groupCandidates = $groupCandidates })
        }
        
        $ProfileDropdown.IsEnabled = $true
        $HostnameBox.IsEnabled = $true
        $DeployBtn.IsEnabled = $true
        if ($ProfileDropdown.Items.Count -gt 0) { $ProfileDropdown.SelectedIndex = 0 }
        Update-GroupDecisionText
        $StatusTxt.Text = "Profielen geladen voor $TargetName! Klaar voor registratie."
    } catch {
        $err = $_.ErrorDetails.Message
        if ([string]::IsNullOrWhiteSpace($err)) { $err = $_.Exception.Message }
        if ([string]::IsNullOrWhiteSpace($err)) { $err = ($_ | Out-String).Trim() }
        
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
    $RebootBtn.IsEnabled = $false
    $LogBox.Clear()
    $profile = $ProfileDropdown.SelectedItem
    
    try {
        Write-ToolLog "Klanttenant: $Script:TargetTenantId"
        Write-ToolLog "Profiel: $($profile.displayName)"
        $serial = Get-LocalSerialNumber
        Write-ToolLog "Serienummer: $serial"
        $dynamicGroups = Invoke-CommunityOnline -TenantId $Script:TargetTenantId -Profile $profile -SelectedAddToGroup $GroupChoiceDropdown.SelectedItem
        foreach ($group in @($dynamicGroups)) {
            Write-ToolLog "Dynamische groep '$($group.name)' wordt automatisch verwerkt door Entra; de regel kan enige tijd nodig hebben."
        }
        # The Community script disconnects its Graph context after a successful
        # import/assignment. A second membership check here would therefore turn
        # an otherwise successful registration into a false failure.
        $RebootBtn.IsEnabled = $true
        $StatusTxt.Text = "GEREED! Autopilot-import en -Assign zijn succesvol afgerond."
        Write-ToolLog "GEREED. Herstart kan nu via knop 4."
    } catch {
       $RebootBtn.IsEnabled = $false
       Write-ToolLog "Registratie mislukt: $_"
    }
    $DeployBtn.IsEnabled = $true
})

$RebootBtn.Add_Click({
    $answer = [System.Windows.MessageBox]::Show(
        "Autopilot is geregistreerd. Wil je deze computer nu herstarten?",
        "Computer herstarten",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    if ($answer -eq [System.Windows.MessageBoxResult]::Yes) {
        Restart-Computer -Force
    }
})

# Laat window zien
$Window.ShowDialog() | Out-Null
