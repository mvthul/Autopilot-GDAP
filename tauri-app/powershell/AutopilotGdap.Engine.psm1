$script:PublicClientId = "6a87f18c-ab0a-4ef9-bb1c-587ae884b8e0"
$script:PartnerTenantId = "26aaae92-5737-48a2-b00c-27aff5b013e7"
$script:MinimumGraphAuthenticationVersion = [version]"2.38.0"
$script:PartnerCenterScope = "https://api.partnercenter.microsoft.com/user_impersonation"
$script:GraphScopes = @(
    "DeviceManagementServiceConfig.ReadWrite.All",
    "DeviceManagementServiceConfig.Read.All",
    "Group.Read.All",
    "GroupMember.ReadWrite.All",
    "Directory.Read.All"
)

function Get-AutopilotGdapDataPath {
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { return $env:LOCALAPPDATA }
    if (-not [string]::IsNullOrWhiteSpace($env:TEMP)) { return $env:TEMP }
    return [IO.Path]::GetTempPath()
}

function Test-OobeEnvironment {
    if ([Environment]::UserName -match '^defaultuser') { return $true }
    foreach ($path in @("HKLM:\SYSTEM\Setup", "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State")) {
        try {
            $setup = Get-ItemProperty -Path $path -ErrorAction Stop
            foreach ($name in @("OOBEInProgress", "SystemSetupInProgress", "SetupInProgress")) {
                $property = $setup.PSObject.Properties[$name]
                if ($property -and [int]$property.Value -eq 1) { return $true }
            }
            $imageState = [string]$setup.ImageState
            if ($imageState -match 'OOBE') { return $true }
        }
        catch { }
    }
    return $false
}

function Resolve-AuthenticationMode {
    param([AllowNull()][object]$IsOobe)
    if ($null -eq $IsOobe) { $IsOobe = Test-OobeEnvironment }
    if ([bool]$IsOobe) { return "browserOobe" }
    return "wam"
}

function Test-WamInteractiveSession {
    param([AllowNull()][object]$IsOobe)
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { return $false }
    if ($null -eq $IsOobe) { $IsOobe = Test-OobeEnvironment }
    if ([bool]$IsOobe) { return $false }
    return ([string]$env:CAPTURETECH_PARENT_HWND -match '^\d+$')
}

function New-AutopilotGdapState {
    param([Parameter(Mandatory = $true)][scriptblock]$Emitter)

    $localDataPath = Get-AutopilotGdapDataPath
    $tokenFolder = Join-Path $localDataPath "CaptureTech\AutopilotGDAP"
    $isOobe = Test-OobeEnvironment
    [pscustomobject]@{
        Emitter = $Emitter
        PublicClientId = $script:PublicClientId
        PartnerTenantId = $script:PartnerTenantId
        AuthMode = Resolve-AuthenticationMode -IsOobe $isOobe
        IsOobe = $isOobe
        WamAvailable = Test-WamInteractiveSession -IsOobe $isOobe
        PartnerCenterTokenPath = Join-Path $tokenFolder "partnercenter.v1.token"
        PartnerCenterAccessToken = $null
        BrowserCancellationPath = Join-Path $tokenFolder "browser-auth.cancel"
        BrowserInteractiveCompleted = $false
        WamBridgeReady = $false
        SessionAccount = ""
        SessionHomeAccountId = ""
        LegacyPartnerCenterTokenRetired = $false
        Customers = @()
        Profiles = @()
        TargetTenantId = ""
        ConnectedAccount = ""
        RegistrationCompleted = $false
    }
}

function Throw-AutopilotGdapError {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Details
    )
    $exception = [System.InvalidOperationException]::new($Message)
    $exception.Data["capturetechErrorCode"] = $Code
    $exception.Data["capturetechErrorMessage"] = $Message
    if (-not [string]::IsNullOrWhiteSpace($Details)) { $exception.Data["capturetechErrorDetails"] = $Details }
    throw $exception
}

function Get-AutopilotGdapError {
    param([Parameter(Mandatory = $true)][System.Management.Automation.ErrorRecord]$ErrorRecord)

    $exception = $ErrorRecord.Exception
    while ($exception) {
        if ($exception.Data -and $exception.Data.Contains("capturetechErrorCode")) {
            return [pscustomobject]@{
                code = [string]$exception.Data["capturetechErrorCode"]
                message = [string]$exception.Data["capturetechErrorMessage"]
                details = [string]$exception.Data["capturetechErrorDetails"]
            }
        }
        $exception = $exception.InnerException
    }

    $details = [string]$ErrorRecord.Exception.Message
    if ([string]::IsNullOrWhiteSpace($details)) { $details = ($ErrorRecord | Out-String).Trim() }
    $code = "operationFailed"
    $message = $details
    if ($details -match 'api\.partnercenter\.microsoft\.com.*(consent|AADSTS65001)|Partner Center.*(consent|AADSTS65001)') {
        $code = "partnerCenterConsentRequired"
        $message = "Partner Center-consent ontbreekt voor deze app. Voer de partner-inrichting opnieuw uit met een bevoegd account."
    }
    elseif ($details -match 'AADSTS90099|AADSTS700016|AADSTS65001|not been authorized|application.*not found') {
        $code = "customerConsentRequired"
        $message = "De CaptureTech-app is nog niet geautoriseerd in deze klanttenant. Laat een Global Administrator eerst klant-appconsent verlenen."
    }
    elseif ($details -match '403|Forbidden|Authorization_RequestDenied') {
        $code = "gdapPimDenied"
        $message = "Toegang geweigerd. Controleer of je actieve GDAP/PIM-rollen voor deze klant voldoende zijn."
    }
    elseif ($details -match 'canceled|cancelled|user_cancelled|authentication_canceled') {
        $code = "authCancelled"
        $message = "De aanmelding is geannuleerd."
    }
    elseif ($details -match 'WAM|Web Account Manager|BrokerPlugin|Parent.*window|interactive Windows user') {
        $code = "wamUnavailable"
        $message = "Windows Web Account Manager kan niet worden gestart. Start de app in een normale interactieve Windows-sessie of gebruik de OOBE-browserflow."
    }
    elseif ($details -match 'MsalUiRequiredException|interaction_required|login_required|claims challenge|conditional access|AADSTS50076|AADSTS50079|AADSTS50158') {
        $code = "authenticationRequired"
        $message = "Extra verificatie is nodig voor het geselecteerde account."
    }
    [pscustomobject]@{ code = $code; message = $message; details = $details }
}

