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
    "Organization.Read.All"
)

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
$graphSp = az rest --method get --url "https://graph.microsoft.com/v1.0/servicePrincipals(appId='$graphAppId')" | ConvertFrom-Json
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

$requiredAccess = @(@{
    resourceAppId  = $graphAppId
    resourceAccess = $resourceAccess
}) | ConvertTo-Json -Depth 5 -Compress

$existing = @(az ad app list --display-name $DisplayName --all --query "[?displayName=='$DisplayName']" -o json | ConvertFrom-Json)
if ($existing.Count -gt 0) {
    $app = $existing[0]
    $clientId = $app.appId
    Write-Host "Bestaande app gevonden: $clientId" -ForegroundColor Yellow
    az ad app update --id $app.id --sign-in-audience AzureADMultipleOrgs --required-resource-accesses $requiredAccess | Out-Null
} else {
    Write-Host "Multi-tenant app aanmaken..." -ForegroundColor Cyan
    $app = az ad app create --display-name $DisplayName --sign-in-audience AzureADMultipleOrgs --required-resource-accesses $requiredAccess | ConvertFrom-Json
    $clientId = $app.appId
}

az ad app update --id $clientId --is-fallback-public-client true | Out-Null

try {
    az ad sp show --id $clientId | Out-Null
} catch {
    Write-Host "Enterprise application/service principal aanmaken..." -ForegroundColor Cyan
    az ad sp create --id $clientId | Out-Null
}

$consentUrl = "https://login.microsoftonline.com/$PartnerTenantId/adminconsent?client_id=$clientId&redirect_uri=http%3A%2F%2Flocalhost"
Write-Host "" 
Write-Host "Klaar. Client ID:" -ForegroundColor Green
Write-Host $clientId
Write-Host "" 
Write-Host "Open deze URL als Global Administrator om partner-consent te bevestigen:" -ForegroundColor Green
Write-Host $consentUrl
Set-Clipboard -Value $consentUrl -ErrorAction SilentlyContinue
Start-Process $consentUrl -ErrorAction SilentlyContinue
Write-Host "De client-id moet daarna in Get-AutopilotGDAP.ps1 worden ingevuld op PublicClientId." -ForegroundColor Yellow
