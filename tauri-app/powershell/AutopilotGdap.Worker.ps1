[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$EnginePath
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$InformationPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-WorkerMessage {
    param([Parameter(Mandatory = $true)][object]$Message)
    $json = $Message | ConvertTo-Json -Depth 16 -Compress
    [Console]::Out.WriteLine($json)
    [Console]::Out.Flush()
}

function Write-WorkerEvent {
    param(
        [Parameter(Mandatory = $true)][string]$RequestId,
        [Parameter(Mandatory = $true)][string]$Event,
        [Parameter(Mandatory = $true)][object]$Payload
    )
    Write-WorkerMessage ([ordered]@{
        kind = "event"
        requestId = $RequestId
        event = $Event
        payload = $Payload
    })
}

function Write-WorkerResult {
    param(
        [Parameter(Mandatory = $true)][string]$RequestId,
        [bool]$Ok,
        [AllowNull()][object]$Data,
        [string]$Error
    )
    $message = [ordered]@{
        kind = "result"
        requestId = $RequestId
        ok = $Ok
    }
    if ($Ok) { $message.data = $Data }
    else { $message.error = $Error }
    Write-WorkerMessage $message
}

function Get-RequestValue {
    param(
        [Parameter(Mandatory = $true)][object]$Payload,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $property = $Payload.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

if (-not (Test-Path -LiteralPath $EnginePath)) {
    throw "De ingebedde Autopilot-engine ontbreekt: $EnginePath"
}

$resolvedEnginePath = (Resolve-Path -LiteralPath $EnginePath -ErrorAction Stop).Path
Import-Module -Name $resolvedEnginePath -Force -ErrorAction Stop -Verbose:$false | Out-Null
$workerContext = @{ RequestId = "" }
$emitter = {
    param([string]$Event, [object]$Payload)
    Write-WorkerEvent -RequestId $workerContext.RequestId -Event $Event -Payload $Payload
}.GetNewClosure()
$state = New-AutopilotGdapState -Emitter $emitter

while ($true) {
    $line = [Console]::In.ReadLine()
    if ($null -eq $line) { break }
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    $requestId = ""
    try {
        $request = $line | ConvertFrom-Json -ErrorAction Stop
        $requestId = [string]$request.requestId
        if ([string]::IsNullOrWhiteSpace($requestId)) { throw "Een requestId is verplicht." }
        $workerContext.RequestId = $requestId
        $action = [string]$request.action
        $payload = $request.payload
        if ($null -eq $payload) { $payload = [pscustomobject]@{} }

        switch ($action) {
            "preflight" {
                $data = Invoke-AutopilotPreflight -State $state
            }
            "loginPartner" {
                $data = Invoke-PartnerLogin -State $state
            }
            "loadCustomers" {
                $data = Invoke-LoadCustomers -State $state
            }
            "connectCustomer" {
                $tenantId = [string](Get-RequestValue -Payload $payload -Name "tenantId")
                if ($tenantId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$') {
                    throw "De klanttenant-ID is ongeldig."
                }
                $data = Invoke-ConnectCustomer -State $state -TenantId $tenantId
            }
            "loadProfiles" {
                $data = Invoke-LoadProfiles -State $state
            }
            "registerDevice" {
                $profileId = [string](Get-RequestValue -Payload $payload -Name "profileId")
                if ([string]::IsNullOrWhiteSpace($profileId)) { throw "Een Autopilot-profiel is verplicht." }
                $data = Invoke-RegisterDevice -State $state `
                    -ProfileId $profileId `
                    -StaticGroupId ([string](Get-RequestValue -Payload $payload -Name "staticGroupId")) `
                    -Hostname ([string](Get-RequestValue -Payload $payload -Name "hostname")) `
                    -Verbose ([bool](Get-RequestValue -Payload $payload -Name "verbose"))
            }
            "restartDevice" {
                $data = Invoke-AppRestart -State $state
            }
            default {
                throw "Onbekende backendactie: $action"
            }
        }
        Write-WorkerResult -RequestId $requestId -Ok $true -Data $data
    }
    catch {
        $detail = $_.Exception.Message
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = ($_ | Out-String).Trim() }
        if ([string]::IsNullOrWhiteSpace($requestId)) { $requestId = [guid]::NewGuid().ToString() }
        Write-WorkerResult -RequestId $requestId -Ok $false -Data $null -Error $detail
    }
    finally {
        $workerContext.RequestId = ""
    }
}
