#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }, @{ ModuleName='Microsoft.PowerShell.SecretStore'; ModuleVersion='1.0.0' }

using namespace System.Collections.Concurrent
using namespace System.Security

# Import test helpers
. (Join-Path $PSScriptRoot '../helpers/MockHelpers.ps1')

# Thread-safe storage for mock SecretStore state
$script:MockSecretStore = [ConcurrentDictionary[string,object]]::new()
$script:MockSecretStoreLocked = $true

<#
.SYNOPSIS
    Creates a new thread-safe mock instance of SecretStore with configurable behavior.
.DESCRIPTION
    Creates a comprehensive mock implementation of SecretStore functionality with support
    for thread safety, error simulation, and enhanced validation for testing purposes.
.PARAMETER Configuration
    Configuration hashtable for mock behavior settings.
.EXAMPLE
    $mockStore = New-SecretStoreMock -Configuration @{ 
        SimulateErrors = $true
        MaxRetries = 3
    }
#>
function New-SecretStoreMock {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$Configuration = @{}
    )

    # Default configuration
    $defaultConfig = @{
        SimulateErrors = $false
        MaxRetries = 3
        RetryDelayMs = 500
        DefaultTTL = [TimeSpan]::FromHours(1)
        PlatformPath = Join-Path $env:TEMP 'MockSecretStore'
    }

    # Merge with provided configuration
    $config = $defaultConfig + $Configuration

    # Initialize mock store if needed
    if (-not $script:MockSecretStore.Count) {
        $script:MockSecretStore = [ConcurrentDictionary[string,object]]::new()
        $script:MockSecretStoreLocked = $true
    }

    # Create mock object with enhanced validation
    $mockObject = @{
        Configuration = $config
        Store = $script:MockSecretStore
        IsLocked = $script:MockSecretStoreLocked
        Validate = {
            param([string]$Name, [object]$Value)
            
            if ([string]::IsNullOrWhiteSpace($Name)) {
                throw [ArgumentException]::new("Secret name cannot be empty")
            }

            if ($null -eq $Value) {
                throw [ArgumentException]::new("Secret value cannot be null")
            }
        }
    }

    return $mockObject
}

<#
.SYNOPSIS
    Implements comprehensive mocking of SecretStore cmdlets.
.DESCRIPTION
    Sets up mock implementations for SecretStore cmdlets with thread safety,
    retry logic, and enhanced validation for testing scenarios.
.PARAMETER MockBehavior
    Hashtable defining mock behavior including error simulation.
.EXAMPLE
    Mock-SecretStoreOperations -MockBehavior @{ 
        SimulateErrors = $true
        ErrorRate = 0.1
    }
#>
function Mock-SecretStoreOperations {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable]$MockBehavior = @{}
    )

    # Set up Set-Secret mock with retry logic
    Mock Set-Secret {
        param($Name, $Secret)

        # Validate parameters
        if ([string]::IsNullOrWhiteSpace($Name)) {
            throw [ArgumentException]::new("Invalid secret name")
        }

        if ($script:MockSecretStoreLocked) {
            throw [InvalidOperationException]::new("SecretStore is locked")
        }

        # Simulate random errors if configured
        if ($MockBehavior.SimulateErrors -and (Get-Random -Maximum 1.0) -lt $MockBehavior.ErrorRate) {
            throw [InvalidOperationException]::new("Simulated error storing secret")
        }

        # Store secret with thread safety
        $script:MockSecretStore.AddOrUpdate($Name, $Secret, { param($k, $v) $Secret })
    } -ParameterFilter { $null -ne $Name -and $null -ne $Secret }

    # Set up Get-Secret mock with error handling
    Mock Get-Secret {
        param($Name)

        if ($script:MockSecretStoreLocked) {
            throw [InvalidOperationException]::new("SecretStore is locked")
        }

        if (-not $script:MockSecretStore.ContainsKey($Name)) {
            throw [ItemNotFoundException]::new("Secret not found: $Name")
        }

        # Retrieve secret with thread safety
        $secret = $null
        if ($script:MockSecretStore.TryGetValue($Name, [ref]$secret)) {
            return $secret
        }
        
        throw [InvalidOperationException]::new("Failed to retrieve secret")
    } -ParameterFilter { $null -ne $Name }

    # Set up Remove-Secret mock with validation
    Mock Remove-Secret {
        param($Name)

        if ($script:MockSecretStoreLocked) {
            throw [InvalidOperationException]::new("SecretStore is locked")
        }

        $removed = $false
        $secret = $null
        if ($script:MockSecretStore.TryRemove($Name, [ref]$secret)) {
            $removed = $true
        }

        if (-not $removed) {
            throw [ItemNotFoundException]::new("Secret not found or could not be removed: $Name")
        }
    } -ParameterFilter { $null -ne $Name }

    # Set up Unlock-SecretStore mock
    Mock Unlock-SecretStore {
        param($Password)

        if (-not $script:MockSecretStoreLocked) {
            return $true
        }

        if ($null -eq $Password) {
            throw [ArgumentException]::new("Password required to unlock store")
        }

        $script:MockSecretStoreLocked = $false
        return $true
    }

    # Set up Lock-SecretStore mock
    Mock Lock-SecretStore {
        $script:MockSecretStoreLocked = $true
    }
}

<#
.SYNOPSIS
    Provides detailed validation of SecretStore operation calls.
.DESCRIPTION
    Validates SecretStore command calls with parameter checking and enhanced reporting.
.PARAMETER CommandName
    Name of the command to verify
.PARAMETER ExpectedParameters
    Expected parameter values and types
.PARAMETER Times
    Expected number of calls
.EXAMPLE
    Assert-SecretStoreCalls -CommandName 'Set-Secret' -ExpectedParameters @{
        Name = 'TestSecret'
        Secret = 'TestValue'
    } -Times 1
#>
function Assert-SecretStoreCalls {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$CommandName,

        [Parameter(Mandatory)]
        [hashtable]$ExpectedParameters,

        [Parameter()]
        [int]$Times = 1
    )

    # Verify call count
    $assertParams = @{
        CommandName = $CommandName
        Times = $Times
        Exactly = $true
    }

    # Build parameter filter
    $paramFilter = {
        $paramsMatch = $true
        foreach ($key in $ExpectedParameters.Keys) {
            if ($PSBoundParameters[$key] -ne $ExpectedParameters[$key]) {
                $paramsMatch = $false
                break
            }
        }
        $paramsMatch
    }

    # Assert with parameter validation
    Should -Invoke @assertParams -ParameterFilter $paramFilter

    return $true
}

# Export functions
Export-ModuleMember -Function @(
    'New-SecretStoreMock',
    'Mock-SecretStoreOperations',
    'Assert-SecretStoreCalls'
)