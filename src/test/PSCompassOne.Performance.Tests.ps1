#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

# Import required modules and helpers
. (Join-Path $PSScriptRoot 'helpers/TestHelpers.ps1')
. (Join-Path $PSScriptRoot 'helpers/AssertionHelpers.ps1')

# Performance test configuration
$PerformanceConfig = @{
    ResponseTimeThreshold = 2000 # 2 seconds in milliseconds
    MemoryThreshold = 500MB # 500MB maximum memory usage
    CpuThreshold = 75 # 75% CPU threshold
    BatchSize = 100 # Default batch size for bulk operations
    Iterations = 1000 # Number of test iterations
    WarmupIterations = 10 # Warmup iterations before measurement
    ParallelThreads = $env:NUMBER_OF_PROCESSORS # Maximum parallel threads
}

# Performance measurement class
class PerformanceMetrics {
    [datetime]$StartTime
    [datetime]$EndTime
    [timespan]$Duration
    [long]$MemoryUsedBytes
    [double]$CpuPercentage
    [int]$Iterations
    [hashtable]$Percentiles
    [double]$OperationsPerSecond
    [hashtable]$ResourceUtilization
    
    PerformanceMetrics() {
        $this.StartTime = Get-Date
        $this.Percentiles = @{}
        $this.ResourceUtilization = @{
            Memory = @()
            Cpu = @()
            Handles = @()
            Threads = @()
        }
    }

    [void] Complete() {
        $this.EndTime = Get-Date
        $this.Duration = $this.EndTime - $this.StartTime
        $this.OperationsPerSecond = $this.Iterations / $this.Duration.TotalSeconds
    }
}

# Performance measurement functions
function Measure-CommandPerformance {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory = $true)]
        [int]$Iterations,
        
        [Parameter()]
        [hashtable]$Thresholds = $PerformanceConfig,
        
        [Parameter()]
        [switch]$EnableParallel,
        
        [Parameter()]
        [string]$BaselineProfile
    )

    $metrics = [PerformanceMetrics]::new()
    $metrics.Iterations = $Iterations
    $timings = [System.Collections.ArrayList]::new()
    
    # Initialize performance counters
    $process = Get-Process -Id $PID
    $initialMemory = $process.WorkingSet64
    
    # Warmup phase
    1..$PerformanceConfig.WarmupIterations | ForEach-Object {
        & $ScriptBlock | Out-Null
    }
    
    if ($EnableParallel) {
        $runspacePool = [runspacefactory]::CreateRunspacePool(1, $PerformanceConfig.ParallelThreads)
        $runspacePool.Open()
        $jobs = @()
        
        1..$Iterations | ForEach-Object {
            $job = [powershell]::Create().AddScript($ScriptBlock)
            $job.RunspacePool = $runspacePool
            
            $jobs += @{
                PowerShell = $job
                Handle = $job.BeginInvoke()
            }
        }
        
        # Collect results
        foreach ($job in $jobs) {
            $result = $job.PowerShell.EndInvoke($job.Handle)
            $timings.Add($job.PowerShell.Streams.Timing) | Out-Null
            $job.PowerShell.Dispose()
        }
        
        $runspacePool.Close()
        $runspacePool.Dispose()
    }
    else {
        1..$Iterations | ForEach-Object {
            $timing = Measure-Command -Expression $ScriptBlock
            $timings.Add($timing.TotalMilliseconds) | Out-Null
            
            # Collect resource metrics
            $metrics.ResourceUtilization.Memory += (Get-Process -Id $PID).WorkingSet64
            $metrics.ResourceUtilization.Cpu += (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue
            $metrics.ResourceUtilization.Handles += (Get-Process -Id $PID).HandleCount
            $metrics.ResourceUtilization.Threads += (Get-Process -Id $PID).Threads.Count
        }
    }
    
    # Calculate percentiles
    $sortedTimings = $timings | Sort-Object
    $metrics.Percentiles = @{
        'P50' = $sortedTimings[[math]::Floor($sortedTimings.Count * 0.5)]
        'P90' = $sortedTimings[[math]::Floor($sortedTimings.Count * 0.9)]
        'P95' = $sortedTimings[[math]::Floor($sortedTimings.Count * 0.95)]
        'P99' = $sortedTimings[[math]::Floor($sortedTimings.Count * 0.99)]
    }
    
    # Calculate final metrics
    $metrics.Complete()
    $metrics.MemoryUsedBytes = (Get-Process -Id $PID).WorkingSet64 - $initialMemory
    $metrics.CpuPercentage = ($metrics.ResourceUtilization.Cpu | Measure-Object -Average).Average
    
    return $metrics
}

