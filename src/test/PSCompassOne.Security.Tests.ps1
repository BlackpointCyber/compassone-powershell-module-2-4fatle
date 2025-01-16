#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }, @{ ModuleName='Microsoft.PowerShell.SecretStore'; ModuleVersion='1.0.0' }

BeforeAll {
    # Import test configuration and helpers
    $TestConfig = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'config/test-config.psd1')
    . (Join-Path $PSScriptRoot 'helpers/TestHelpers.ps1')
    . (Join-Path $PSScriptRoot 'mocks/MockSecretStore.ps1')

    # Initialize test environment with security settings
    $script:TestEnvironment = Initialize-TestEnvironment -TestName 'SecurityTests' -UseMockData
    $script:SecretStoreMock = New-SecretStoreMock -Configuration @{
        SimulateErrors = $false
        MaxRetries = 3
        RetryDelayMs = 500
    }

    # Set up SecretStore mocks
    Mock-SecretStoreOperations -MockBehavior @{
        SimulateErrors = $false
        ErrorRate = 0.1
    }
}

Describe 'PSCompassOne Security Tests' {
    Context 'Authentication and Authorization' {
        BeforeEach {
            # Reset SecretStore state before each test
            $script:SecretStoreMock.Store.Clear()
            $script:SecretStoreMock.IsLocked = $true
        }

        It 'Should securely store API credentials in SecretStore' {
            # Arrange
            $apiKey = 'test-api-key-123'
            $encryptedApiKey = ConvertTo-SecureString $apiKey -AsPlainText -Force

            # Act
            Set-Secret -Name 'PSCompassOne_ApiKey' -Secret $encryptedApiKey

            # Assert
            Assert-SecretStoreCalls -CommandName 'Set-Secret' -ExpectedParameters @{
                Name = 'PSCompassOne_ApiKey'
                Secret = $encryptedApiKey
            } -Times 1

            $storedSecret = Get-Secret -Name 'PSCompassOne_ApiKey'
            $storedSecret | Should -Not -BeNullOrEmpty
            $storedSecret.GetType().Name | Should -Be 'SecureString'
        }

        It 'Should enforce TLS 1.2 or higher for API communication' {
            # Arrange
            $originalTls = [Net.ServicePointManager]::SecurityProtocol

            # Act
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $response = Invoke-RestMethod -Uri $TestEnvironment.ApiEndpoint -Method Get

                # Assert
                [Net.ServicePointManager]::SecurityProtocol | Should -Be ([Net.SecurityProtocolType]::Tls12)
                $response | Should -Not -BeNullOrEmpty
            }
            finally {
                [Net.ServicePointManager]::SecurityProtocol = $originalTls
            }
        }

        It 'Should validate API token expiration and refresh when needed' {
            # Arrange
            $expiredToken = @{
                Token = 'expired-token'
                ExpiresAt = (Get-Date).AddHours(-1)
            }
            Set-Secret -Name 'PSCompassOne_Token' -Secret ($expiredToken | ConvertTo-SecureString -AsPlainText -Force)

            # Act & Assert
            { Get-PSCompassOneToken } | Should -Not -Throw
            Assert-SecretStoreCalls -CommandName 'Set-Secret' -ExpectedParameters @{
                Name = 'PSCompassOne_Token'
            } -Times 2  # Initial set and refresh
        }
    }

    Context 'Data Security' {
        It 'Should encrypt sensitive data before storage' {
            # Arrange
            $sensitiveData = @{
                ApiKey = 'secret-key-123'
                Password = 'secure-password'
            }

            # Act
            $encryptedData = Protect-PSCompassOneData -Data $sensitiveData

            # Assert
            $encryptedData | Should -Not -BeNullOrEmpty
            $encryptedData | Should -Not -BeLike "*$($sensitiveData.ApiKey)*"
            $encryptedData | Should -Not -BeLike "*$($sensitiveData.Password)*"
        }

        It 'Should securely handle credentials in memory' {
            # Arrange
            $credential = [PSCredential]::new(
                'testuser',
                (ConvertTo-SecureString 'testpass' -AsPlainText -Force)
            )

            # Act
            $result = Test-PSCompassOneCredential -Credential $credential

            # Assert
            $result | Should -BeTrue
            Get-Variable -Name 'credential' -ValueOnly | 
                Select-Object -ExpandProperty Password | 
                Should -BeOfType [SecureString]
        }

        It 'Should properly sanitize error messages' {
            # Arrange
            $sensitiveData = @{
                ApiKey = 'secret-key-456'
                Token = 'bearer-token-789'
            }

            # Act
            $error = { 
                throw [System.Security.SecurityException]::new(
                    "Error processing request with key: $($sensitiveData.ApiKey)"
                )
            }

            # Assert
            $error | Should -Throw -ExceptionType ([System.Security.SecurityException])
            $error.Exception.Message | Should -Not -BeLike "*$($sensitiveData.ApiKey)*"
        }
    }

    Context 'Security Protocols' {
        It 'Should enforce certificate validation' {
            # Arrange
            $originalCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback

            # Act & Assert
            {
                [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $null
                Connect-PSCompassOne -ApiEndpoint 'https://invalid.example.com'
            } | Should -Throw -ExceptionType ([System.Security.Authentication.AuthenticationException])

            # Cleanup
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $originalCallback
        }

        It 'Should implement rate limiting with exponential backoff' {
            # Arrange
            $maxAttempts = 3
            $attempts = 0
            $startTime = Get-Date

            # Act
            { 
                while ($attempts -lt $maxAttempts) {
                    $attempts++
                    Invoke-PSCompassOneApi -Method Get -Endpoint '/test'
                }
            } | Should -Throw -ExceptionType ([System.Net.WebException])

            # Assert
            $duration = (Get-Date) - $startTime
            $duration.TotalSeconds | Should -BeGreaterThan 3  # Minimum backoff time
        }

        It 'Should properly handle secure error responses' {
            # Arrange
            $errorResponse = @{
                StatusCode = 401
                Message = 'Unauthorized access'
                RequestId = 'test-request-123'
            }

            Mock Invoke-RestMethod {
                throw [System.Net.WebException]::new(
                    'The remote server returned an error: (401) Unauthorized.'
                )
            }

            # Act & Assert
            { 
                Invoke-PSCompassOneApi -Method Get -Endpoint '/secure/resource' 
            } | Should -Throw -ExceptionType ([System.Net.WebException])
        }
    }

    Context 'Cross-Platform Security' {
        It 'Should handle platform-specific credential storage' {
            # Arrange
            $isWindows = $PSVersionTable.PSVersion.Major -ge 6 -and $IsWindows
            $isUnix = $PSVersionTable.PSVersion.Major -ge 6 -and ($IsLinux -or $IsMacOS)

            # Act & Assert
            if ($isWindows) {
                Test-PSCompassOneCredentialStorage | Should -Be 'DPAPI'
            }
            elseif ($isUnix) {
                Test-PSCompassOneCredentialStorage | Should -Be 'LibSecret'
            }
            else {
                Test-PSCompassOneCredentialStorage | Should -Be 'AES'
            }
        }

        It 'Should enforce secure file permissions' {
            # Arrange
            $configPath = Join-Path $TestEnvironment.TestDataPath 'config.json'
            $secureContent = @{ test = 'data' } | ConvertTo-Json
            $secureContent | Set-Content -Path $configPath

            # Act
            $acl = Get-Acl -Path $configPath

            # Assert
            if ($IsWindows) {
                $acl.Access | Where-Object { $_.IdentityReference -notmatch 'SYSTEM|Administrators' } |
                    Should -BeNullOrEmpty
            }
            else {
                (Get-Item $configPath).Mode | Should -BeLike '*600'
            }
        }
    }

    Context 'Audit and Logging' {
        It 'Should securely log security events' {
            # Arrange
            $logPath = Join-Path $TestEnvironment.TestDataPath 'security.log'
            $sensitiveData = 'secret-value-123'

            # Act
            Write-PSCompassOneSecurityLog -Message "Test security event" -Data @{
                Event = 'SecurityTest'
                SensitiveValue = $sensitiveData
            }

            # Assert
            $logContent = Get-Content $logPath -Raw
            $logContent | Should -Not -BeNullOrEmpty
            $logContent | Should -Not -BeLike "*$sensitiveData*"
            $logContent | Should -BeLike "*SecurityTest*"
        }

        It 'Should track authentication attempts' {
            # Arrange
            $maxFailedAttempts = 3
            $attempts = 0

            # Act & Assert
            while ($attempts -lt $maxFailedAttempts) {
                { 
                    Connect-PSCompassOne -ApiKey 'invalid-key' 
                } | Should -Throw
                $attempts++
            }

            Get-PSCompassOneSecurityMetric -MetricName 'FailedAuthAttempts' |
                Should -Be $maxFailedAttempts
        }
    }
}

AfterAll {
    # Cleanup test environment
    if ($script:TestEnvironment) {
        Remove-Item -Path $script:TestEnvironment.TestDataPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Reset SecretStore mock
    $script:SecretStoreMock.Store.Clear()
}