function Write-EngineEvent {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [ValidateSet("log", "status", "progress")][string]$Event = "log",
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("info", "success", "warning", "error")][string]$Level = "info",
        [bool]$Technical = $false,
        [ValidateSet("login", "customer", "configure", "register", "complete")][string]$Step
    )
    $payload = [ordered]@{
        message = $Message
        level = $Level
        technical = $Technical
    }
    if ($Step) { $payload.step = $Step }
    & $State.Emitter $Event $payload
}

function Ensure-GraphAuthenticationModule {
    param([Parameter(Mandatory = $true)][object]$State)

    $available = @(Get-Module -ListAvailable -Name Microsoft.Graph.Authentication | Where-Object { $_.Version -ge $script:MinimumGraphAuthenticationVersion })
    if ($available.Count -eq 0) {
        Write-EngineEvent -State $State -Message "Microsoft Graph-module wordt geïnstalleerd voor de huidige Windows-gebruiker." -Level info
        Install-Module -Name Microsoft.Graph.Authentication -MinimumVersion $script:MinimumGraphAuthenticationVersion -Scope CurrentUser -Force -AllowClobber -Repository PSGallery -ErrorAction Stop | Out-Null
    }
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop -Verbose:$false | Out-Null
    $module = Get-Module -Name Microsoft.Graph.Authentication | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $module -or $module.Version -lt $script:MinimumGraphAuthenticationVersion) {
        Throw-AutopilotGdapError -Code "wamUnavailable" -Message "Microsoft Graph Authentication $($script:MinimumGraphAuthenticationVersion) of hoger is vereist voor WAM."
    }
    return $module
}

function Retire-LegacyPartnerCenterToken {
    param([Parameter(Mandatory = $true)][object]$State)
    if ($State.LegacyPartnerCenterTokenRetired) { return }
    $State.LegacyPartnerCenterTokenRetired = $true
    if (Test-Path -LiteralPath $State.PartnerCenterTokenPath) {
        Remove-Item -LiteralPath $State.PartnerCenterTokenPath -Force -ErrorAction SilentlyContinue
        Write-EngineEvent -State $State -Message "De oude lokale Partner Center-token-cache is verwijderd; deze app bewaart geen eigen refresh-tokenbestand meer." -Level info -Technical $true
    }
}

function Invoke-BrowserAuthorizationCodeFlow {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][string]$AuthorizeUri,
        [Parameter(Mandatory = $true)][string]$RedirectUri,
        [Parameter(Mandatory = $true)][scriptblock]$ExchangeCode,
        [Parameter(Mandatory = $true)][string]$Purpose
    )

    $listener = New-Object System.Net.HttpListener
    $cancellationPath = [string]$State.BrowserCancellationPath
    try {
        # A separate, native Tauri command can place this marker when the
        # operator chooses to open the customer-specific admin-consent page.
        # Remove an old marker before every browser flow so a previous action
        # can never cancel a new login.
        if (-not [string]::IsNullOrWhiteSpace($cancellationPath)) {
            Remove-Item -LiteralPath $cancellationPath -Force -ErrorAction SilentlyContinue
        }
        $listener.Prefixes.Add($RedirectUri)
        $listener.Start()
    }
    catch {
        $listener.Close()
        throw "$Purpose kan de lokale callback niet starten op $RedirectUri. Sluit een andere appinstantie en probeer opnieuw. Details: $($_.Exception.Message)"
    }

    try {
        Write-EngineEvent -State $State -Message "$Purpose opent in je standaardbrowser. Meld aan met je IT-Hulp-account." -Level info
        Start-Process $AuthorizeUri -ErrorAction Stop
        $result = $listener.BeginGetContext($null, $null)
        $timeoutAt = [DateTime]::UtcNow.AddMinutes(5)
        while (-not $result.AsyncWaitHandle.WaitOne(250)) {
            if (-not [string]::IsNullOrWhiteSpace($cancellationPath) -and (Test-Path -LiteralPath $cancellationPath)) {
                Remove-Item -LiteralPath $cancellationPath -Force -ErrorAction SilentlyContinue
                throw "$Purpose is onderbroken om de klant-app in te stellen. Voltooi de eenmalige admin consent en kies daarna opnieuw Verbinden."
            }
            if ([DateTime]::UtcNow -ge $timeoutAt) {
                throw "De browseraanmelding duurde langer dan vijf minuten."
            }
        }
        $context = $listener.EndGetContext($result)
        $query = $context.Request.QueryString
        $success = -not [string]::IsNullOrWhiteSpace([string]$query["code"])
        $html = if ($success) {
            "<html><body><h2>Aanmelding voltooid</h2><p>U kunt dit venster sluiten en teruggaan naar CaptureTech Autopilot GDAP.</p></body></html>"
        } else {
            "<html><body><h2>Aanmelding niet voltooid</h2><p>U kunt dit venster sluiten.</p></body></html>"
        }
        $bytes = [Text.Encoding]::UTF8.GetBytes($html)
        $context.Response.ContentType = "text/html; charset=utf-8"
        $context.Response.ContentLength64 = $bytes.Length
        $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $context.Response.OutputStream.Close()
        if (-not $success) {
            $description = [string]$query["error_description"]
            if ([string]::IsNullOrWhiteSpace($description)) { $description = [string]$query["error"] }
            throw "$Purpose is afgebroken: $description"
        }
        return & $ExchangeCode ([string]$query["code"])
    }
    finally {
        if (-not [string]::IsNullOrWhiteSpace($cancellationPath)) {
            Remove-Item -LiteralPath $cancellationPath -Force -ErrorAction SilentlyContinue
        }
        if ($listener.IsListening) { $listener.Stop() }
        $listener.Close()
    }
}

