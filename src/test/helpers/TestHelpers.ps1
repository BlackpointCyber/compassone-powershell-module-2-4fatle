#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

# Import required modules and configurations
using module './AssertionHelpers.ps1'
$TestConfig = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot '../config/test-config.psd1')

function Initialize-TestEnvironment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TestName,

        [Parameter()]
        [switch]$UseMockData,

        [Parameter()]
        [switch]$EnableParallel,

        [Parameter()]
        [ValidateSet('Verbose', 'Debug', 'Information', 'Warning', 'Error')]
        [string]$LogLevel = 'Information'
    )

    try {
        # Create test environment configuration
        $testEnvironment = @{
            TestName = $TestName
            TestId = [System.Guid]::NewGuid().ToString()
            StartTime = Get-Date
            UseMockData = $UseMockData.IsPresent
            ParallelExecution = $EnableParallel.IsPresent
            LogLevel = $LogLevel
            TestDataPath = Join-Path $TestConfig.TestConfiguration.TestDataPath $TestName
            ApiEndpoint = $TestConfig.TestConfiguration.ApiEndpoint
            Resources = @{
                Created = @()
                Modified = @()
                Deleted = @()
            }
        }

        # Create test data directory if it doesn't exist
        if (-not (Test-Path $testEnvironment.TestDataPath)) {
            New-Item -Path $testEnvironment.TestDataPath -ItemType Directory -Force | Out-Null
        }

        # Initialize logging
        $logPath = Join-Path $testEnvironment.TestDataPath "test_$($testEnvironment.TestId).log"
        $testEnvironment.LogPath = $logPath

        # Configure logging based on specified level
        switch ($LogLevel) {
            'Verbose' { $VerbosePreference = 'Continue' }
            'Debug' { $DebugPreference = 'Continue' }
            default { $InformationPreference = 'Continue' }
        }

        # Initialize mock data if specified
        if ($UseMockData) {
            Initialize-ApiMocks -Configuration $testEnvironment
        }

        # Set up parallel execution context if enabled
        if ($EnableParallel) {
            $testEnvironment.ParallelContext = @{
                MaxJobs = $env:NUMBER_OF_PROCESSORS
                RunspacePool = [runspacefactory]::CreateRunspacePool(1, $env:NUMBER_OF_PROCESSORS)
                Jobs = @()
            }
            $testEnvironment.ParallelContext.RunspacePool.Open()
        }

        Write-Verbose "Test environment initialized: $($testEnvironment.TestId)"
        return $testEnvironment
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'TestEnvironmentInitializationError',
                [System.Management.Automation.ErrorCategory]::OperationStopped,
                $testEnvironment
            )
        )
    }
}

function Initialize-ApiMocks {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$Configuration,

        [Parameter()]
        [switch]$SimulateErrors
    )

    try {
        # Set up base API mock
        Mock Invoke-RestMethod {
            param($Uri, $Method, $Headers, $Body)

            # Simulate network latency
            Start-Sleep -Milliseconds (Get-Random -Minimum 100 -Maximum 500)

            # Simulate rate limiting
            if ((Get-Random -Minimum 1 -Maximum 100) -le 5) {
                throw [System.Net.WebException]::new(
                    'Too Many Requests',
                    $null,
                    [System.Net.WebExceptionStatus]::ProtocolError,
                    [PSCustomObject]@{
                        StatusCode = 429
                        StatusDescription = 'Too Many Requests'
                    }
                )
            }

            # Load appropriate mock response based on URI and method
            $mockPath = Join-Path $Configuration.TestDataPath "mock_responses"
            $mockFile = Join-Path $mockPath "$Method_$([System.Web.HttpUtility]::UrlEncode($Uri)).json"

            if (Test-Path $mockFile) {
                $response = Get-Content $mockFile -Raw | ConvertFrom-Json
                return $response
            }
            else {
                throw [System.IO.FileNotFoundException]::new("Mock response file not found: $mockFile")
            }
        } -ParameterFilter { $Uri -match $Configuration.ApiEndpoint }

        # Set up authentication mock
        Mock Get-PSCompassOneToken {
            return [PSCustomObject]@{
                Token = "mock_token_$(New-Guid)"
                ExpiresAt = (Get-Date).AddHours(1)
            }
        }

        if ($SimulateErrors) {
            # Set up error simulation mocks
            Mock Invoke-RestMethod {
                throw [System.Net.WebException]::new(
                    'Internal Server Error',
                    $null,
                    [System.Net.WebExceptionStatus]::ProtocolError,
                    [PSCustomObject]@{
                        StatusCode = 500
                        StatusDescription = 'Internal Server Error'
                    }
                )
            } -ParameterFilter { $Uri -match 'error' }
        }

        Write-Verbose "API mocks initialized for endpoint: $($Configuration.ApiEndpoint)"
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'ApiMockInitializationError',
                [System.Management.Automation.ErrorCategory]::OperationStopped,
                $Configuration
            )
        )
    }
}

function New-TestAsset {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('DEVICE', 'CONTAINER', 'SOFTWARE', 'USER', 'PROCESS')]
        [string]$AssetType,

        [Parameter(Mandatory = $true)]
        [hashtable]$Properties,

        [Parameter()]
        [switch]$ValidateRelationships
    )

    try {
        # Create base asset object
        $asset = [PSCustomObject]@{
            Id = [System.Guid]::NewGuid().ToString()
            Type = $AssetType
            CreatedAt = Get-Date
            UpdatedAt = Get-Date
            Status = 'Active'
        }

        # Add required properties based on asset type
        switch ($AssetType) {
            'DEVICE' {
                $requiredProps = @('name', 'model')
                $optionalProps = @('osName', 'osVersion', 'ips', 'macs')
            }
            'CONTAINER' {
                $requiredProps = @('name', 'image')
                $optionalProps = @('ports', 'command', 'imageTag')
            }
            'SOFTWARE' {
                $requiredProps = @('name', 'version')
                $optionalProps = @('license', 'urls', 'hipaa')
            }
            'USER' {
                $requiredProps = @('name', 'email', 'username')
                $optionalProps = @('mfaEnabled', 'admin', 'group')
            }
            'PROCESS' {
                $requiredProps = @('name', 'pid')
                $optionalProps = @('ppid', 'hash', 'userName')
            }
        }

        # Validate required properties
        foreach ($prop in $requiredProps) {
            if (-not $Properties.ContainsKey($prop)) {
                throw [System.ArgumentException]::new("Missing required property: $prop for asset type: $AssetType")
            }
            $asset | Add-Member -NotePropertyName $prop -NotePropertyValue $Properties[$prop]
        }

        # Add optional properties if provided
        foreach ($prop in $optionalProps) {
            if ($Properties.ContainsKey($prop)) {
                $asset | Add-Member -NotePropertyName $prop -NotePropertyValue $Properties[$prop]
            }
        }

        # Validate relationships if specified
        if ($ValidateRelationships -and $Properties.ContainsKey('relationships')) {
            foreach ($relationship in $Properties.relationships) {
                if (-not ($relationship.sourceId -and $relationship.targetId -and $relationship.type)) {
                    throw [System.ArgumentException]::new("Invalid relationship structure")
                }
            }
            $asset | Add-Member -NotePropertyName 'relationships' -NotePropertyValue $Properties.relationships
        }

        # Validate final asset structure
        Assert-AssetProperties -Asset $asset -AssetType $AssetType

        return $asset
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'TestAssetCreationError',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $Properties
            )
        )
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Initialize-TestEnvironment',
    'New-TestAsset'
)