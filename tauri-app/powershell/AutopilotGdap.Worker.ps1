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
        [AllowNull()][object]$Error
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

function Get-CustomerCacheCompletionData {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter(Mandatory = $true)][object]$State
    )

    # Never serialize the PowerShell return stream from the Partner Center
    # action. The engine can emit diagnostic objects on that stream on Windows
    # PowerShell, despite the customer cache itself having been written.
    if ($Action -eq "loginPartner") {
        return [ordered]@{
            tenantId = [string]$State.PartnerTenantId
            account = [string]$State.ConnectedAccount
            authMode = [string]$State.AuthMode
            isOobe = [bool]$State.IsOobe
            customerCount = [int](@($State.Customers).Count)
        }
    }
    return [ordered]@{ customerCount = [int](@($State.Customers).Count) }
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
                [void](Invoke-PartnerLogin -State $state)
                $data = Get-CustomerCacheCompletionData -Action $action -State $state
            }
            "loadCustomers" {
                [void](Invoke-LoadCustomers -State $state)
                $data = Get-CustomerCacheCompletionData -Action $action -State $state
            }
            "connectCustomer" {
                $tenantId = [string](Get-RequestValue -Payload $payload -Name "tenantId")
                if ($tenantId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$') {
                    throw "De klanttenant-ID is ongeldig."
                }
                [void](Invoke-ConnectCustomer -State $state -TenantId $tenantId)
                $data = [ordered]@{
                    tenantId = [string]$state.TargetTenantId
                    account = [string]$state.ConnectedAccount
                    authMode = [string]$state.AuthMode
                    customerAuthMode = [string]$state.CustomerAuthMode
                }
            }
            "loadProfiles" {
                $data = Invoke-LoadProfiles -State $state
            }
            "resetSession" {
                $data = Invoke-ResetSession -State $state
            }
            "registerDevice" {
                $profileId = [string](Get-RequestValue -Payload $payload -Name "profileId")
                if ([string]::IsNullOrWhiteSpace($profileId)) { throw "Een Autopilot-profiel is verplicht." }
                $data = Invoke-RegisterDevice -State $state `
                    -ProfileId $profileId `
                    -StaticGroupId ([string](Get-RequestValue -Payload $payload -Name "staticGroupId")) `
                    -Hostname ([string](Get-RequestValue -Payload $payload -Name "hostname")) `
                    -IncludeTechnicalOutput ([bool](Get-RequestValue -Payload $payload -Name "verbose"))
            }
            "restartDevice" {
                $data = Invoke-AppRestart -State $state
            }
            default {
                throw "Onbekende backendactie: $action"
            }
        }
        if ($action -in @("loginPartner", "loadCustomers")) {
            # The customer records are kept in the private runtime cache. Rust
            # streams the cache to the UI, then converts this small completion
            # event into the normal frontend result.
            Write-WorkerEvent -RequestId $requestId -Event "customerCacheReady" -Payload $data
        }
        # Successful actions always end as an event with a deliberately
        # bounded payload. Rust converts it to the frontend result protocol.
        # This avoids serialising any incidental PowerShell pipeline objects.
        Write-WorkerEvent -RequestId $requestId -Event "actionComplete" -Payload $data
    }
    catch {
        if ([string]::IsNullOrWhiteSpace($requestId)) { $requestId = [guid]::NewGuid().ToString() }
        $errorInfo = Get-AutopilotGdapError -ErrorRecord $_
        Write-WorkerResult -RequestId $requestId -Ok $false -Data $null -Error $errorInfo
    }
    finally {
        $workerContext.RequestId = ""
    }
}