function Get-BrowserGraphAccessToken {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][string]$TenantId,
        [Parameter(Mandatory = $true)][string[]]$Scopes
    )
    $scope = (($Scopes + @("openid", "profile", "offline_access")) | Select-Object -Unique) -join " "
    $authority = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0"
    $redirectUri = "http://localhost:8766/"
    $prompts = if ($State.BrowserInteractiveCompleted) { @("none", "select_account") } else { @("select_account") }
    foreach ($prompt in $prompts) {
        $authorizeUri = "$authority/authorize?client_id=$([uri]::EscapeDataString($State.PublicClientId))&response_type=code&redirect_uri=$([uri]::EscapeDataString($redirectUri))&response_mode=query&scope=$([uri]::EscapeDataString($scope))&prompt=$prompt"
        $exchange = {
            param([string]$Code)
            try {
                Invoke-RestMethod -Method POST -Uri "$authority/token" -Body @{
                    grant_type = "authorization_code"
                    client_id = $State.PublicClientId
                    code = $Code
                    redirect_uri = $redirectUri
                    scope = $scope
                } -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
            }
            catch {
                $detail = $_.ErrorDetails.Message
                if ([string]::IsNullOrWhiteSpace($detail)) { $detail = $_.Exception.Message }
                throw "Graph-token ophalen mislukt: $detail"
            }
        }.GetNewClosure()
        try {
            $token = Invoke-BrowserAuthorizationCodeFlow -State $State -AuthorizeUri $authorizeUri -RedirectUri $redirectUri -ExchangeCode $exchange -Purpose "Microsoft Graph-aanmelding"
            $State.BrowserInteractiveCompleted = $true
            return [pscustomobject]@{ accessToken = [string]$token.access_token; account = ""; homeAccountId = ""; tenantId = $TenantId }
        }
        catch {
            if ($prompt -eq "none" -and $_.Exception.Message -match 'login_required|interaction_required|AADSTS50058') { continue }
            throw
        }
    }
    Throw-AutopilotGdapError -Code "authenticationRequired" -Message "De browser-SSO-sessie kon niet worden hergebruikt."
}

function Get-MsalAssemblyPath {
    param(
        [Parameter(Mandatory = $true)][object]$Module,
        [Parameter(Mandatory = $true)][string]$FileName
    )
    $matches = @(Get-ChildItem -LiteralPath $Module.ModuleBase -Filter $FileName -File -Recurse -ErrorAction SilentlyContinue)
    if ($matches.Count -eq 0) { return $null }
    $desktopMatch = @($matches | Where-Object { $_.FullName -match '[\\/]Dependencies[\\/]Desktop[\\/]' } | Select-Object -First 1)
    if ($desktopMatch.Count -gt 0) { return [string]$desktopMatch[0].FullName }
    return [string]$matches[0].FullName
}

