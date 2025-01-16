#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

# Import required modules
using module '../helpers/TestHelpers.ps1'

function New-TestDevice {
    [CmdletBinding()]
    param (
        [Parameter()]
        [hashtable]$Properties = @{},

        [Parameter()]
        [switch]$SimulateError
    )

    try {
        # Acquire thread-safe lock
        $lock = Get-TestDataLock

        # Create base device properties
        $deviceProps = @{
            name = $Properties.name ?? "TestDevice-$(New-Guid)"
            status = $Properties.status ?? "Active"
            model = $Properties.model ?? "TestModel-$(Get-Random)"
        }

        # Add optional properties if provided
        $optionalProps = @('osName', 'osVersion', 'ips', 'macs')
        foreach ($prop in $optionalProps) {
            if ($Properties.ContainsKey($prop)) {
                $deviceProps[$prop] = $Properties[$prop]
            }
        }

        # Validate IP addresses if provided
        if ($deviceProps.ContainsKey('ips')) {
            foreach ($ip in $deviceProps.ips) {
                if ($ip -notmatch '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$') {
                    throw [System.ArgumentException]::new("Invalid IP address format: $ip")
                }
            }
        }

        # Validate MAC addresses if provided
        if ($deviceProps.ContainsKey('macs')) {
            foreach ($mac in $deviceProps.macs) {
                if ($mac -notmatch '^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$') {
                    throw [System.ArgumentException]::new("Invalid MAC address format: $mac")
                }
            }
        }

        # Simulate error if requested
        if ($SimulateError) {
            throw [System.InvalidOperationException]::new("Simulated device creation error")
        }

        # Create test device asset
        $device = New-TestAsset -AssetType 'DEVICE' -Properties $deviceProps
        return $device
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'TestDeviceCreationError',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $Properties
            )
        )
    }
    finally {
        if ($lock) { $lock.Dispose() }
    }
}

function New-TestContainer {
    [CmdletBinding()]
    param (
        [Parameter()]
        [hashtable]$Properties = @{},

        [Parameter()]
        [switch]$SimulateError
    )

    try {
        # Acquire thread-safe lock
        $lock = Get-TestDataLock

        # Create base container properties
        $containerProps = @{
            name = $Properties.name ?? "TestContainer-$(New-Guid)"
            status = $Properties.status ?? "Active"
            image = $Properties.image ?? "test/image:latest"
        }

        # Add optional properties if provided
        $optionalProps = @('ports', 'command', 'imageTag')
        foreach ($prop in $optionalProps) {
            if ($Properties.ContainsKey($prop)) {
                $containerProps[$prop] = $Properties[$prop]
            }
        }

        # Validate ports if provided
        if ($containerProps.ContainsKey('ports')) {
            foreach ($port in $containerProps.ports) {
                if ($port -notmatch '^\d+(?:\/(?:tcp|udp))?$') {
                    throw [System.ArgumentException]::new("Invalid port format: $port")
                }
            }
        }

        # Validate image tag if provided
        if ($containerProps.ContainsKey('imageTag')) {
            if ($containerProps.imageTag -notmatch '^[\w][\w.-]{0,127}$') {
                throw [System.ArgumentException]::new("Invalid image tag format: $($containerProps.imageTag)")
            }
        }

        # Simulate error if requested
        if ($SimulateError) {
            throw [System.InvalidOperationException]::new("Simulated container creation error")
        }

        # Create test container asset
        $container = New-TestAsset -AssetType 'CONTAINER' -Properties $containerProps
        return $container
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'TestContainerCreationError',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $Properties
            )
        )
    }
    finally {
        if ($lock) { $lock.Dispose() }
    }
}

function Get-TestAssetData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('DEVICE', 'CONTAINER', 'SOFTWARE', 'USER', 'PROCESS')]
        [string]$AssetType,

        [Parameter()]
        [switch]$SkipCache
    )

    try {
        # Acquire thread-safe lock
        $lock = Get-TestDataLock

        # Check cache unless explicitly skipped
        if (-not $SkipCache) {
            $cachedData = $script:TestAssetCache[$AssetType]
            if ($cachedData) {
                Write-Verbose "Returning cached test data for asset type: $AssetType"
                return $cachedData
            }
        }

        # Load test asset data from JSON
        $testDataPath = Join-Path $PSScriptRoot "TestAssets.json"
        if (-not (Test-Path $testDataPath)) {
            throw [System.IO.FileNotFoundException]::new("Test asset data file not found", $testDataPath)
        }

        $testData = Get-Content $testDataPath -Raw | ConvertFrom-Json

        # Filter and validate assets by type
        $assets = $testData.assets | Where-Object { $_.type -eq $AssetType }
        foreach ($asset in $assets) {
            Assert-AssetProperties -Asset $asset -AssetType $AssetType
        }

        # Update cache if not skipped
        if (-not $SkipCache) {
            $script:TestAssetCache[$AssetType] = $assets
        }

        return $assets
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'TestAssetDataRetrievalError',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $AssetType
            )
        )
    }
    finally {
        if ($lock) { $lock.Dispose() }
    }
}

# Initialize test asset cache
$script:TestAssetCache = @{}

# Export functions
Export-ModuleMember -Function @(
    'New-TestDevice',
    'New-TestContainer',
    'Get-TestAssetData'
)