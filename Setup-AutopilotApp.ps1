<#
.SYNOPSIS
  Eenmalige inrichting van de eigen multi-tenant Autopilot-app in de partner-tenant.

.DESCRIPTION
  Vereist Azure CLI en een interactieve Global Administrator-login.
  Er wordt geen client secret aangemaakt of opgeslagen.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PartnerTenantId,

    [string]$DisplayName = "CaptureTech Autopilot GDAP"
)

$ErrorActionPreference = "Stop"
$graphAppId = "00000003-0000-0000-c000-000000000000"
$scopeNames = @(
    "DeviceManagementServiceConfig.ReadWrite.All",
    "DeviceManagementServiceConfig.Read.All",
    "Group.Read.All",
    "GroupMember.ReadWrite.All",
    "Directory.Read.All"
)
$partnerCenterScope = "https://api.partnercenter.microsoft.com/user_impersonation"

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI is niet geïnstalleerd. Installeer Azure CLI en voer dit script opnieuw uit."
}

Write-Host "Aanmelden op partner-tenant $PartnerTenantId..." -ForegroundColor Cyan
az login --tenant $PartnerTenantId --use-device-code | Out-Null
$loggedInTenant = az account show --query tenantId -o tsv
if ($loggedInTenant -ne $PartnerTenantId) {
    throw "Azure CLI is aangemeld op tenant '$loggedInTenant' in plaats van '$PartnerTenantId'."
}

Write-Host "Microsoft Graph-permissies ophalen..." -ForegroundColor Cyan
$graphSpJson = az ad sp show --id $graphAppId -o json 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($graphSpJson -join ""))) {
    throw "De Microsoft Graph service principal kon niet worden opgehaald. Controleer of Azure CLI met een Global Administrator is aangemeld."
}
$graphSp = $graphSpJson | ConvertFrom-Json
$scopeMap = @{}
foreach ($scope in $graphSp.oauth2PermissionScopes) {
    $scopeMap[$scope.value] = $scope.id
}

$resourceAccess = @()
foreach ($scopeName in $scopeNames) {
    if (-not $scopeMap.ContainsKey($scopeName)) {
        throw "Graph-scope '$scopeName' is niet gevonden in de Microsoft Graph service principal."
    }
    $resourceAccess += @{ id = $scopeMap[$scopeName]; type = "Scope" }
}

$existingJson = az ad app list --all --query "[?displayName=='$DisplayName']" -o json
if ($LASTEXITCODE -ne 0) {
    throw "Bestaande appregistraties konden niet worden opgehaald."
}
$existing = $existingJson | ConvertFrom-Json
if ($existing) {
    $app = @($existing)[0]
    if ([string]::IsNullOrWhiteSpace([string]$app.appId) -or [string]::IsNullOrWhiteSpace([string]$app.id)) {
        throw "De gevonden app '$DisplayName' heeft geen geldige object-id/client-id. Controleer de appregistratie handmatig."
    }
    $clientId = [string]$app.appId
    $appObjectId = [string]$app.id
    Write-Host "Bestaande app gevonden: $clientId" -ForegroundColor Yellow
    az ad app update --id $appObjectId --sign-in-audience AzureADMultipleOrgs | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Bestaande app kon niet als multi-tenant worden ingesteld." }
} else {
    Write-Host "Multi-tenant app aanmaken..." -ForegroundColor Cyan
    $appJson = az ad app create --display-name $DisplayName --sign-in-audience AzureADMultipleOrgs -o json
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($appJson -join ""))) {
        throw "Appregistratie kon niet worden aangemaakt."
    }
    $app = $appJson | ConvertFrom-Json
    $clientId = [string]$app.appId
    $appObjectId = [string]$app.id
    if ([string]::IsNullOrWhiteSpace($clientId) -or [string]::IsNullOrWhiteSpace($appObjectId)) {
        throw "Azure CLI gaf geen geldige client-id/object-id terug."
    }
}

Write-Host "Graph-permissies instellen..." -ForegroundColor Cyan
$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
az ad app permission delete --id $appObjectId --api $graphAppId 2>$null | Out-Null
$ErrorActionPreference = $previousErrorActionPreference
foreach ($scopeName in $scopeNames) {
    $permission = "$($scopeMap[$scopeName])=Scope"
    az ad app permission add --id $appObjectId --api $graphAppId --api-permissions $permission | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Graph-permissie '$scopeName' kon niet worden toegevoegd." }
}

az ad app update --id $appObjectId --is-fallback-public-client true | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Public-client/device-code flow kon niet worden ingeschakeld." }
az ad app update --id $appObjectId --public-client-redirect-uris http://localhost | Out-Null
if ($LASTEXITCODE -ne 0) { throw "De localhost redirect URI kon niet worden ingesteld." }

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$spJson = az ad sp show --id $clientId -o json 2>$null
$spExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorActionPreference
if ($spExitCode -ne 0 -or [string]::IsNullOrWhiteSpace(($spJson -join ""))) {
    Write-Host "Enterprise application/service principal aanmaken..." -ForegroundColor Cyan
    az ad sp create --id $clientId | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Enterprise application/service principal kon niet worden aangemaakt." }
}

$consentUrl = "https://login.microsoftonline.com/$PartnerTenantId/adminconsent?client_id=$clientId&redirect_uri=http%3A%2F%2Flocalhost"
$partnerCenterConsentUrl = "https://login.microsoftonline.com/$PartnerTenantId/v2.0/adminconsent?client_id=$clientId&scope=$([uri]::EscapeDataString($partnerCenterScope))&redirect_uri=http%3A%2F%2Flocalhost"
$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
az ad app permission admin-consent --id $appObjectId | Out-Null
$consentExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorActionPreference
Write-Host "" 
Write-Host "Klaar. Client ID:" -ForegroundColor Green
Write-Host $clientId
Write-Host "" 
Write-Host "Open deze URL als Global Administrator om partner-consent te bevestigen:" -ForegroundColor Green
Write-Host $consentUrl
Set-Clipboard -Value $consentUrl -ErrorAction SilentlyContinue
if ($consentExitCode -ne 0) {
    Write-Host "Automatische consent is niet gelukt; open de getoonde URL als Global Administrator." -ForegroundColor Yellow
    Start-Process $consentUrl -ErrorAction SilentlyContinue
} else {
    Write-Host "Admin consent is via Azure CLI verleend." -ForegroundColor Green
}
Write-Host ""
Write-Host "Open daarna deze URL voor Partner Center-klantlijst-consent:" -ForegroundColor Green
Write-Host $partnerCenterConsentUrl
Write-Host "De runtime-tool vraagt deze Partner Center-aanmelding anders automatisch via device code." -ForegroundColor Yellow
Write-Host "De client-id moet daarna in Get-AutopilotGDAP.ps1 worden ingevuld op PublicClientId." -ForegroundColor Yellow
