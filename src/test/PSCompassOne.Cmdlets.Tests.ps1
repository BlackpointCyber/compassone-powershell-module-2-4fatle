#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

# Import required test helpers and configuration
using module './helpers/TestHelpers.ps1'
using module './helpers/AssertionHelpers.ps1'
using module './mocks/MockAPI.ps1'

BeforeAll {
    # Initialize test environment
    $script:testConfig = Initialize-TestEnvironment -TestName 'PSCompassOne.Cmdlets' -UseMockData -EnableParallel
    
    # Initialize mock API endpoints
    Initialize-MockApi
    
    # Import module under test
    Import-Module PSCompassOne -Force
}

Describe 'Asset Management Cmdlets' {
    BeforeAll {
        # Create test assets
        $script:testDevice = New-TestAsset -AssetType 'DEVICE' -Properties @{
            name = 'TestDevice1'
            model = 'TestModel'
            osName = 'Windows'
            osVersion = '10.0'
            ips = @('192.168.1.1')
            macs = @('00:11:22:33:44:55')
        }
        
        $script:testContainer = New-TestAsset -AssetType 'CONTAINER' -Properties @{
            name = 'TestContainer1'
            image = 'nginx:latest'
            ports = @('80:80')
            command = 'nginx -g daemon off;'
            imageTag = 'latest'
        }
    }

    Context 'Get-PSCompassOneAsset' {
        It 'Should retrieve a single asset by ID' {
            $result = Get-PSCompassOneAsset -Id $testDevice.Id
            Assert-AssetProperties -Asset $result -AssetType 'DEVICE'
            $result.Id | Should -Be $testDevice.Id
        }

        It 'Should list all assets with pagination' {
            $results = Get-PSCompassOneAsset -PageSize 10 -Page 1
            $results | Should -Not -BeNullOrEmpty
            $results.Count | Should -BeLessOrEqual 10
            $results | ForEach-Object {
                Assert-AssetProperties -Asset $_ -AssetType $_.Type
            }
        }

        It 'Should filter assets by type' {
            $results = Get-PSCompassOneAsset -Type 'DEVICE'
            $results | Should -Not -BeNullOrEmpty
            $results | ForEach-Object {
                $_.Type | Should -Be 'DEVICE'
            }
        }

        It 'Should handle API errors gracefully' {
            Mock Invoke-RestMethod { throw [System.Net.WebException]::new('API Error') }
            { Get-PSCompassOneAsset -Id 'invalid-id' } | Should -Throw -ErrorId 'AssetNotFound'
        }
    }

    Context 'New-PSCompassOneAsset' {
        It 'Should create a new device asset' {
            $newAsset = @{
                name = 'NewDevice'
                type = 'DEVICE'
                model = 'TestModel'
                osName = 'Windows'
                osVersion = '10.0'
            }
            
            $result = New-PSCompassOneAsset @newAsset
            Assert-AssetProperties -Asset $result -AssetType 'DEVICE'
            $result.name | Should -Be $newAsset.name
        }

        It 'Should create a new container asset' {
            $newAsset = @{
                name = 'NewContainer'
                type = 'CONTAINER'
                image = 'nginx:latest'
                ports = @('80:80')
            }
            
            $result = New-PSCompassOneAsset @newAsset
            Assert-AssetProperties -Asset $result -AssetType 'CONTAINER'
            $result.name | Should -Be $newAsset.name
        }

        It 'Should validate required properties' {
            { New-PSCompassOneAsset -Type 'DEVICE' } | Should -Throw -ErrorId 'ValidationError'
        }

        It 'Should support pipeline input' {
            $assets = @(
                @{ name = 'Pipeline1'; type = 'DEVICE'; model = 'Test' }
                @{ name = 'Pipeline2'; type = 'DEVICE'; model = 'Test' }
            )
            
            $results = $assets | New-PSCompassOneAsset
            $results.Count | Should -Be 2
            $results | ForEach-Object {
                Assert-AssetProperties -Asset $_ -AssetType 'DEVICE'
            }
        }
    }

    Context 'Set-PSCompassOneAsset' {
        It 'Should update an existing asset' {
            $updateParams = @{
                Id = $testDevice.Id
                Status = 'Inactive'
                Tags = @('test', 'update')
            }
            
            $result = Set-PSCompassOneAsset @updateParams
            Assert-AssetProperties -Asset $result -AssetType 'DEVICE'
            $result.Status | Should -Be 'Inactive'
            $result.Tags | Should -Contain 'test'
        }

        It 'Should handle partial updates' {
            $result = Set-PSCompassOneAsset -Id $testDevice.Id -Status 'Active'
            $result.Status | Should -Be 'Active'
        }

        It 'Should validate asset existence' {
            { Set-PSCompassOneAsset -Id 'invalid-id' -Status 'Active' } | Should -Throw -ErrorId 'AssetNotFound'
        }

        It 'Should support pipeline input' {
            $updates = @(
                @{ Id = $testDevice.Id; Status = 'Inactive' }
                @{ Id = $testContainer.Id; Status = 'Inactive' }
            )
            
            $results = $updates | Set-PSCompassOneAsset
            $results.Count | Should -Be 2
            $results | ForEach-Object {
                $_.Status | Should -Be 'Inactive'
            }
        }
    }

    Context 'Remove-PSCompassOneAsset' {
        It 'Should delete an asset' {
            Remove-PSCompassOneAsset -Id $testDevice.Id -Confirm:$false
            { Get-PSCompassOneAsset -Id $testDevice.Id } | Should -Throw -ErrorId 'AssetNotFound'
        }

        It 'Should require confirmation by default' {
            $result = Remove-PSCompassOneAsset -Id $testContainer.Id -Confirm:$false -WhatIf
            $result | Should -BeNullOrEmpty
        }

        It 'Should support pipeline input' {
            $assets = @($testDevice.Id, $testContainer.Id)
            $assets | Remove-PSCompassOneAsset -Confirm:$false
            $assets | ForEach-Object {
                { Get-PSCompassOneAsset -Id $_ } | Should -Throw -ErrorId 'AssetNotFound'
            }
        }
    }
}

