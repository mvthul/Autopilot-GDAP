$script:PublicClientId = "6a87f18c-ab0a-4ef9-bb1c-587ae884b8e0"
$script:PartnerTenantId = "26aaae92-5737-48a2-b00c-27aff5b013e7"
$script:GraphScopes = @(
    "DeviceManagementServiceConfig.ReadWrite.All",
    "DeviceManagementServiceConfig.Read.All",
    "Group.Read.All",
    "GroupMember.ReadWrite.All",
    "Directory.Read.All"
)

function New-AutopilotGdapState {
    param([Parameter(Mandatory = $true)][scriptblock]$Emitter)

    $localDataPath = if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $env:LOCALAPPDATA
    } elseif (-not [string]::IsNullOrWhiteSpace($env:TEMP)) {
        $env:TEMP
    } else {
        [IO.Path]::GetTempPath()
    }
    $tokenFolder = Join-Path $localDataPath "CaptureTech\AutopilotGDAP"
    [pscustomobject]@{
        Emitter = $Emitter
        PublicClientId = $script:PublicClientId
        PartnerTenantId = $script:PartnerTenantId
        PartnerCenterTokenPath = Join-Path $tokenFolder "partnercenter.v1.token"
        PartnerCenterAccessToken = $null
        BrowserCancellationPath = Join-Path $tokenFolder "browser-auth.cancel"
        Customers = @()
        Profiles = @()
        TargetTenantId = ""
        ConnectedAccount = ""
        RegistrationCompleted = $false
    }
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

    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        Write-EngineEvent -State $State -Message "Microsoft Graph-module wordt geïnstalleerd voor de huidige Windows-gebruiker." -Level info
        Install-Module -Name Microsoft.Graph.Authentication -Scope CurrentUser -Force -AllowClobber -Repository PSGallery -ErrorAction Stop | Out-Null
    }
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop -Verbose:$false | Out-Null
}

function Save-PartnerCenterToken {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][object]$Token
    )
    if ([string]::IsNullOrWhiteSpace([string]$Token.refresh_token)) { return }
    $folder = Split-Path -Parent $State.PartnerCenterTokenPath
    New-Item -Path $folder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    $protected = ConvertTo-SecureString ($Token | ConvertTo-Json -Compress) -AsPlainText -Force | ConvertFrom-SecureString
    Set-Content -LiteralPath $State.PartnerCenterTokenPath -Value $protected -Force -ErrorAction Stop
}

function Get-CachedPartnerCenterToken {
    param([Parameter(Mandatory = $true)][object]$State)
    if (-not (Test-Path -LiteralPath $State.PartnerCenterTokenPath)) { return $null }
    try {
        $protected = Get-Content -LiteralPath $State.PartnerCenterTokenPath -Raw -ErrorAction Stop
        $plain = [System.Net.NetworkCredential]::new('', (ConvertTo-SecureString $protected)).Password
        $cached = $plain | ConvertFrom-Json
        if ([string]::IsNullOrWhiteSpace([string]$cached.refresh_token)) { return $null }
        return $cached
    }
    catch { return $null }
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
    $authorizeUri = "$authority/authorize?client_id=$([uri]::EscapeDataString($State.PublicClientId))&response_type=code&redirect_uri=$([uri]::EscapeDataString($redirectUri))&response_mode=query&scope=$([uri]::EscapeDataString($scope))&prompt=select_account"
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
    $token = Invoke-BrowserAuthorizationCodeFlow -State $State -AuthorizeUri $authorizeUri -RedirectUri $redirectUri -ExchangeCode $exchange -Purpose "Microsoft Graph-aanmelding"
    return [string]$token.access_token
}

function Connect-BrowserGraph {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][string]$TenantId,
        [Parameter(Mandatory = $true)][string[]]$Scopes
    )
    Ensure-GraphAuthenticationModule -State $State
    $accessToken = Get-BrowserGraphAccessToken -State $State -TenantId $TenantId -Scopes $Scopes
    $secureToken = ConvertTo-SecureString $accessToken -AsPlainText -Force
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    Connect-MgGraph -AccessToken $secureToken -ErrorAction Stop -NoWelcome | Out-Null
    $context = Get-MgContext
    if (-not $context -or [string]$context.TenantId -ne [string]$TenantId) {
        throw "Graph heeft de verkeerde tenantcontext geopend. Verwacht: $TenantId."
    }
    $State.ConnectedAccount = [string]$context.Account
    Write-EngineEvent -State $State -Message "Graph-verbinding met tenant $TenantId is actief." -Level success
}

function Get-PartnerCenterAccessToken {
    param([Parameter(Mandatory = $true)][object]$State)
    $resource = "https://api.partnercenter.microsoft.com"
    $tokenUri = "https://login.microsoftonline.com/common/oauth2/token"
    $cached = Get-CachedPartnerCenterToken -State $State
    if ($cached) {
        try {
            $renewed = Invoke-RestMethod -Method POST -Uri $tokenUri -Body @{
                grant_type = "refresh_token"
                client_id = $State.PublicClientId
                refresh_token = $cached.refresh_token
                resource = $resource
            } -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
            Save-PartnerCenterToken -State $State -Token $renewed
            return [string]$renewed.access_token
        }
        catch {
            Remove-Item -LiteralPath $State.PartnerCenterTokenPath -Force -ErrorAction SilentlyContinue
        }
    }

    $redirectUri = "http://localhost:8765/"
    $authorizeUri = "https://login.microsoftonline.com/common/oauth2/authorize?client_id=$([uri]::EscapeDataString($State.PublicClientId))&response_type=code&redirect_uri=$([uri]::EscapeDataString($redirectUri))&response_mode=query&resource=$([uri]::EscapeDataString($resource))&prompt=select_account"
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
    $token = Invoke-BrowserAuthorizationCodeFlow -State $State -AuthorizeUri $authorizeUri -RedirectUri $redirectUri -ExchangeCode $exchange -Purpose "Partner Center-aanmelding"
    Save-PartnerCenterToken -State $State -Token $token
    return [string]$token.access_token
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
    $scriptText = $patchedText.Replace('setx MSAL_FORCE_WAM 0', '# WAM disabled: existing browser Graph session is reused')
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
    }
}

function Invoke-PartnerLogin {
    param([Parameter(Mandatory = $true)][object]$State)
    Connect-BrowserGraph -State $State -TenantId $State.PartnerTenantId -Scopes @("Directory.Read.All")
    Write-EngineEvent -State $State -Message "IT-Hulp-account is aangemeld. Partner Center-klanten kunnen worden geladen." -Level success -Step customer
    return [pscustomobject]@{ tenantId = $State.PartnerTenantId; account = $State.ConnectedAccount }
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
    Connect-BrowserGraph -State $State -TenantId $TenantId -Scopes $script:GraphScopes
    $State.TargetTenantId = $TenantId
    $State.RegistrationCompleted = $false
    Write-EngineEvent -State $State -Message "Verbonden met $($customer[0].customerName)." -Level success
    [pscustomobject]@{ tenantId = $TenantId; account = $State.ConnectedAccount }
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
    "Invoke-AutopilotPreflight",
    "Invoke-PartnerLogin",
    "Invoke-LoadCustomers",
    "Invoke-ConnectCustomer",
    "Invoke-LoadProfiles",
    "Invoke-RegisterDevice",
    "Invoke-AppRestart"
)
