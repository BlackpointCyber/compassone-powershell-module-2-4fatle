#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

# Import test configuration and helpers
$TestConfig = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'config/test-config.psd1')
. (Join-Path $PSScriptRoot 'helpers/TestHelpers.ps1')
. (Join-Path $PSScriptRoot 'mocks/MockAPI.ps1')

BeforeAll {
    # Initialize test environment
    $script:testEnvironment = Initialize-TestEnvironment -TestName 'PSCompassOneTests' -UseMockData
    
    # Import module under test
    Import-Module (Join-Path $PSScriptRoot '../PSCompassOne.psd1') -Force
    
    # Initialize API mocks
    Initialize-MockApi
}

AfterAll {
    # Cleanup test environment
    Remove-Module PSCompassOne -Force -ErrorAction SilentlyContinue
    
    # Clear test data
    if (Test-Path $script:testEnvironment.TestDataPath) {
        Remove-Item -Path $script:testEnvironment.TestDataPath -Recurse -Force
    }
}

Describe 'PSCompassOne Module Tests' {
    Context 'Module Loading' {
        It 'Should import the module successfully' {
            Get-Module PSCompassOne | Should -Not -BeNull
        }

        It 'Should have the correct module version' {
            (Get-Module PSCompassOne).Version | Should -Be '1.0.0'
        }

        It 'Should export all required cmdlets' {
            $expectedCmdlets = @(
                'Get-PSCompassOneAsset',
                'New-PSCompassOneAsset',
                'Set-PSCompassOneAsset',
                'Remove-PSCompassOneAsset',
                'Get-PSCompassOneFinding',
                'New-PSCompassOneFinding',
                'Connect-PSCompassOne'
            )

            $exportedCmdlets = Get-Command -Module PSCompassOne
            foreach ($cmdlet in $expectedCmdlets) {
                $exportedCmdlets.Name | Should -Contain $cmdlet
            }
        }
    }

    Context 'Configuration Management' {
        It 'Should load default configuration successfully' {
            InModuleScope PSCompassOne {
                $config = Get-PSCompassOneConfiguration
                $config | Should -Not -BeNull
                $config.ApiEndpoint | Should -Not -BeNullOrEmpty
                $config.ApiVersion | Should -Match '^\d+\.\d+\.\d+$'
            }
        }

        It 'Should override configuration with custom settings' {
            $customConfig = @{
                ApiEndpoint = 'https://custom.api.endpoint'
                ApiVersion = '2.0.0'
            }

            InModuleScope PSCompassOne {
                Set-PSCompassOneConfiguration -Configuration $customConfig
                $config = Get-PSCompassOneConfiguration
                $config.ApiEndpoint | Should -Be $customConfig.ApiEndpoint
                $config.ApiVersion | Should -Be $customConfig.ApiVersion
            }
        }

        It 'Should validate configuration settings' {
            $invalidConfig = @{
                ApiEndpoint = 'invalid-url'
            }

            { 
                InModuleScope PSCompassOne {
                    Set-PSCompassOneConfiguration -Configuration $invalidConfig
                }
            } | Should -Throw -ErrorId 'InvalidConfiguration'
        }
    }

    Context 'Authentication' {
        It 'Should connect successfully with valid credentials' {
            $credential = [PSCredential]::new(
                'test-api-key',
                ('mock-api-key' | ConvertTo-SecureString -AsPlainText -Force)
            )

            { Connect-PSCompassOne -Credential $credential } | Should -Not -Throw
            InModuleScope PSCompassOne {
                Get-PSCompassOneToken | Should -Not -BeNull
            }
        }

        It 'Should handle authentication failures gracefully' {
            $invalidCred = [PSCredential]::new(
                'invalid-key',
                ('invalid-key' | ConvertTo-SecureString -AsPlainText -Force)
            )

            { Connect-PSCompassOne -Credential $invalidCred } | 
                Should -Throw -ErrorId 'AuthenticationError'
        }

        It 'Should refresh expired tokens automatically' {
            InModuleScope PSCompassOne {
                # Force token expiration
                $Global:PSCompassOneState.Token.ExpiresAt = [DateTime]::UtcNow.AddMinutes(-5)
                
                # Attempt an API call
                { Get-PSCompassOneAsset } | Should -Not -Throw
                
                # Verify token was refreshed
                $Global:PSCompassOneState.Token.ExpiresAt | 
                    Should -BeGreaterThan ([DateTime]::UtcNow)
            }
        }
    }

    Context 'Asset Management' {
        BeforeAll {
            # Create test assets
            $script:testAsset = New-TestAsset -AssetType 'DEVICE' -Properties @{
                name = 'Test-Device-1'
                model = 'Test-Model'
                osName = 'Windows'
                osVersion = '10.0'
            }
        }

        It 'Should create new assets successfully' {
            $result = New-PSCompassOneAsset -InputObject $script:testAsset
            $result | Should -Not -BeNull
            $result.Id | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be $script:testAsset.name
        }

        It 'Should retrieve assets with filtering' {
            $assets = Get-PSCompassOneAsset -Filter @{ type = 'DEVICE' }
            $assets | Should -Not -BeNull
            $assets.Count | Should -BeGreaterThan 0
            $assets[0].Type | Should -Be 'DEVICE'
        }

        It 'Should update existing assets' {
            $updateProps = @{
                Id = $script:testAsset.Id
                Status = 'Inactive'
            }

            $result = Set-PSCompassOneAsset @updateProps
            $result | Should -Not -BeNull
            $result.Status | Should -Be 'Inactive'
        }

        It 'Should delete assets' {
            { Remove-PSCompassOneAsset -Id $script:testAsset.Id } | Should -Not -Throw
            { Get-PSCompassOneAsset -Id $script:testAsset.Id } | 
                Should -Throw -ErrorId 'AssetNotFound'
        }
    }

    Context 'Finding Management' {
        BeforeAll {
            $script:testFinding = @{
                Title = 'Test Finding'
                Severity = 'High'
                Description = 'Test finding description'
                AssetId = $script:testAsset.Id
            }
        }

        It 'Should create new findings' {
            $result = New-PSCompassOneFinding @script:testFinding
            $result | Should -Not -BeNull
            $result.Title | Should -Be $script:testFinding.Title
            $result.Severity | Should -Be $script:testFinding.Severity
        }

        It 'Should retrieve findings with filtering' {
            $findings = Get-PSCompassOneFinding -Filter @{ severity = 'High' }
            $findings | Should -Not -BeNull
            $findings.Count | Should -BeGreaterThan 0
            $findings[0].Severity | Should -Be 'High'
        }
    }

    Context 'Cross-Platform Compatibility' {
        It 'Should handle platform-specific paths correctly' {
            InModuleScope PSCompassOne {
                $path = Join-PSCompassOnePath 'test' 'path'
                if ($IsWindows) {
                    $path | Should -Match '\\'
                } else {
                    $path | Should -Match '/'
                }
            }
        }

        It 'Should use appropriate line endings' {
            InModuleScope PSCompassOne {
                $content = Get-PSCompassOneLogContent
                if ($IsWindows) {
                    $content | Should -Match "`r`n"
                } else {
                    $content | Should -Match "`n"
                }
            }
        }
    }

    Context 'Error Handling' {
        It 'Should handle network errors gracefully' {
            Mock Invoke-RestMethod { 
                throw [System.Net.WebException]::new(
                    'The remote name could not be resolved'
                )
            }

            { Get-PSCompassOneAsset } | 
                Should -Throw -ErrorId 'NetworkError'
        }

        It 'Should implement retry logic for transient errors' {
            $retryCount = 0
            Mock Invoke-RestMethod {
                $retryCount++
                if ($retryCount -lt 3) {
                    throw [System.Net.WebException]::new(
                        'The operation has timed out'
                    )
                }
                return @{ success = $true }
            }

            $result = Get-PSCompassOneAsset
            $result | Should -Not -BeNull
            $retryCount | Should -Be 3
        }

        It 'Should handle rate limiting' {
            Mock Invoke-RestMethod {
                throw [System.Net.WebException]::new(
                    'Too Many Requests'
                )
            }

            { Get-PSCompassOneAsset } | 
                Should -Throw -ErrorId 'RateLimitExceeded'
        }
    }

    Context 'Pipeline Support' {
        It 'Should support pipeline input for asset operations' {
            $assets = 1..3 | ForEach-Object {
                New-TestAsset -AssetType 'DEVICE' -Properties @{
                    name = "Pipeline-Test-$_"
                    model = 'Test-Model'
                }
            }

            $results = $assets | New-PSCompassOneAsset
            $results.Count | Should -Be 3
            $results | ForEach-Object {
                $_.Id | Should -Not -BeNullOrEmpty
            }
        }

        It 'Should support pipeline output' {
            $results = Get-PSCompassOneAsset | Select-Object -First 1 | Set-PSCompassOneAsset -Status 'Active'
            $results | Should -Not -BeNull
            $results.Status | Should -Be 'Active'
        }
    }
}