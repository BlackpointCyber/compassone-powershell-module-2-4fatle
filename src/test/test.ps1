#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

# Import required modules and configurations
. (Join-Path $PSScriptRoot 'helpers/TestHelpers.ps1')
$TestConfig = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'config/test-config.psd1')

function Initialize-TestSuite {
    [CmdletBinding()]
    param (
        [Parameter()]
        [switch]$UseMockData,

        [Parameter()]
        [int]$ParallelJobs = $env:NUMBER_OF_PROCESSORS,

        [Parameter()]
        [switch]$DetailedLogging
    )

    try {
        # Initialize test environment with platform-specific settings
        $testEnvironment = Initialize-TestEnvironment -TestName 'PSCompassOne' `
            -UseMockData:$UseMockData `
            -EnableParallel:($ParallelJobs -gt 1) `
            -LogLevel $(if ($DetailedLogging) { 'Verbose' } else { 'Information' })

        # Configure Pester for parallel execution
        $pesterConfig = New-PesterConfiguration
        $pesterConfig.Run.Path = $PSScriptRoot
        $pesterConfig.Run.PassThru = $true
        $pesterConfig.Run.Exit = $true
        $pesterConfig.Output.Verbosity = if ($DetailedLogging) { 'Detailed' } else { 'Normal' }
        $pesterConfig.Run.Container.Parallel = ($ParallelJobs -gt 1)
        $pesterConfig.Run.Container.Jobs = $ParallelJobs

        # Add configuration to test environment
        $testEnvironment.PesterConfig = $pesterConfig
        $testEnvironment.TestConfig = $TestConfig

        Write-Verbose "Test suite initialized with parallel jobs: $ParallelJobs"
        return $testEnvironment
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'TestSuiteInitializationError',
                [System.Management.Automation.ErrorCategory]::OperationStopped,
                $testEnvironment
            )
        )
    }
}

function Invoke-ModuleTests {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$Configuration,

        [Parameter()]
        [string[]]$Categories,

        [Parameter()]
        [switch]$ParallelExecution
    )

    try {
        Write-Verbose "Starting test execution with configuration: $($Configuration.TestId)"

        # Load test suites
        $testSuites = @(
            @{
                Path = Join-Path $PSScriptRoot 'PSCompassOne.Module.Tests.ps1'
                Name = 'Module Tests'
                Priority = 1
            },
            @{
                Path = Join-Path $PSScriptRoot 'PSCompassOne.API.Tests.ps1'
                Name = 'API Tests'
                Priority = 2
            },
            @{
                Path = Join-Path $PSScriptRoot 'PSCompassOne.Integration.Tests.ps1'
                Name = 'Integration Tests'
                Priority = 3
            }
        )

        # Filter test suites by category if specified
        if ($Categories) {
            $testSuites = $testSuites | Where-Object {
                $_.Name -in $Categories
            }
        }

        # Configure test execution
        $pesterConfig = $Configuration.PesterConfig
        $pesterConfig.Run.Container.Parallel = $ParallelExecution

        # Execute test suites
        $results = foreach ($suite in ($testSuites | Sort-Object Priority)) {
            Write-Verbose "Executing test suite: $($suite.Name)"
            $pesterConfig.Run.Path = $suite.Path
            
            $result = Invoke-Pester -Configuration $pesterConfig
            
            [PSCustomObject]@{
                Suite = $suite.Name
                Passed = $result.PassedCount
                Failed = $result.FailedCount
                Skipped = $result.SkippedCount
                Duration = $result.Duration
                Result = $result
            }
        }

        # Aggregate results
        $summary = [PSCustomObject]@{
            TotalPassed = ($results | Measure-Object -Property Passed -Sum).Sum
            TotalFailed = ($results | Measure-Object -Property Failed -Sum).Sum
            TotalSkipped = ($results | Measure-Object -Property Skipped -Sum).Sum
            TotalDuration = ($results | Measure-Object -Property Duration -Sum).Sum
            SuiteResults = $results
            StartTime = $Configuration.StartTime
            EndTime = Get-Date
            TestId = $Configuration.TestId
        }

        Write-Verbose "Test execution completed. Total tests: $($summary.TotalPassed + $summary.TotalFailed + $summary.TotalSkipped)"
        return $summary
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'TestExecutionError',
                [System.Management.Automation.ErrorCategory]::OperationStopped,
                $Configuration
            )
        )
    }
}

function Reset-TestSuite {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$TestEnvironment,

        [Parameter()]
        [switch]$Force
    )

    try {
        Write-Verbose "Cleaning up test environment: $($TestEnvironment.TestId)"

        # Clean up test data directory
        if (Test-Path $TestEnvironment.TestDataPath) {
            Remove-Item -Path $TestEnvironment.TestDataPath -Recurse -Force:$Force
        }

        # Clean up parallel execution context if it exists
        if ($TestEnvironment.ParallelContext) {
            if ($TestEnvironment.ParallelContext.RunspacePool) {
                $TestEnvironment.ParallelContext.RunspacePool.Close()
                $TestEnvironment.ParallelContext.RunspacePool.Dispose()
            }
            
            # Clean up any remaining jobs
            foreach ($job in $TestEnvironment.ParallelContext.Jobs) {
                if ($job.State -ne 'Completed') {
                    $job.Stop()
                }
                $job.Dispose()
            }
        }

        # Archive test logs
        if (Test-Path $TestEnvironment.LogPath) {
            $archivePath = Join-Path $PSScriptRoot "logs/archive"
            if (-not (Test-Path $archivePath)) {
                New-Item -Path $archivePath -ItemType Directory -Force | Out-Null
            }
            
            $archiveFile = Join-Path $archivePath "test_$($TestEnvironment.TestId)_$(Get-Date -Format 'yyyyMMddHHmmss').log"
            Move-Item -Path $TestEnvironment.LogPath -Destination $archiveFile -Force
        }

        Write-Verbose "Test environment cleanup completed"
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'TestSuiteCleanupError',
                [System.Management.Automation.ErrorCategory]::OperationStopped,
                $TestEnvironment
            )
        )
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Initialize-TestSuite',
    'Invoke-ModuleTests',
    'Reset-TestSuite'
)