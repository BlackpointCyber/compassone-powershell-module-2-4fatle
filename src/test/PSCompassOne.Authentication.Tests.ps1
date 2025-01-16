#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

BeforeAll {
    # Import test helpers and mocks
    . (Join-Path $PSScriptRoot 'helpers/TestHelpers.ps1')
    . (Join-Path $PSScriptRoot 'mocks/MockSecretStore.ps1')

    # Initialize test environment
    $script:testEnvironment = Initialize-TestEnvironment -TestName 'Authentication' -LogLevel 'Verbose'
    
    # Initialize SecretStore mock with enhanced security validation
    $script:mockSecretStore = New-SecretStoreMock -Configuration @{
        SimulateErrors = $false
        MaxRetries = 3
        RetryDelayMs = 500
    }

    # Set up thread-safe mocking
    Mock-SecretStoreOperations -MockBehavior @{
        SimulateErrors = $false
        ErrorRate = 0.1
    }

    # Test credentials
    $script:testCredentials = @{
        ApiKey = 'test-api-key'
        ApiSecret = 'test-api-secret'
        SecurityContext = @{
            TenantId = 'test-tenant'
            Environment = 'test'
        }
    }
}

Describe 'PSCompassOne Authentication Tests' {
    Context 'API Key Authentication' {
        BeforeEach {
            # Reset SecretStore state before each test
            $script:MockSecretStore.Clear()
            $script:MockSecretStoreLocked = $true
        }

        It 'Should successfully store API credentials in SecretStore' {
            # Arrange
            $credentialName = 'PSCompassOne_ApiKey'
            
            # Act
            $result = Set-PSCompassOneCredential -ApiKey $testCredentials.ApiKey -ApiSecret $testCredentials.ApiSecret

            # Assert
            $result | Should -BeTrue
            Assert-SecretStoreCalls -CommandName 'Set-Secret' -ExpectedParameters @{
                Name = $credentialName
                Secret = $testCredentials.ApiKey
            } -Times 1
        }

        It 'Should retrieve stored API credentials' {
            # Arrange
            Set-PSCompassOneCredential -ApiKey $testCredentials.ApiKey -ApiSecret $testCredentials.ApiSecret

            # Act
            $credentials = Get-PSCompassOneCredential

            # Assert
            $credentials | Should -Not -BeNull
            $credentials.ApiKey | Should -Be $testCredentials.ApiKey
            $credentials.ApiSecret | Should -Be $testCredentials.ApiSecret
        }

        It 'Should handle invalid API credentials' {
            # Act & Assert
            {
                Set-PSCompassOneCredential -ApiKey '' -ApiSecret $testCredentials.ApiSecret
            } | Should -Throw -ErrorId 'InvalidApiCredentials'
        }

        It 'Should securely remove API credentials' {
            # Arrange
            Set-PSCompassOneCredential -ApiKey $testCredentials.ApiKey -ApiSecret $testCredentials.ApiSecret

            # Act
            $result = Remove-PSCompassOneCredential

            # Assert
            $result | Should -BeTrue
            { Get-PSCompassOneCredential } | Should -Throw -ErrorId 'CredentialsNotFound'
        }
    }

    Context 'Token Management' {
        BeforeAll {
            # Set up token management mocks
            Mock Get-PSCompassOneToken {
                return @{
                    AccessToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
                    ExpiresAt = (Get-Date).AddHours(1)
                    TokenType = "Bearer"
                }
            }
        }

        It 'Should generate valid authentication token' {
            # Act
            $token = New-PSCompassOneToken -Credential $testCredentials

            # Assert
            $token | Should -Not -BeNull
            $token.AccessToken | Should -Not -BeNullOrEmpty
            $token.ExpiresAt | Should -BeGreaterThan (Get-Date)
        }

        It 'Should refresh expired token automatically' {
            # Arrange
            $expiredToken = @{
                AccessToken = "expired_token"
                ExpiresAt = (Get-Date).AddHours(-1)
                TokenType = "Bearer"
            }

            # Act
            $newToken = Update-PSCompassOneToken -Token $expiredToken

            # Assert
            $newToken | Should -Not -BeNull
            $newToken.AccessToken | Should -Not -Be $expiredToken.AccessToken
            $newToken.ExpiresAt | Should -BeGreaterThan (Get-Date)
        }

        It 'Should handle token refresh failures gracefully' {
            # Arrange
            Mock Get-PSCompassOneToken { throw 'Token refresh failed' }

            # Act & Assert
            { Update-PSCompassOneToken -Token @{ AccessToken = 'invalid' } } | 
                Should -Throw -ErrorId 'TokenRefreshError'
        }
    }

    Context 'Cross-Platform Authentication' {
        BeforeAll {
            # Platform-specific configurations
            $platformConfigs = @{
                Windows = @{
                    SecretStorePath = "$env:LOCALAPPDATA\PSCompassOne"
                    UseWindowsCredentialStore = $true
                }
                Linux = @{
                    SecretStorePath = "$env:HOME/.pscompassone"
                    UseWindowsCredentialStore = $false
                }
                MacOS = @{
                    SecretStorePath = "$env:HOME/Library/Application Support/PSCompassOne"
                    UseWindowsCredentialStore = $false
                }
            }
        }

        It 'Should handle authentication on <_> platform' -TestCases @('Windows', 'Linux', 'MacOS') {
            param($Platform)

            # Arrange
            $config = $platformConfigs[$Platform]
            Mock Get-PSCompassOnePlatform { return $Platform }

            # Act
            $result = Initialize-PSCompassOneAuth -Configuration $config

            # Assert
            $result | Should -BeTrue
            $result.SecretStorePath | Should -Be $config.SecretStorePath
        }
    }

    Context 'Security Validation' {
        It 'Should enforce minimum security requirements' {
            # Act & Assert
            { Set-PSCompassOneCredential -ApiKey 'weak' -ApiSecret 'weak' } |
                Should -Throw -ErrorId 'SecurityValidationFailed'
        }

        It 'Should detect and prevent credential exposure' {
            # Arrange
            $exposedCredential = @{
                ApiKey = 'exposed_key'
                ApiSecret = 'exposed_secret'
            }

            # Act & Assert
            { Set-PSCompassOneCredential @exposedCredential } |
                Should -Throw -ErrorId 'CredentialExposureDetected'
        }

        It 'Should implement rate limiting for authentication attempts' {
            # Arrange
            $attempts = 1..6 | ForEach-Object {
                try {
                    Set-PSCompassOneCredential -ApiKey "test$_" -ApiSecret "test$_"
                }
                catch {
                    $_.Exception
                }
            }

            # Assert
            $attempts[-1].FullyQualifiedErrorId | Should -Be 'RateLimitExceeded'
        }
    }
}

AfterAll {
    # Clean up test environment
    if ($script:testEnvironment) {
        # Secure cleanup of test credentials
        $script:MockSecretStore.Clear()
        
        # Remove test data
        Remove-Item -Path $script:testEnvironment.TestDataPath -Recurse -Force -ErrorAction SilentlyContinue
        
        # Clear test environment
        $script:testEnvironment = $null
    }
}