function Initialize-WamBroker {
    param([Parameter(Mandatory = $true)][object]$State)
    if ($State.AuthMode -ne "wam") { return }
    if ($State.WamBridgeReady) { return }
    if (-not (Test-WamInteractiveSession -IsOobe $State.IsOobe)) {
        Throw-AutopilotGdapError -Code "wamUnavailable" -Message "WAM is alleen beschikbaar in een normale interactieve Windows-sessie. Start deze app via OOBE voor de browserflow."
    }
    $module = Ensure-GraphAuthenticationModule -State $State
    $msalPath = Get-MsalAssemblyPath -Module $module -FileName "Microsoft.Identity.Client.dll"
    $brokerPath = Get-MsalAssemblyPath -Module $module -FileName "Microsoft.Identity.Client.Broker.dll"
    $nativeInteropPath = Get-MsalAssemblyPath -Module $module -FileName "Microsoft.Identity.Client.NativeInterop.dll"
    foreach ($assemblyPath in @($msalPath, $brokerPath, $nativeInteropPath)) {
        if ([string]::IsNullOrWhiteSpace([string]$assemblyPath) -or -not (Test-Path -LiteralPath $assemblyPath)) {
            Throw-AutopilotGdapError -Code "wamUnavailable" -Message "De geïnstalleerde Graph-module bevat niet alle WAM-onderdelen. Installeer Microsoft.Graph.Authentication opnieuw." -Details $assemblyPath
        }
        $loaded = @([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object {
            try { $_.Location -eq $assemblyPath }
            catch { $false }
        })
        if ($loaded.Count -eq 0) { [void][System.Reflection.Assembly]::LoadFrom($assemblyPath) }
    }
    if (-not ("CaptureTech.AutopilotGdap.WamBroker" -as [type])) {
        $bridgeSource = @'
using System;
using Microsoft.Identity.Client;
using Microsoft.Identity.Client.Broker;

namespace CaptureTech.AutopilotGdap
{
    public sealed class WamToken
    {
        public string AccessToken { get; set; }
        public string Account { get; set; }
        public string HomeAccountId { get; set; }
        public string TenantId { get; set; }
    }

    public static class WamBroker
    {
        private static readonly object Gate = new object();
        private static IPublicClientApplication application;
        private static IAccount sessionAccount;

        public static void Initialize(string clientId, long parentWindowHandle)
        {
            lock (Gate)
            {
                if (application != null) return;
                var builder = PublicClientApplicationBuilder.Create(clientId)
                    .WithAuthority(AzureCloudInstance.AzurePublic, "organizations")
                    .WithRedirectUri("ms-appx-web://Microsoft.AAD.BrokerPlugin/" + clientId)
                    .WithParentActivityOrWindow(() => new IntPtr(parentWindowHandle));
                application = BrokerExtension.WithBroker(
                    builder,
                    new BrokerOptions(BrokerOptions.OperatingSystems.Windows)).Build();
            }
        }

        public static WamToken Acquire(string tenantId, string[] scopes, bool interactive, bool selectAccount)
        {
            if (application == null) throw new InvalidOperationException("WAM is niet geïnitialiseerd.");
            var authority = "https://login.microsoftonline.com/" + tenantId;
            AuthenticationResult result;
            if (interactive)
            {
                var request = application.AcquireTokenInteractive(scopes).WithAuthority(authority);
                if (sessionAccount != null && !selectAccount) request = request.WithAccount(sessionAccount);
                if (selectAccount) request = request.WithPrompt(Prompt.SelectAccount);
                result = request.ExecuteAsync().GetAwaiter().GetResult();
            }
            else
            {
                if (sessionAccount == null) throw new MsalUiRequiredException("no_session_account", "Er is geen IT-Hulp-account geselecteerd in deze appsessie.");
                result = application.AcquireTokenSilent(scopes, sessionAccount).WithAuthority(authority).ExecuteAsync().GetAwaiter().GetResult();
            }
            sessionAccount = result.Account;
            return new WamToken
            {
                AccessToken = result.AccessToken,
                Account = result.Account == null ? String.Empty : result.Account.Username,
                HomeAccountId = result.Account == null || result.Account.HomeAccountId == null ? String.Empty : result.Account.HomeAccountId.Identifier,
                TenantId = result.TenantId
            };
        }

        public static void ResetSession()
        {
            lock (Gate) { sessionAccount = null; }
        }
    }
}
'@
        Add-Type -TypeDefinition $bridgeSource -ReferencedAssemblies @($msalPath, $brokerPath) -Language CSharp -ErrorAction Stop
    }
    try {
        [CaptureTech.AutopilotGdap.WamBroker]::Initialize($State.PublicClientId, [int64]$env:CAPTURETECH_PARENT_HWND)
    }
    catch {
        Throw-AutopilotGdapError -Code "wamUnavailable" -Message "Windows Web Account Manager kon niet worden voorbereid. Voer de partner-appinrichting opnieuw uit en controleer de broker redirect URI." -Details $_.Exception.Message
    }
    $State.WamBridgeReady = $true
}

function ConvertTo-MsalScopes {
    param([Parameter(Mandatory = $true)][string[]]$Scopes)
    return @($Scopes | ForEach-Object {
        if ($_ -match '^https://') { [string]$_ } else { "https://graph.microsoft.com/$($_)" }
    })
}

function Get-WamAccessToken {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][string]$TenantId,
        [Parameter(Mandatory = $true)][string[]]$Scopes,
        [switch]$Interactive,
        [switch]$SelectAccount,
        [switch]$AllowInteractiveFallback
    )
    Initialize-WamBroker -State $State
    $msalScopes = [string[]](ConvertTo-MsalScopes -Scopes $Scopes)
    try {
        $token = [CaptureTech.AutopilotGdap.WamBroker]::Acquire($TenantId, $msalScopes, [bool]$Interactive, [bool]$SelectAccount)
    }
    catch {
        $errorInfo = Get-AutopilotGdapError -ErrorRecord $_
        if ($errorInfo.code -ne "authenticationRequired" -or -not $AllowInteractiveFallback -or $Interactive) { throw }
        Write-EngineEvent -State $State -Message "Windows vraagt aanvullende verificatie voor het eerder gekozen IT-Hulp-account." -Level info -Step login
        try {
            $token = [CaptureTech.AutopilotGdap.WamBroker]::Acquire($TenantId, $msalScopes, $true, $false)
        }
        catch { throw }
    }
    $State.SessionAccount = [string]$token.Account
    $State.SessionHomeAccountId = [string]$token.HomeAccountId
    return [pscustomobject]@{ accessToken = [string]$token.AccessToken; account = [string]$token.Account; homeAccountId = [string]$token.HomeAccountId; tenantId = [string]$token.TenantId }
}

function Get-GraphAccessToken {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][string]$TenantId,
        [Parameter(Mandatory = $true)][string[]]$Scopes,
        [switch]$Interactive,
        [switch]$SelectAccount
    )
    if ($State.AuthMode -eq "wam") {
        return Get-WamAccessToken -State $State -TenantId $TenantId -Scopes $Scopes -Interactive:$Interactive -SelectAccount:$SelectAccount -AllowInteractiveFallback:(-not $Interactive)
    }
    return Get-BrowserGraphAccessToken -State $State -TenantId $TenantId -Scopes $Scopes
}

function Connect-GraphTenant {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][string]$TenantId,
        [Parameter(Mandatory = $true)][string[]]$Scopes,
        [switch]$Interactive,
        [switch]$SelectAccount
    )
    Ensure-GraphAuthenticationModule -State $State
    $token = Get-GraphAccessToken -State $State -TenantId $TenantId -Scopes $Scopes -Interactive:$Interactive -SelectAccount:$SelectAccount
    $secureToken = ConvertTo-SecureString $token.accessToken -AsPlainText -Force
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    Connect-MgGraph -AccessToken $secureToken -ErrorAction Stop -NoWelcome | Out-Null
    $context = Get-MgContext
    if (-not $context -or [string]$context.TenantId -ne [string]$TenantId) {
        throw "Graph heeft de verkeerde tenantcontext geopend. Verwacht: $TenantId."
    }
    $State.ConnectedAccount = if (-not [string]::IsNullOrWhiteSpace([string]$token.account)) { [string]$token.account } else { [string]$context.Account }
    Write-EngineEvent -State $State -Message "Graph-verbinding met tenant $TenantId is actief." -Level success
}

