#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }, @{ ModuleName='PSScriptAnalyzer'; ModuleVersion='1.20.0' }

# Import test helpers and configuration
using module './helpers/TestHelpers.ps1'
Import-Module -Name (Join-Path $PSScriptRoot 'helpers/TestHelpers.ps1') -Force
$TestConfiguration = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'config/test-config.psd1')

# Global test state
$Global:TestState = @{
    Configuration = $null
    Environment = $null
    Results = @{}
    Metrics = @{}
    Security = @{}
    Resources = @{}
}

function Initialize-PesterConfiguration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$TestConfiguration
    )

    try {
        $config = New-PesterConfiguration

        # Run configuration
        $config.Run.Path = $PSScriptRoot
        $config.Run.PassThru = $true
        $config.Run.Exit = $true
        $config.Run.EnableExit = $true
        $config.Run.SkipRemainingOnFailure = 'Container'

        # Output configuration
        $config.Output.Verbosity = if ($TestConfiguration.EnableVerboseLogging) { 'Detailed' } else { 'Normal' }
        $config.Output.CIFormat = 'Auto'
        $config.Output.StackTraceVerbosity = 'Full'

        # Code coverage configuration
        $config.CodeCoverage.Enabled = $true
        $config.CodeCoverage.OutputFormat = 'JaCoCo'
        $config.CodeCoverage.OutputPath = Join-Path $TestConfiguration.TestDataPath 'coverage.xml'
        $config.CodeCoverage.Path = @(
            (Join-Path $PSScriptRoot '..' 'PSCompassOne' '*.ps1'),
            (Join-Path $PSScriptRoot '..' 'PSCompassOne' '*.psm1')
        )
        $config.CodeCoverage.ExcludeTests = $true

        # Test result configuration
        $config.TestResult.Enabled = $true
        $config.TestResult.OutputFormat = 'NUnitXml'
        $config.TestResult.OutputPath = Join-Path $TestConfiguration.TestDataPath 'testResults.xml'

        # Debug configuration
        $config.Debug.ShowFullErrors = $TestConfiguration.EnableDebugOutput
        $config.Debug.WriteDebugMessages = $TestConfiguration.EnableDebugOutput
        $config.Debug.WriteVerboseMessages = $TestConfiguration.EnableVerboseLogging

        # Container configuration
        $config.Container.Parallel = $TestConfiguration.ParallelTestExecution
        $config.Container.Tags = $TestConfiguration.TestCategories
        $config.Container.ExcludeTag = $TestConfiguration.ExcludedTests

        # Filter configuration
        if ($TestConfiguration.SkipLongRunningTests) {
            $config.Filter.ExcludeTag = @('LongRunning')
        }

        return $config
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'PesterConfigurationError',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $config
            )
        )
    }
}

function Set-PesterOutput {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$Configuration
    )

    try {
        # Configure CI-specific output if running in CI environment
        if ($env:CI -or $env:TF_BUILD -or $env:GITHUB_ACTIONS) {
            $Configuration.Output.CIFormat = switch ($true) {
                $env:TF_BUILD { 'AzureDevOps' }
                $env:GITHUB_ACTIONS { 'GithubActions' }
                default { 'Auto' }
            }
        }

        # Configure additional test result formats for CI integration
        $Configuration.TestResult.OutputFormat = @('NUnitXml', 'JUnitXml')
        $Configuration.TestResult.OutputPath = @(
            (Join-Path $TestConfiguration.TestDataPath 'testResults.nunit.xml'),
            (Join-Path $TestConfiguration.TestDataPath 'testResults.junit.xml')
        )

        # Set up enhanced error formatting
        $Configuration.Output.StackTraceVerbosity = 'Full'
        $Configuration.Output.MaxStackTraceLines = 100
        $Configuration.Output.MaxErrorLines = 50

        # Configure timing and performance logging
        $Configuration.Run.CollectTiming = $true
        $Configuration.Output.ShowTestTiming = $true
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'PesterOutputConfigurationError',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $Configuration
            )
        )
    }
}

function Initialize-TestDependencies {
    [CmdletBinding()]
    param()

    try {
        # Verify Pester version
        $pesterModule = Get-Module -Name Pester -ListAvailable | 
            Sort-Object Version -Descending | 
            Select-Object -First 1

        if ($pesterModule.Version -lt [Version]'5.0.0') {
            throw "Pester version 5.0.0 or higher is required. Current version: $($pesterModule.Version)"
        }

        # Verify PSScriptAnalyzer
        $analyzerModule = Get-Module -Name PSScriptAnalyzer -ListAvailable |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if (-not $analyzerModule) {
            throw "PSScriptAnalyzer module is required but not installed"
        }

        # Import required modules
        Import-Module -Name Pester -MinimumVersion '5.0.0' -Force
        Import-Module -Name PSScriptAnalyzer -MinimumVersion '1.20.0' -Force

        # Set up module path environment
        $moduleRoot = Split-Path -Parent $PSScriptRoot
        if ($env:PSModulePath -notlike "*$moduleRoot*") {
            $env:PSModulePath = "$moduleRoot$([IO.Path]::PathSeparator)$env:PSModulePath"
        }

        # Initialize module caching
        $Global:TestState.ModuleCache = @{}
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'TestDependencyInitializationError',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $null
            )
        )
    }
}

# Initialize test environment
Initialize-TestDependencies
$Global:TestState.Configuration = Initialize-PesterConfiguration -TestConfiguration $TestConfiguration
Set-PesterOutput -Configuration $Global:TestState.Configuration

# Export configuration for use in test files
Export-ModuleMember -Variable TestState