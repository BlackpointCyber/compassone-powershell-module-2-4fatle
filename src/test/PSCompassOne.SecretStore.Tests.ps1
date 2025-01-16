#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }, 
             @{ ModuleName='Microsoft.PowerShell.SecretStore'; ModuleVersion='1.0.0' }

using namespace System.Collections.Concurrent
using namespace System.Security

BeforeAll {
    # Import test helpers and mocks
    . (Join-Path $PSScriptRoot 'helpers/TestHelpers.ps1')
    . (Join-Path $PSScriptRoot 'mocks/MockSecretStore.ps1')

    # Initialize thread-safe test environment
    $script:TestState = [ConcurrentDictionary[string,object]]::new()
    $script:TestSecrets = [ConcurrentDictionary[string,SecureString]]::new()
    
    # Platform-specific configurations
    $script:PlatformConfig = @{
        Windows = @{
            SecretStorePath = "$env:LOCALAPPDATA\PSCompassOne\SecretStore"
            DefaultPassword = ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force
        }
        Linux = @{
            SecretStorePath = "$env:HOME/.pscompassone/secretstore"
            DefaultPassword = ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force
        }
        MacOS = @{
            SecretStorePath = "$env:HOME/Library/Application Support/PSCompassOne/SecretStore"
            DefaultPassword = ConvertTo-SecureString 'TestPass123!' -AsPlainText -Force
        }
    }
}