function Get-BrowserPartnerCenterAccessToken {
    param([Parameter(Mandatory = $true)][object]$State)
    $resource = "https://api.partnercenter.microsoft.com"
    $tokenUri = "https://login.microsoftonline.com/common/oauth2/token"
    $redirectUri = "http://localhost:8765/"
    $prompts = if ($State.BrowserInteractiveCompleted) { @("none", "select_account") } else { @("select_account") }
    foreach ($prompt in $prompts) {
        $authorizeUri = "https://login.microsoftonline.com/common/oauth2/authorize?client_id=$([uri]::EscapeDataString($State.PublicClientId))&response_type=code&redirect_uri=$([uri]::EscapeDataString($redirectUri))&response_mode=query&resource=$([uri]::EscapeDataString($resource))&prompt=$prompt"
        $exchange = {
            param([string]$Code)
            try {
                Invoke-RestMethod -Method POST -Uri $tokenUri -Body @{
                    grant_type = "authorization_code"
                    client_id = $State.PublicClientId
                    code = $Code
                    redirect_uri = $redirectUri
                    resource = $resource
                } -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
            }
            catch {
                $detail = $_.ErrorDetails.Message
                if ([string]::IsNullOrWhiteSpace($detail)) { $detail = $_.Exception.Message }
                throw "Partner Center-token ophalen mislukt: $detail"
            }
        }.GetNewClosure()
        try {
            $token = Invoke-BrowserAuthorizationCodeFlow -State $State -AuthorizeUri $authorizeUri -RedirectUri $redirectUri -ExchangeCode $exchange -Purpose "Partner Center-aanmelding"
            $State.BrowserInteractiveCompleted = $true
            return [string]$token.access_token
        }
        catch {
            if ($prompt -eq "none" -and $_.Exception.Message -match 'login_required|interaction_required|AADSTS50058') { continue }
            throw
        }
    }
    Throw-AutopilotGdapError -Code "authenticationRequired" -Message "Partner Center kon de browser-SSO-sessie niet hergebruiken."
}

function Get-PartnerCenterAccessToken {
    param([Parameter(Mandatory = $true)][object]$State)
    if (-not [string]::IsNullOrWhiteSpace([string]$State.PartnerCenterAccessToken)) { return [string]$State.PartnerCenterAccessToken }
    try {
        if ($State.AuthMode -eq "wam") {
            $token = Get-WamAccessToken -State $State -TenantId $State.PartnerTenantId -Scopes @($script:PartnerCenterScope) -AllowInteractiveFallback
            $State.PartnerCenterAccessToken = [string]$token.accessToken
        }
        else {
            $State.PartnerCenterAccessToken = Get-BrowserPartnerCenterAccessToken -State $State
        }
    }
    catch {
        $details = $_.Exception.Message
        if ($details -match 'consent|AADSTS65001|AADSTS700016') {
            Throw-AutopilotGdapError -Code "partnerCenterConsentRequired" -Message "Partner Center-consent ontbreekt voor de CaptureTech-app. Voer Setup-AutopilotApp.ps1 opnieuw uit met een bevoegd partneraccount." -Details $details
        }
        throw
    }
    Retire-LegacyPartnerCenterToken -State $State
    return [string]$State.PartnerCenterAccessToken
}

function Get-PartnerCenterCustomers {
    param([Parameter(Mandatory = $true)][object]$State)
    if ([string]::IsNullOrWhiteSpace([string]$State.PartnerCenterAccessToken)) {
        $State.PartnerCenterAccessToken = Get-PartnerCenterAccessToken -State $State
    }
    $headers = @{
        Authorization = "Bearer $($State.PartnerCenterAccessToken)"
        Accept = "application/json"
        "MS-RequestId" = [guid]::NewGuid().ToString()
        "MS-CorrelationId" = [guid]::NewGuid().ToString()
        "MS-Contract-Version" = "v1"
    }
    $customers = [System.Collections.Generic.List[object]]::new()
    $uri = "https://api.partnercenter.microsoft.com/v1/customers"
    do {
        $page = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers -ErrorAction Stop
        foreach ($customer in @($page.items)) {
            $name = [string]$customer.companyProfile.companyName
            if ([string]::IsNullOrWhiteSpace($name)) { $name = [string]$customer.companyProfile.domain }
            $domain = [string]$customer.companyProfile.domain
            $tenantId = [string]$customer.id
            if ([string]::IsNullOrWhiteSpace($tenantId)) { continue }
            [void]$customers.Add([pscustomobject]@{
                tenantId = $tenantId
                customerName = $name
                tenantDomain = $domain
                displayName = "$name [$domain]"
            })
        }
        $next = [string]$page.links.next.uri
        if ([string]::IsNullOrWhiteSpace($next)) { $uri = $null }
        elseif ($next -match "^https?://") { $uri = $next }
        else { $uri = "https://api.partnercenter.microsoft.com$next" }
    } while ($uri)
    return @($customers | Sort-Object tenantId -Unique)
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
    return @($items)
}