function Test-BulkOperationPerformance {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Asset', 'Finding', 'Relationship')]
        [string]$OperationType,
        
        [Parameter()]
        [int]$BatchSize = $PerformanceConfig.BatchSize,
        
        [Parameter()]
        [hashtable]$ResourceLimits = $PerformanceConfig,
        
        [Parameter()]
        [switch]$EnableParallel,
        
        [Parameter()]
        [timespan]$Timeout = [timespan]::FromMinutes(5)
    )
    
    $metrics = [PerformanceMetrics]::new()
    $testData = @()
    
    # Generate test data
    switch ($OperationType) {
        'Asset' {
            $testData = 1..$BatchSize | ForEach-Object {
                New-TestAsset -AssetType 'DEVICE' -Properties @{
                    name = "TestDevice_$_"
                    model = "TestModel_$_"
                    status = 'Active'
                }
            }
        }
        'Finding' {
            $testData = 1..$BatchSize | ForEach-Object {
                @{
                    title = "TestFinding_$_"
                    severity = 'Medium'
                    status = 'Open'
                }
            }
        }
        'Relationship' {
            $testData = 1..$BatchSize | ForEach-Object {
                @{
                    sourceId = "Source_$_"
                    targetId = "Target_$_"
                    type = 'CONNECTS_TO'
                }
            }
        }
    }
    
    # Measure bulk operation performance
    $scriptBlock = {
        param($Data, $Type)
        
        switch ($Type) {
            'Asset' { $Data | New-PSCompassOneAsset }
            'Finding' { $Data | New-PSCompassOneFinding }
            'Relationship' { $Data | New-PSCompassOneRelationship }
        }
    }
    
    $metrics = Measure-CommandPerformance -ScriptBlock { 
        & $scriptBlock $testData $OperationType 
    } -Iterations 1 -Thresholds $ResourceLimits -EnableParallel:$EnableParallel
    
    return $metrics
}

# Performance test suite
Describe 'PSCompassOne Performance Tests' {
    BeforeAll {
        $testEnv = Initialize-TestEnvironment -TestName 'Performance' -EnableParallel
    }

    AfterAll {
        Reset-TestEnvironment
    }

    Context 'Single Operation Performance' {
        It 'Should retrieve single asset within response time threshold' {
            $metrics = Measure-CommandPerformance -ScriptBlock {
                Get-PSCompassOneAsset -Id 'test-asset-id'
            } -Iterations 100
            
            $metrics.Percentiles.P95 | Should -BeLessOrEqual $PerformanceConfig.ResponseTimeThreshold
            $metrics.MemoryUsedBytes | Should -BeLessOrEqual $PerformanceConfig.MemoryThreshold
            $metrics.CpuPercentage | Should -BeLessOrEqual $PerformanceConfig.CpuThreshold
        }

        It 'Should create single asset within response time threshold' {
            $asset = New-TestAsset -AssetType 'DEVICE' -Properties @{
                name = 'PerformanceTest'
                model = 'TestModel'
                status = 'Active'
            }
            
            $metrics = Measure-CommandPerformance -ScriptBlock {
                New-PSCompassOneAsset -Asset $asset
            } -Iterations 100
            
            $metrics.Percentiles.P95 | Should -BeLessOrEqual $PerformanceConfig.ResponseTimeThreshold
        }
    }

    Context 'Bulk Operation Performance' {
        It 'Should handle bulk asset creation efficiently' {
            $metrics = Test-BulkOperationPerformance -OperationType 'Asset' -BatchSize 100 -EnableParallel
            
            $metrics.OperationsPerSecond | Should -BeGreaterOrEqual 10
            $metrics.MemoryUsedBytes | Should -BeLessOrEqual $PerformanceConfig.MemoryThreshold
        }

        It 'Should handle bulk relationship creation efficiently' {
            $metrics = Test-BulkOperationPerformance -OperationType 'Relationship' -BatchSize 100 -EnableParallel
            
            $metrics.OperationsPerSecond | Should -BeGreaterOrEqual 10
            $metrics.MemoryUsedBytes | Should -BeLessOrEqual $PerformanceConfig.MemoryThreshold
        }
    }

    Context 'Resource Utilization' {
        It 'Should maintain stable memory usage during repeated operations' {
            $initialMemory = (Get-Process -Id $PID).WorkingSet64
            
            $metrics = Measure-CommandPerformance -ScriptBlock {
                1..100 | ForEach-Object {
                    Get-PSCompassOneAsset -Id "test-$_"
                }
            } -Iterations 10
            
            $finalMemory = (Get-Process -Id $PID).WorkingSet64
            $memoryGrowth = $finalMemory - $initialMemory
            
            $memoryGrowth | Should -BeLessOrEqual ($PerformanceConfig.MemoryThreshold * 0.1)
        }

        It 'Should handle parallel operations efficiently' {
            $metrics = Measure-CommandPerformance -ScriptBlock {
                Get-PSCompassOneAsset -Id 'test-asset'
            } -Iterations 100 -EnableParallel
            
            $metrics.Percentiles.P95 | Should -BeLessOrEqual ($PerformanceConfig.ResponseTimeThreshold * 1.5)
            $metrics.CpuPercentage | Should -BeLessOrEqual $PerformanceConfig.CpuThreshold
        }
    }
}