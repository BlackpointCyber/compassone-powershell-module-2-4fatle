#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

BeforeAll {
    # Import test helpers and mocks
    . "$PSScriptRoot/helpers/TestHelpers.ps1"
    . "$PSScriptRoot/mocks/MockAPI.ps1"

    # Initialize test environment
    $script:testEnv = Initialize-TestEnvironment -TestName 'Pipeline.Tests' -UseMockData -EnableParallel
    Initialize-MockApi

    # Initialize performance monitoring
    $script:perfCounters = @{
        Memory = @{
            Initial = [System.GC]::GetTotalMemory($true)
            Peak = 0
        }
        Timing = @{
            Start = Get-Date
            Operations = @{}
        }
    }
}

Describe 'PSCompassOne Pipeline Tests' {
    Context 'Pipeline Input Validation' {
        BeforeAll {
            # Create test data for pipeline operations
            $script:testAssets = 1..10 | ForEach-Object {
                New-TestAsset -AssetType 'DEVICE' -Properties @{
                    name = "TestDevice$_"
                    model = "TestModel$_"
                    osName = "Windows"
                    osVersion = "10.0.$_"
                }
            }
        }

        It 'Should accept pipeline input by value for Get-PSCompassOneAsset' {
            # Test pipeline input by value
            $result = $script:testAssets | Get-PSCompassOneAsset
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be $script:testAssets.Count
        }

        It 'Should accept pipeline input by property name for Get-PSCompassOneAsset' {
            # Test pipeline input by property name
            $idObjects = $script:testAssets | Select-Object -Property @{Name='Id';Expression={$_.Id}}
            $result = $idObjects | Get-PSCompassOneAsset
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be $idObjects.Count
        }

        It 'Should validate pipeline input types' {
            # Test invalid input type handling
            $invalidInput = @("invalid", 123, $null)
            { $invalidInput | Get-PSCompassOneAsset } | Should -Throw -ErrorId 'ParameterBindingValidationException'
        }
    }

    Context 'Pipeline Output Processing' {
        It 'Should properly format pipeline output objects' {
            $asset = New-TestAsset -AssetType 'DEVICE' -Properties @{
                name = "OutputTest"
                model = "TestModel"
            }
            
            $result = $asset | Get-PSCompassOneAsset | Select-Object -First 1
            $result.PSObject.TypeNames[0] | Should -Be 'PSCompassOne.Asset'
            $result.PSObject.Properties.Name | Should -Contain 'Id'
            $result.PSObject.Properties.Name | Should -Contain 'Name'
        }

        It 'Should maintain property order in pipeline output' {
            $asset = New-TestAsset -AssetType 'DEVICE' -Properties @{
                name = "OrderTest"
                model = "TestModel"
            }
            
            $result = $asset | Get-PSCompassOneAsset | Get-Member -MemberType NoteProperty
            $result[0].Name | Should -Be 'Id'
            $result[1].Name | Should -Be 'Name'
            $result[2].Name | Should -Be 'Type'
        }
    }

    Context 'Pipeline Performance' {
        BeforeAll {
            # Create large dataset for performance testing
            $script:largeDataset = 1..1000 | ForEach-Object {
                New-TestAsset -AssetType 'DEVICE' -Properties @{
                    name = "PerfDevice$_"
                    model = "PerfModel$_"
                }
            }
        }

        It 'Should handle large datasets efficiently' {
            # Measure memory usage and execution time
            $initialMemory = [System.GC]::GetTotalMemory($true)
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            $result = $script:largeDataset | Get-PSCompassOneAsset
            
            $stopwatch.Stop()
            $finalMemory = [System.GC]::GetTotalMemory($true)
            
            # Verify performance metrics
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 30000
            ($finalMemory - $initialMemory) / 1MB | Should -BeLessThan 500
            $result.Count | Should -Be $script:largeDataset.Count
        }

        It 'Should support parallel pipeline processing' {
            # Test parallel processing with ThrottleLimit
            $result = $script:largeDataset | ForEach-Object -ThrottleLimit 4 -Parallel {
                $_ | Get-PSCompassOneAsset
            }
            
            $result.Count | Should -Be $script:largeDataset.Count
        }
    }

    Context 'Pipeline Error Handling' {
        It 'Should properly handle pipeline errors' {
            # Test error propagation
            $errorAsset = New-TestAsset -AssetType 'DEVICE' -Properties @{
                name = "ErrorTest"
                model = "ErrorModel"
            }
            $errorAsset.Id = "invalid_id"

            { $errorAsset | Get-PSCompassOneAsset -ErrorAction Stop } | 
                Should -Throw -ErrorId 'PSCompassOne.AssetNotFound'
        }

        It 'Should continue pipeline execution after non-terminating errors' {
            $mixedAssets = @(
                (New-TestAsset -AssetType 'DEVICE' -Properties @{
                    name = "ValidDevice"
                    model = "ValidModel"
                }),
                (New-TestAsset -AssetType 'DEVICE' -Properties @{
                    name = "ErrorDevice"
                    model = "ErrorModel"
                })
            )
            $mixedAssets[1].Id = "invalid_id"

            $result = $mixedAssets | Get-PSCompassOneAsset -ErrorAction SilentlyContinue
            $result.Count | Should -Be 1
            $result.Name | Should -Be "ValidDevice"
        }
    }

    Context 'Cross-Platform Pipeline Compatibility' {
        It 'Should handle platform-specific line endings' {
            $asset = New-TestAsset -AssetType 'DEVICE' -Properties @{
                name = "CrossPlatform`r`nTest"
                model = "TestModel"
            }
            
            $result = $asset | Get-PSCompassOneAsset
            $result.Name | Should -Be "CrossPlatform`nTest"
        }

        It 'Should maintain encoding consistency across platforms' {
            $asset = New-TestAsset -AssetType 'DEVICE' -Properties @{
                name = "Encoding€Test"
                model = "TestModel"
            }
            
            $result = $asset | Get-PSCompassOneAsset
            $result.Name | Should -Be "Encoding€Test"
        }
    }
}

AfterAll {
    # Clean up test environment
    if ($script:testEnv) {
        # Record final performance metrics
        $script:perfCounters.Memory.Final = [System.GC]::GetTotalMemory($true)
        $script:perfCounters.Timing.End = Get-Date
        
        # Log performance results
        $performanceLog = @{
            TestDuration = ($script:perfCounters.Timing.End - $script:perfCounters.Timing.Start).TotalSeconds
            PeakMemoryMB = ($script:perfCounters.Memory.Peak / 1MB)
            FinalMemoryMB = ($script:perfCounters.Memory.Final / 1MB)
            OperationTimings = $script:perfCounters.Timing.Operations
        }
        
        $performanceLog | ConvertTo-Json | Out-File -Path (Join-Path $script:testEnv.TestDataPath "pipeline_performance.json")
    }
}