function Get-GroupInfo {
    param([Parameter(Mandatory = $true)][string]$GroupId)
    $select = '$select=id,displayName,groupTypes,membershipRule,membershipRuleProcessingState,securityEnabled,mailEnabled'
    $groupUri = "https://graph.microsoft.com/v1.0/groups/{0}?{1}" -f $GroupId, $select
    $group = Invoke-MgGraphRequest -Method GET -Uri $groupUri -OutputType PSObject -ErrorAction Stop
    $isDynamic = @($group.groupTypes) -contains "DynamicMembership"
    $escapedName = ([string]$group.displayName).Replace("'", "''")
    $encodedFilter = [uri]::EscapeDataString("displayName eq '$escapedName'")
    $sameNameGroups = @(Get-GraphCollection -Uri ("https://graph.microsoft.com/v1.0/groups?%24filter={0}&%24select=id,displayName" -f $encodedFilter))
    $children = @()
    $parents = @()
    try { $children = @(Get-GraphCollection -Uri "https://graph.microsoft.com/v1.0/groups/$GroupId/members/microsoft.graph.group") } catch { }
    try { $parents = @(Get-GraphCollection -Uri "https://graph.microsoft.com/v1.0/groups/$GroupId/transitiveMemberOf/microsoft.graph.group") } catch { }
    [pscustomobject]@{
        id = [string]$group.id
        name = [string]$group.displayName
        type = if ($isDynamic) { "Dynamisch" } else { "Statisch" }
        isDynamic = $isDynamic
        isExclusion = $false
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
        $groupId = [string]$target.groupId
        if ([string]::IsNullOrWhiteSpace($groupId)) { continue }
        $info = Get-GroupInfo -GroupId $groupId
        $info.isExclusion = ([string]$target.'@odata.type' -match "exclusion")
        $groups += $info
    }
    return @($groups)
}

function Get-ProfileGroupCandidates {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][object[]]$Groups
    )
    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($group in @($Groups | Where-Object { -not $_.isDynamic -and -not $_.isExclusion })) {
        if ($group.matchingGroupCount -ne 1) {
            Write-EngineEvent -State $State -Message "Statische groep '$($group.name)' is niet uniek en wordt niet als -AddToGroup-kandidaat gebruikt." -Level warning
            continue
        }
        if (-not $group.securityEnabled) {
            Write-EngineEvent -State $State -Message "Statische groep '$($group.name)' is geen beveiligingsgroep en wordt niet als -AddToGroup-kandidaat gebruikt." -Level warning
            continue
        }
        [void]$candidates.Add([pscustomobject]@{
            id = [string]$group.id
            name = [string]$group.name
            displayName = "$($group.name) - direct statisch"
            source = "Direct toegewezen statische groep"
        })
    }
    foreach ($dynamicGroup in @($Groups | Where-Object { $_.isDynamic -and -not $_.isExclusion })) {
        foreach ($child in @($dynamicGroup.childGroups)) {
            if (@($child.groupTypes) -contains "DynamicMembership") { continue }
            if ([string]::IsNullOrWhiteSpace([string]$child.id)) { continue }
            $childInfo = Get-GroupInfo -GroupId ([string]$child.id)
            if ($childInfo.isDynamic -or -not $childInfo.securityEnabled -or $childInfo.matchingGroupCount -ne 1) { continue }
            [void]$candidates.Add([pscustomobject]@{
                id = [string]$childInfo.id
                name = [string]$childInfo.name
                displayName = "$($childInfo.name) - nested statisch onder $($dynamicGroup.name)"
                source = "Nested onder dynamische groep '$($dynamicGroup.name)'"
            })
        }
    }
    return @($candidates | Group-Object id | ForEach-Object { $_.Group[0] } | Sort-Object displayName)
}

function Get-CommunityScriptPath {
    param([Parameter(Mandatory = $true)][object]$State)
    $command = Get-Command Get-WindowsAutopilotInfoCommunity.ps1 -ErrorAction SilentlyContinue
    if (-not $command) { $command = Get-Command Get-WindowsAutopilotInfoCommunity -ErrorAction SilentlyContinue }
    if (-not $command) {
        Write-EngineEvent -State $State -Message "Community-script ontbreekt en wordt vanuit PSGallery geïnstalleerd." -Level info
        Install-Script -Name Get-WindowsAutopilotInfoCommunity -Scope CurrentUser -Force -ErrorAction Stop | Out-Null
        $command = Get-Command Get-WindowsAutopilotInfoCommunity.ps1 -ErrorAction SilentlyContinue
        if (-not $command) { $command = Get-Command Get-WindowsAutopilotInfoCommunity -ErrorAction Stop }
    }
    return [string]$command.Source
}

function Test-TechnicalCommunityOutput {
    param([Parameter(Mandatory = $true)][string]$Text)
    return $Text -match '^(Loading module from path|Importing (cmdlet|function|alias)|Version \d+ module detected|GET https://graph\.microsoft\.com/|POST https://graph\.microsoft\.com/|PUT https://graph\.microsoft\.com/|PATCH https://graph\.microsoft\.com/|received \d+-byte response|Perform operation |Operation ''.*'' (complete|with following parameters)|\s*ClientId\s+:|\{\s*$)'
}

function Write-CommunityRecord {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][object]$Record,
        [bool]$Verbose
    )
    $text = ($Record | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    $technical = Test-TechnicalCommunityOutput -Text $text
    if ($technical -and -not $Verbose) { return }
    $level = if ($Record -is [System.Management.Automation.ErrorRecord]) { "error" } else { "info" }
    Write-EngineEvent -State $State -Message $text -Level $level -Technical $technical
}

function Invoke-CommunityOnline {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][string]$TenantId,
        [Parameter(Mandatory = $true)][object]$Profile,
        [AllowNull()][object]$SelectedAddToGroup,
        [string]$Hostname,
        [bool]$Verbose
    )
    $context = Get-MgContext
    if (-not $context -or [string]$context.TenantId -ne [string]$TenantId) {
        throw "De actieve Graph-sessie hoort niet bij klanttenant $TenantId."
    }
    $source = Get-CommunityScriptPath -State $State
    $tempPath = Join-Path $env:TEMP ("Get-WindowsAutopilotInfoCommunity-{0}.ps1" -f ([guid]::NewGuid()))
    $scriptText = Get-Content -LiteralPath $source -Raw -ErrorAction Stop
    $reuseBlock = @'
                    $existingContext = Get-MgContext
                    if ($existingContext) {
                        $graph = $existingContext
                        Write-Host "Using existing Graph session for tenant $($existingContext.TenantId)"
                    }
                    else {
                        throw "No existing Graph session is available for the Community script."
                    }
