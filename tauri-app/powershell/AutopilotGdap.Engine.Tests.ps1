[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$enginePath = Join-Path $PSScriptRoot "AutopilotGdap.Engine.psm1"
$module = Import-Module -Name $enginePath -Force -PassThru -ErrorAction Stop
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)][object]$Actual,
        [Parameter(Mandatory = $true)][object]$Expected,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if ($Actual -ne $Expected) {
        [void]$failures.Add("$Name. Verwacht: '$Expected'. Ontvangen: '$Actual'.")
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if (-not $Condition) { [void]$failures.Add($Name) }
}

function New-TestErrorRecord {
    param([Parameter(Mandatory = $true)][string]$Message)
    $exception = [System.InvalidOperationException]::new($Message)
    return [System.Management.Automation.ErrorRecord]::new($exception, "AutopilotGdapTest", [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
}

$oobeMode = & $module { Resolve-AuthenticationMode -IsOobe $true }
$desktopMode = & $module { Resolve-AuthenticationMode -IsOobe $false }
Assert-Equal -Actual $oobeMode -Expected "browserOobe" -Name "OOBE gebruikt browser-SSO"
Assert-Equal -Actual $desktopMode -Expected "wam" -Name "Desktop gebruikt WAM"

$scopes = @(& $module { ConvertTo-MsalScopes -Scopes @("Directory.Read.All", "https://api.partnercenter.microsoft.com/user_impersonation") })
Assert-True -Condition ($scopes -contains "https://graph.microsoft.com/Directory.Read.All") -Name "Graph-scope krijgt de vaste Graph-resource"
Assert-True -Condition ($scopes -contains "https://api.partnercenter.microsoft.com/user_impersonation") -Name "Partner Center-scope blijft ongewijzigd"

$customerError = & $module {
    param($record)
    Get-AutopilotGdapError -ErrorRecord $record
} (New-TestErrorRecord -Message "AADSTS90099: application has not been authorized in the tenant")
Assert-Equal -Actual $customerError.code -Expected "customerConsentRequired" -Name "Klantconsentfout is getypeerd"

$partnerError = & $module {
    param($record)
    Get-AutopilotGdapError -ErrorRecord $record
} (New-TestErrorRecord -Message "Partner Center https://api.partnercenter.microsoft.com returned AADSTS65001 consent required")
Assert-Equal -Actual $partnerError.code -Expected "partnerCenterConsentRequired" -Name "Partner Center-consentfout is getypeerd"

$pimError = & $module {
    param($record)
    Get-AutopilotGdapError -ErrorRecord $record
} (New-TestErrorRecord -Message "HTTP/1.1 403 Forbidden")
Assert-Equal -Actual $pimError.code -Expected "gdapPimDenied" -Name "GDAP/PIM-fout is getypeerd"

$legacyTokenPath = Join-Path ([IO.Path]::GetTempPath()) ("autopilot-gdap-legacy-{0}.token" -f ([guid]::NewGuid()))
[IO.File]::WriteAllText($legacyTokenPath, "legacy-token")
$legacyState = [pscustomobject]@{
    LegacyPartnerCenterTokenRetired = $false
    PartnerCenterTokenPath = $legacyTokenPath
    Emitter = { param($event, $payload) }
}
& $module {
    param($state)
    Retire-LegacyPartnerCenterToken -State $state
} $legacyState
Assert-True -Condition (-not (Test-Path -LiteralPath $legacyTokenPath)) -Name "Legacy Partner Center-token wordt verwijderd"
Assert-True -Condition ([bool]$legacyState.LegacyPartnerCenterTokenRetired) -Name "Legacy-tokenmigratie wordt gemarkeerd"

$resetState = [pscustomobject]@{
    PartnerCenterAccessToken = "token"
    BrowserInteractiveCompleted = $true
    SessionAccount = "it-hulp@capturetech.example"
    SessionHomeAccountId = "account-id"
    ConnectedAccount = "it-hulp@capturetech.example"
    Customers = @([pscustomobject]@{ tenantId = "tenant" })
    Profiles = @([pscustomobject]@{ profileId = "profile" })
    TargetTenantId = "tenant"
    RegistrationCompleted = $true
    AuthMode = "wam"
    Emitter = { param($event, $payload) }
}
$resetResult = & $module {
    param($state)
    function Disconnect-MgGraph { [CmdletBinding()] param() }
    Invoke-ResetSession -State $state
} $resetState
Assert-True -Condition ([bool]$resetResult.sessionReset) -Name "Sessie-reset geeft een expliciet resultaat"
Assert-Equal -Actual $resetState.SessionAccount -Expected "" -Name "Sessie-reset wist het account"
Assert-Equal -Actual $resetState.TargetTenantId -Expected "" -Name "Sessie-reset wist de klanttenant"
Assert-True -Condition (-not [bool]$resetState.RegistrationCompleted) -Name "Sessie-reset blokkeert herstart opnieuw"

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "Autopilot GDAP engine-contracttests geslaagd." -ForegroundColor Green