Describe 'Finding Management Cmdlets' {
    BeforeAll {
        # Create test findings
        $script:testFinding = @{
            title = 'Test Finding'
            severity = 'High'
            description = 'Test Description'
            assetId = $testDevice.Id
        }
    }

    Context 'Get-PSCompassOneFinding' {
        It 'Should retrieve a single finding by ID' {
            $result = Get-PSCompassOneFinding -Id $testFinding.Id
            $result.Id | Should -Be $testFinding.Id
            $result.title | Should -Be $testFinding.title
        }

        It 'Should list findings with filtering' {
            $results = Get-PSCompassOneFinding -Severity 'High'
            $results | Should -Not -BeNullOrEmpty
            $results | ForEach-Object {
                $_.severity | Should -Be 'High'
            }
        }

        It 'Should support pagination' {
            $results = Get-PSCompassOneFinding -PageSize 5 -Page 1
            $results.Count | Should -BeLessOrEqual 5
        }
    }

    Context 'New-PSCompassOneFinding' {
        It 'Should create a new finding' {
            $result = New-PSCompassOneFinding @testFinding
            $result.title | Should -Be $testFinding.title
            $result.severity | Should -Be $testFinding.severity
        }

        It 'Should validate required properties' {
            { New-PSCompassOneFinding -Title 'Invalid' } | Should -Throw -ErrorId 'ValidationError'
        }
    }
}

Describe 'Authentication and Configuration' {
    Context 'Connect-PSCompassOne' {
        It 'Should authenticate with API key' {
            $result = Connect-PSCompassOne -ApiKey 'test-key'
            $result.authenticated | Should -BeTrue
        }

        It 'Should store credentials securely' {
            Connect-PSCompassOne -ApiKey 'test-key'
            $stored = Get-PSCompassOneConfiguration
            $stored.ApiEndpoint | Should -Not -BeNullOrEmpty
        }

        It 'Should handle invalid credentials' {
            { Connect-PSCompassOne -ApiKey 'invalid-key' } | Should -Throw -ErrorId 'AuthenticationError'
        }
    }

    Context 'Get-PSCompassOneConfiguration' {
        It 'Should retrieve current configuration' {
            $config = Get-PSCompassOneConfiguration
            $config.ApiEndpoint | Should -Not -BeNullOrEmpty
            $config.ApiVersion | Should -Not -BeNullOrEmpty
        }
    }
}

AfterAll {
    # Clean up test environment
    Reset-TestEnvironment -Configuration $testConfig
    Remove-Module PSCompassOne -Force
}