'@
    $connectRegex = [regex]::new('(?m)^\s*\$graph\s*=\s*Connect-MgGraph\s+-Scopes\s+\$scopes\s*$')
    $patchedText = $connectRegex.Replace($scriptText, $reuseBlock.TrimEnd(), 1)
    if ($patchedText -eq $scriptText) {
        throw "De actuele Community-scriptversie heeft een onbekende Graph-loginstructuur. Er is niet naar WAM teruggevallen."
    }
    $scriptText = $patchedText.Replace('setx MSAL_FORCE_WAM 0', '# Existing Graph session is reused')
    $scriptText = $scriptText.Replace('setx MSAL_FORCE_WAM 1', '# WAM setting is not changed by this tool')
    Set-Content -LiteralPath $tempPath -Value $scriptText -Encoding UTF8 -ErrorAction Stop
    try {
        $communityCommand = Get-Command -Name $tempPath -ErrorAction Stop
        $requiredParameters = @("Online", "TenantId", "Assign")
        $missingParameters = @($requiredParameters | Where-Object { -not $communityCommand.Parameters.ContainsKey($_) })
        if ($missingParameters.Count -gt 0) {
            throw "De actuele Community-scriptversie ondersteunt niet de vereiste parameter(s): $($missingParameters -join ', ')."
        }
        $parameters = @{ Online = $true; TenantId = $TenantId; Assign = $true }
        if ($Verbose) { $parameters.Verbose = $true }
        if (-not [string]::IsNullOrWhiteSpace($Hostname)) { $parameters.AssignedComputerName = $Hostname.Trim() }
        if ($SelectedAddToGroup) {
            $parameters.AddToGroup = [string]$SelectedAddToGroup.name
            Write-EngineEvent -State $State -Message "Statische groepsactie: -AddToGroup '$($SelectedAddToGroup.name)'." -Level info
        }
        foreach ($group in @($Profile.groups | Where-Object { $_.isDynamic -and -not $_.isExclusion })) {
            Write-EngineEvent -State $State -Message "Dynamische groep '$($group.name)': geen handmatige toevoeging. Entra beoordeelt de membership-regel automatisch." -Level info
        }
        $errors = [System.Collections.Generic.List[string]]::new()
        Write-EngineEvent -State $State -Message "Community-script wordt gestart met -Online, -TenantId en -Assign." -Level info -Step register
        & $tempPath @parameters *>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { [void]$errors.Add(($_ | Out-String).Trim()) }
            Write-CommunityRecord -State $State -Record $_ -Verbose $Verbose
        }
        if ($errors.Count -gt 0) { throw ($errors -join "`n") }
    }
    finally {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
}

function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

function Invoke-AutopilotPreflight {
    param([Parameter(Mandatory = $true)][object]$State)
    [pscustomobject]@{
        isAdministrator = Test-IsAdministrator
        powershellVersion = $PSVersionTable.PSVersion.ToString()
        graphModuleInstalled = [bool](Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)
        authMode = [string]$State.AuthMode
        isOobe = [bool]$State.IsOobe
        wamAvailable = [bool]$State.WamAvailable
    }
}

function Invoke-PartnerLogin {
    param([Parameter(Mandatory = $true)][object]$State)
    $State.PartnerCenterAccessToken = $null
    if ($State.AuthMode -eq "wam") {
        Write-EngineEvent -State $State -Message "Windows opent de accountkiezer voor je IT-Hulp-account." -Level info -Step login
        Connect-GraphTenant -State $State -TenantId $State.PartnerTenantId -Scopes $script:GraphScopes -Interactive -SelectAccount
    }
    else {
        Write-EngineEvent -State $State -Message "OOBE is actief: de browser wordt gebruikt voor de IT-Hulp-aanmelding." -Level info -Step login
        Connect-GraphTenant -State $State -TenantId $State.PartnerTenantId -Scopes $script:GraphScopes -Interactive
    }
    Write-EngineEvent -State $State -Message "IT-Hulp-account is aangemeld. Partner Center-klanten kunnen worden geladen." -Level success -Step customer
    return [pscustomobject]@{ tenantId = $State.PartnerTenantId; account = $State.ConnectedAccount; authMode = $State.AuthMode; isOobe = [bool]$State.IsOobe }
}

function Invoke-LoadCustomers {
    param([Parameter(Mandatory = $true)][object]$State)
    Write-EngineEvent -State $State -Message "Partner Center-klantenlijst wordt opgehaald." -Level info
    $State.Customers = @(Get-PartnerCenterCustomers -State $State)
    [pscustomobject]@{ customers = @($State.Customers) }
}

function Invoke-ConnectCustomer {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][string]$TenantId
    )
    $customer = @($State.Customers | Where-Object { $_.tenantId -eq $TenantId } | Select-Object -First 1)
    if ($customer.Count -ne 1) { throw "De gekozen klanttenant komt niet uit de actieve Partner Center-klantenlijst." }
    Connect-GraphTenant -State $State -TenantId $TenantId -Scopes $script:GraphScopes
    $State.TargetTenantId = $TenantId
    $State.RegistrationCompleted = $false
    Write-EngineEvent -State $State -Message "Verbonden met $($customer[0].customerName)." -Level success
    [pscustomobject]@{ tenantId = $TenantId; account = $State.ConnectedAccount; authMode = $State.AuthMode }
}

