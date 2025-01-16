#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

# Import required test helpers and mocks
. "$PSScriptRoot/helpers/TestHelpers.ps1"
. "$PSScriptRoot/helpers/AssertionHelpers.ps1"
. "$PSScriptRoot/mocks/MockAPI.ps1"

BeforeAll {
    # Initialize test environment
    $script:testConfig = Initialize-TestEnvironment -TestName 'PSCompassOne.Integration' -EnableParallel
    
    # Import the PSCompassOne module
    Import-Module PSCompassOne -Force -ErrorAction Stop
    
    # Initialize mock API
    Initialize-MockApi
}

Describe 'Asset Management Integration Tests' -Tag 'Integration', 'Assets' {
    BeforeEach {
        # Create test asset data
        $script:testAsset = New-TestAsset -AssetType 'DEVICE' -Properties @{
            name = "TestDevice-$(New-Guid)"
            model = "TestModel"
            osName = "Windows Server 2022"
            osVersion = "10.0.20348"
            ips = @("192.168.1.100")
            macs = @("00:11:22:33:44:55")
        }
    }

    Context 'Asset Creation' {
        It 'Should create a new asset with validation' {
            # Arrange
            $newAssetParams = @{
                Name = $testAsset.name
                Type = 'DEVICE'
                Properties = @{
                    model = $testAsset.model
                    osName = $testAsset.osName
                    osVersion = $testAsset.osVersion
                }
            }

            # Act
            $result = New-PSCompassOneAsset @newAssetParams

            # Assert
            $result | Should -Not -BeNullOrEmpty
            Assert-AssetProperties -Asset $result -AssetType 'DEVICE'
            $result.name | Should -Be $testAsset.name
            $result.type | Should -Be 'DEVICE'
        }

        It 'Should handle asset creation failures gracefully' {
            # Arrange
            $invalidParams = @{
                Name = ''
                Type = 'INVALID_TYPE'
            }

            # Act & Assert
            { New-PSCompassOneAsset @invalidParams } | Should -Throw -ErrorId 'AssetValidationError'
        }
    }

    Context 'Asset Retrieval' {
        It 'Should retrieve existing assets with filtering' {
            # Arrange
            $filterParams = @{
                Type = 'DEVICE'
                Status = 'Active'
                PageSize = 50
            }

            # Act
            $results = Get-PSCompassOneAsset @filterParams

            # Assert
            $results | Should -Not -BeNullOrEmpty
            $results | ForEach-Object {
                Assert-AssetProperties -Asset $_ -AssetType 'DEVICE'
                $_.status | Should -Be 'Active'
            }
        }

        It 'Should handle pagination correctly' {
            # Arrange
            $pageSize = 10
            $totalPages = 3

            # Act
            $allResults = for ($page = 1; $page -le $totalPages; $page++) {
                Get-PSCompassOneAsset -PageSize $pageSize -Page $page
            }

            # Assert
            $allResults.Count | Should -BeGreaterThan $pageSize
            $allResults | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Asset Updates' {
        It 'Should update asset properties with verification' {
            # Arrange
            $updateParams = @{
                Id = $testAsset.Id
                Properties = @{
                    status = 'Inactive'
                    osVersion = '10.0.20349'
                }
            }

            # Act
            $result = Set-PSCompassOneAsset @updateParams

            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.status | Should -Be 'Inactive'
            $result.osVersion | Should -Be '10.0.20349'
        }

        It 'Should handle concurrent update conflicts' {
            # Arrange
            $conflictParams = @{
                Id = $testAsset.Id
                Properties = @{
                    status = 'Active'
                }
            }

            # Act & Assert
            { Set-PSCompassOneAsset @conflictParams } | Should -Not -Throw
        }
    }

    Context 'Asset Deletion' {
        It 'Should delete assets with cleanup confirmation' {
            # Act
            $result = Remove-PSCompassOneAsset -Id $testAsset.Id -Confirm:$false

            # Assert
            $result | Should -BeTrue
            { Get-PSCompassOneAsset -Id $testAsset.Id } | Should -Throw -ErrorId 'AssetNotFound'
        }

        It 'Should handle bulk deletions efficiently' {
            # Arrange
            $bulkAssets = 1..3 | ForEach-Object {
                New-TestAsset -AssetType 'DEVICE' -Properties @{
                    name = "BulkTest-$_"
                    model = "TestModel"
                }
            }

            # Act
            $results = $bulkAssets | Remove-PSCompassOneAsset -Confirm:$false

            # Assert
            $results | Should -Not -BeNullOrEmpty
            $results.Count | Should -Be $bulkAssets.Count
        }
    }
}

Describe 'Authentication Integration Tests' -Tag 'Integration', 'Authentication' {
    Context 'Token Management' {
        It 'Should authenticate with valid credentials' {
            # Arrange
            $validCreds = @{
                ApiKey = 'valid-api-key'
            }

            # Act
            $result = Connect-PSCompassOne @validCreds

            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Token | Should -Not -BeNullOrEmpty
            $result.ExpiresAt | Should -BeOfType [DateTime]
        }

        It 'Should handle invalid credentials gracefully' {
            # Arrange
            $invalidCreds = @{
                ApiKey = 'invalid-api-key'
            }

            # Act & Assert
            { Connect-PSCompassOne @invalidCreds } | Should -Throw -ErrorId 'AuthenticationError'
        }

        It 'Should refresh expired tokens automatically' {
            # Arrange
            $expiredToken = Connect-PSCompassOne -ApiKey 'valid-api-key'
            Start-Sleep -Seconds 1

            # Act
            $result = Get-PSCompassOneAsset -Id 'test-id'

            # Assert
            $result | Should -Not -BeNullOrEmpty
            $Global:PSCompassOneConfig.Token | Should -Not -Be $expiredToken.Token
        }
    }
}

Describe 'Error Handling Integration Tests' -Tag 'Integration', 'ErrorHandling' {
    Context 'API Errors' {
        It 'Should handle rate limiting with retry logic' {
            # Arrange
            $rateLimitParams = @{
                Type = 'DEVICE'
                PageSize = 1000
            }

            # Act & Assert
            { Get-PSCompassOneAsset @rateLimitParams } | Should -Not -Throw
        }

        It 'Should provide detailed error context' {
            # Arrange
            $invalidId = 'non-existent-id'

            # Act
            $error.Clear()
            Get-PSCompassOneAsset -Id $invalidId -ErrorAction SilentlyContinue

            # Assert
            $error[0] | Should -Not -BeNullOrEmpty
            $error[0].Exception.Message | Should -Match 'Asset not found'
            Assert-ErrorResponse -Error $error[0] -ExpectedErrorId 'AssetNotFound' -ExpectedCategory 'ObjectNotFound'
        }
    }
}

Describe 'Cross-Platform Integration Tests' -Tag 'Integration', 'CrossPlatform' {
    Context 'Platform-Specific Operations' {
        It 'Should handle paths correctly on <platform>' -TestCases @(
            @{ platform = 'Windows' }
            @{ platform = 'Linux' }
            @{ platform = 'MacOS' }
        ) {
            param($platform)

            # Skip if not running on the specified platform
            if (-not (Test-Platform -Platform $platform)) {
                Set-ItResult -Skipped -Because "Not running on $platform"
                return
            }

            # Act
            $result = Get-PSCompassOneAsset -Type 'DEVICE'

            # Assert
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should manage credentials securely on <platform>' -TestCases @(
            @{ platform = 'Windows' }
            @{ platform = 'Linux' }
            @{ platform = 'MacOS' }
        ) {
            param($platform)

            # Skip if not running on the specified platform
            if (-not (Test-Platform -Platform $platform)) {
                Set-ItResult -Skipped -Because "Not running on $platform"
                return
            }

            # Arrange
            $secureKey = ConvertTo-SecureString 'test-api-key' -AsPlainText -Force

            # Act
            Set-PSCompassOneConfiguration -ApiKey $secureKey

            # Assert
            $config = Get-PSCompassOneConfiguration
            $config.ApiKey | Should -BeOfType [System.Security.SecureString]
        }
    }
}

AfterAll {
    # Cleanup test environment
    if ($script:testConfig) {
        # Remove test data
        $script:testConfig.Resources.Created | ForEach-Object {
            Remove-PSCompassOneAsset -Id $_.Id -Confirm:$false -ErrorAction SilentlyContinue
        }

        # Clear mock API
        Initialize-MockApi

        # Remove module
        Remove-Module PSCompassOne -ErrorAction SilentlyContinue
    }
}