Describe 'PSCompassOne SecretStore Integration Tests' {
    BeforeAll {
        # Initialize test environment with platform detection
        $platform = switch ($true) {
            $IsWindows { 'Windows' }
            $IsLinux { 'Linux' }
            $IsMacOS { 'MacOS' }
            default { 'Windows' }
        }
        
        $script:TestEnv = Initialize-TestEnvironment -TestName 'SecretStore' -EnableParallel
        $script:MockStore = New-SecretStoreMock -Configuration @{
            SimulateErrors = $false
            PlatformPath = $PlatformConfig[$platform].SecretStorePath
        }
        
        # Set up SecretStore mocks
        Mock-SecretStoreOperations -MockBehavior @{
            SimulateErrors = $false
            ErrorRate = 0.1
        }
    }

    Context 'SecretStore Initialization' {
        It 'Should initialize SecretStore with correct platform path' {
            # Arrange
            $platform = if ($IsWindows) { 'Windows' } elseif ($IsLinux) { 'Linux' } else { 'MacOS' }
            $expectedPath = $PlatformConfig[$platform].SecretStorePath
            
            # Act
            $result = Initialize-PSCompassOneSecretStore -Path $expectedPath
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Path | Should -Be $expectedPath
            Assert-SecretStoreCalls -CommandName 'Unlock-SecretStore' -Times 1 -ExpectedParameters @{
                Password = $PlatformConfig[$platform].DefaultPassword
            }
        }

        It 'Should handle SecretStore initialization failures gracefully' {
            # Arrange
            Mock Unlock-SecretStore { throw 'Simulated initialization error' }
            
            # Act & Assert
            { Initialize-PSCompassOneSecretStore } | Should -Throw -ExpectedMessage 'Failed to initialize SecretStore*'
        }
    }

    Context 'Credential Management' {
        BeforeEach {
            # Set up test credentials
            $script:TestCredential = [PSCredential]::new(
                'test@example.com',
                (ConvertTo-SecureString 'TestApiKey123!' -AsPlainText -Force)
            )
        }

        It 'Should store API credentials securely' {
            # Act
            $result = Set-PSCompassOneCredential -Credential $TestCredential
            
            # Assert
            $result | Should -BeTrue
            Assert-SecretStoreCalls -CommandName 'Set-Secret' -Times 1 -ExpectedParameters @{
                Name = 'PSCompassOne_ApiCredential'
                Secret = $TestCredential
            }
        }

        It 'Should retrieve stored credentials successfully' {
            # Arrange
            Set-PSCompassOneCredential -Credential $TestCredential
            
            # Act
            $retrievedCred = Get-PSCompassOneCredential
            
            # Assert
            $retrievedCred | Should -Not -BeNullOrEmpty
            $retrievedCred.UserName | Should -Be $TestCredential.UserName
            $retrievedCred.GetNetworkCredential().Password | Should -Be $TestCredential.GetNetworkCredential().Password
        }

        It 'Should handle concurrent credential operations thread-safely' {
            # Arrange
            $operations = 1..5 | ForEach-Object {
                @{
                    Credential = [PSCredential]::new(
                        "test$_@example.com",
                        (ConvertTo-SecureString "TestApiKey$_!" -AsPlainText -Force)
                    )
                }
            }
            
            # Act & Assert
            $results = $operations | ForEach-Object -ThrottleLimit 5 -Parallel {
                Set-PSCompassOneCredential -Credential $_.Credential
            }
            
            $results | Should -Not -Contain $false
        }
    }

    Context 'Token Management' {
        BeforeEach {
            $script:TestToken = @{
                AccessToken = 'test-token-123'
                ExpiresAt = (Get-Date).AddHours(1)
            }
        }

        It 'Should store and retrieve authentication tokens securely' {
            # Act
            $stored = Set-PSCompassOneToken -Token $TestToken
            $retrieved = Get-PSCompassOneToken
            
            # Assert
            $stored | Should -BeTrue
            $retrieved.AccessToken | Should -Be $TestToken.AccessToken
            $retrieved.ExpiresAt | Should -Be $TestToken.ExpiresAt
        }

        It 'Should handle token expiration correctly' {
            # Arrange
            $expiredToken = @{
                AccessToken = 'expired-token-123'
                ExpiresAt = (Get-Date).AddHours(-1)
            }
            Set-PSCompassOneToken -Token $expiredToken
            
            # Act & Assert
            { Get-PSCompassOneToken } | Should -Throw -ExpectedMessage '*Token has expired*'
        }

        It 'Should refresh tokens automatically when near expiration' {
            # Arrange
            $nearExpiryToken = @{
                AccessToken = 'near-expiry-token-123'
                ExpiresAt = (Get-Date).AddMinutes(5)
            }
            Set-PSCompassOneToken -Token $nearExpiryToken
            
            # Act
            $result = Get-PSCompassOneToken -AutoRefresh
            
            # Assert
            $result.AccessToken | Should -Not -Be $nearExpiryToken.AccessToken
            $result.ExpiresAt | Should -BeGreaterThan $nearExpiryToken.ExpiresAt
        }
    }

    Context 'Cross-Platform Compatibility' {
        It 'Should handle platform-specific paths correctly' {
            # Arrange
            $platforms = @('Windows', 'Linux', 'MacOS')
            
            # Act & Assert
            foreach ($platform in $platforms) {
                $config = $PlatformConfig[$platform]
                $result = Initialize-PSCompassOneSecretStore -Path $config.SecretStorePath
                $result.Path | Should -Be $config.SecretStorePath
            }
        }

        It 'Should maintain consistent encryption across platforms' {
            # Arrange
            $testSecret = @{
                Name = 'CrossPlatformSecret'
                Value = 'SecretValue123!'
            }
            
            # Act
            Set-Secret -Name $testSecret.Name -SecureString (ConvertTo-SecureString $testSecret.Value -AsPlainText -Force)
            $retrieved = Get-Secret -Name $testSecret.Name
            
            # Assert
            $retrieved | Should -Not -BeNullOrEmpty
            [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($retrieved)
            ) | Should -Be $testSecret.Value
        }
    }

    Context 'Error Handling and Recovery' {
        It 'Should handle SecretStore locked state correctly' {
            # Arrange
            Lock-SecretStore
            
            # Act & Assert
            { Get-PSCompassOneCredential } | Should -Throw -ExpectedMessage '*SecretStore is locked*'
            { Unlock-SecretStore -Password $PlatformConfig[$platform].DefaultPassword } | Should -Not -Throw
        }

        It 'Should retry failed operations with exponential backoff' {
            # Arrange
            Mock Set-Secret { throw 'Transient error' } -Times 2
            Mock Set-Secret { $true } -Times 1
            
            # Act
            $result = Set-PSCompassOneCredential -Credential $TestCredential -MaxRetries 3
            
            # Assert
            $result | Should -BeTrue
            Should -Invoke Set-Secret -Times 3 -Exactly
        }

        It 'Should maintain data integrity during concurrent access' {
            # Arrange
            $concurrentOps = 1..10 | ForEach-Object {
                @{
                    Operation = if ($_ % 2 -eq 0) { 'Read' } else { 'Write' }
                    Data = if ($_ % 2 -eq 0) { $null } else {
                        [PSCredential]::new(
                            "concurrent$_@example.com",
                            (ConvertTo-SecureString "ConcurrentKey$_!" -AsPlainText -Force)
                        )
                    }
                }
            }
            
            # Act & Assert
            $results = $concurrentOps | ForEach-Object -ThrottleLimit 10 -Parallel {
                if ($_.Operation -eq 'Write') {
                    Set-PSCompassOneCredential -Credential $_.Data
                } else {
                    Get-PSCompassOneCredential
                }
            }
            
            $results | Where-Object { $_ -is [bool] } | Should -Not -Contain $false
            $results | Where-Object { $_ -is [PSCredential] } | Should -Not -BeNullOrEmpty
        }
    }
}

AfterAll {
    # Clean up test environment
    if ($script:TestEnv) {
        Reset-TestEnvironment -TestEnvironment $script:TestEnv
    }
    
    # Reset SecretStore to initial state
    Lock-SecretStore
    $script:TestState.Clear()
    $script:TestSecrets.Clear()
}