function Invoke-ResetSession {
    param([Parameter(Mandatory = $true)][object]$State)
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    if ("CaptureTech.AutopilotGdap.WamBroker" -as [type]) {
        [CaptureTech.AutopilotGdap.WamBroker]::ResetSession()
    }
    $State.PartnerCenterAccessToken = $null
    $State.BrowserInteractiveCompleted = $false
    $State.SessionAccount = ""
    $State.SessionHomeAccountId = ""
    $State.ConnectedAccount = ""
    $State.Customers = @()
    $State.Profiles = @()
    $State.TargetTenantId = ""
    $State.RegistrationCompleted = $false
    Write-EngineEvent -State $State -Message "De appsessie is gewist. Windows-accounts en WAM-tokens van andere apps zijn niet gewijzigd." -Level info -Step login
    [pscustomobject]@{ authMode = $State.AuthMode; sessionReset = $true }
}

function Invoke-LoadProfiles {
    param([Parameter(Mandatory = $true)][object]$State)
    if ([string]::IsNullOrWhiteSpace($State.TargetTenantId)) { throw "Kies eerst een klanttenant." }
    $context = Get-MgContext
    if (-not $context -or [string]$context.TenantId -ne [string]$State.TargetTenantId) { throw "De Graph-sessie hoort niet bij de geselecteerde klanttenant." }
    Write-EngineEvent -State $State -Message "Autopilot-profielen en groepsassignments worden opgehaald." -Level info
    $response = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles" -ErrorAction Stop
    $profiles = @()
    foreach ($profile in @($response.value)) {
        $groups = @(Get-ProfileAssignments -Profile $profile)
        $candidates = if ($groups.Count -gt 0) { @(Get-ProfileGroupCandidates -State $State -Groups $groups) } else { @() }
        $profiles += [pscustomobject]@{
            profileId = [string]$profile.id
            displayName = [string]$profile.displayName
            groups = @($groups | ForEach-Object {
                [pscustomobject]@{
                    id = $_.id; name = $_.name; type = $_.type; isDynamic = $_.isDynamic; isExclusion = $_.isExclusion
                    membershipRule = $_.membershipRule; membershipRuleProcessingState = $_.membershipRuleProcessingState; hasNested = $_.hasNested
                    securityEnabled = $_.securityEnabled; mailEnabled = $_.mailEnabled
                }
            })
            groupCandidates = @($candidates)
        }
    }
    $State.Profiles = @($profiles)
    [pscustomobject]@{ profiles = @($State.Profiles) }
}

function Invoke-RegisterDevice {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][string]$ProfileId,
        [string]$StaticGroupId,
        [string]$Hostname,
        [bool]$Verbose
    )
    $profile = @($State.Profiles | Where-Object { $_.profileId -eq $ProfileId } | Select-Object -First 1)
    if ($profile.Count -ne 1) { throw "Het gekozen profiel is niet meer actief in deze sessie. Laad de profielen opnieuw." }
    $candidates = @($profile[0].groupCandidates)
    $selectedGroup = $null
    if ($candidates.Count -eq 1) { $selectedGroup = $candidates[0] }
    elseif ($candidates.Count -gt 1) {
        if ([string]::IsNullOrWhiteSpace($StaticGroupId)) { throw "Kies eerst een statische groep voor -AddToGroup." }
        $matchingCandidates = @($candidates | Where-Object { $_.id -eq $StaticGroupId })
        if ($matchingCandidates.Count -ne 1) { throw "De gekozen groep is geen geldige statische kandidaat voor dit profiel." }
        $selectedGroup = $matchingCandidates[0]
    }
    if (-not [string]::IsNullOrWhiteSpace($Hostname) -and $Hostname -notmatch '^[A-Za-z0-9-]{1,15}$') {
        throw "De apparaatnaam mag maximaal 15 tekens bevatten: letters, cijfers en streepjes."
    }
    $serial = [string](Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop).SerialNumber
    Write-EngineEvent -State $State -Message "Hardwaregegevens verzameld voor serienummer $serial." -Level info -Step register
    $State.RegistrationCompleted = $false
    Invoke-CommunityOnline -State $State -TenantId $State.TargetTenantId -Profile $profile[0] -SelectedAddToGroup $selectedGroup -Hostname $Hostname -Verbose $Verbose
    $dynamicGroups = @($profile[0].groups | Where-Object { $_.isDynamic -and -not $_.isExclusion })
    foreach ($group in $dynamicGroups) {
        Write-EngineEvent -State $State -Message "Dynamische groep '$($group.name)' wordt door Entra verwerkt; dit kan enige tijd duren." -Level info
    }
    $State.RegistrationCompleted = $true
    [pscustomobject]@{
        serialNumber = $serial
        staticGroupName = if ($selectedGroup) { [string]$selectedGroup.name } else { $null }
        dynamicGroups = @($dynamicGroups)
        importCompleted = $true
        assigned = $true
    }
}

function Invoke-AppRestart {
    param([Parameter(Mandatory = $true)][object]$State)
    if (-not $State.RegistrationCompleted) { throw "Herstart is pas beschikbaar nadat import, profieltoewijzing en een eventuele statische groepsactie zijn afgerond." }
    if (-not (Test-IsAdministrator)) { throw "De computer kan alleen als administrator worden herstart." }
    Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-Command", "Start-Sleep -Seconds 2; Restart-Computer -Force") -WindowStyle Hidden -ErrorAction Stop
    Write-EngineEvent -State $State -Message "Herstart is ingepland." -Level success
    [pscustomobject]@{ restarting = $true }
}

Export-ModuleMember -Function @(
    "New-AutopilotGdapState",
    "Get-AutopilotGdapError",
    "Invoke-AutopilotPreflight",
    "Invoke-PartnerLogin",
    "Invoke-LoadCustomers",
    "Invoke-ConnectCustomer",
    "Invoke-ResetSession",
    "Invoke-LoadProfiles",
    "Invoke-RegisterDevice",
    "Invoke-AppRestart"
)
