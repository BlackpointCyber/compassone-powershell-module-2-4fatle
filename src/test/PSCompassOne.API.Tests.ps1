#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

# Import required test helpers and mocks
. "$PSScriptRoot/helpers/TestHelpers.ps1"
. "$PSScriptRoot/mocks/MockAPI.ps1"

BeforeAll {
    # Initialize test environment and mocks
    $script:testEnv = Initialize-TestEnvironment -TestName 'API.Tests' -UseMockData
    Initialize-MockApi

    # Performance thresholds
    $script:performanceThresholds = @{
        ResponseTime = 2000  # milliseconds
        MemoryUsage = 512MB # maximum memory usage
        CpuThreshold = 75   # percentage
    }

    # Platform-specific configurations
    $script:platformConfig = @{
        Windows = @{
            PathSeparator = '\'
            CertStore = 'Cert:\LocalMachine\My'
            SecurityProtocol = 'Tls12'
        }
        Linux = @{
            PathSeparator = '/'
            CertPath = '/etc/ssl/certs'
            SecurityProtocol = 'Tls12,Tls13'
        }
        MacOS = @{
            PathSeparator = '/'
            CertPath = '/etc/ssl/certs'
            SecurityProtocol = 'Tls12,Tls13'
        }
    }
}

Describe 'PSCompassOne API Client Tests' {
    Context 'Authentication' {
        It 'Should authenticate with valid credentials' {
            # Arrange
            $apiKey = 'valid-api-key'
            
            # Act
            $result = Get-PSCompassOneToken -ApiKey $apiKey
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Token | Should -Not -BeNullOrEmpty
            $result.ExpiresAt | Should -BeOfType [DateTime]
            $result.TokenType | Should -Be 'Bearer'
        }

        It 'Should handle invalid credentials' {
            # Arrange
            $apiKey = 'invalid-api-key'
            
            # Act & Assert
            { Get-PSCompassOneToken -ApiKey $apiKey } | Should -Throw -ErrorId 'AuthenticationError'
        }

        It 'Should refresh expired tokens' {
            # Arrange
            $expiredToken = 'expired-token'
            
            # Act
            $result = Update-PSCompassOneToken -Token $expiredToken
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Token | Should -Not -Be $expiredToken
            $result.ExpiresAt | Should -BeGreaterThan (Get-Date)
        }

        It 'Should validate SSL/TLS requirements' {
            # Arrange
            $currentProtocol = [System.Net.ServicePointManager]::SecurityProtocol
            
            # Act
            $result = Test-PSCompassOneConnection
            
            # Assert
            $result.SecurityProtocol | Should -Match 'Tls12|Tls13'
            $result.CertificateValidation | Should -BeTrue
        }
    }

    Context 'Request Processing' {
        It 'Should handle GET requests correctly' {
            # Arrange
            $endpoint = '/api/v1/assets'
            
            # Act
            $result = Invoke-PSCompassOneRequest -Method 'GET' -Endpoint $endpoint
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.StatusCode | Should -Be 200
            $result.Headers['Content-Type'] | Should -Be 'application/json'
        }

        It 'Should handle POST requests correctly' {
            # Arrange
            $endpoint = '/api/v1/assets'
            $body = @{
                name = 'TestAsset'
                type = 'DEVICE'
            }
            
            # Act
            $result = Invoke-PSCompassOneRequest -Method 'POST' -Endpoint $endpoint -Body $body
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.StatusCode | Should -Be 201
            $result.Content.id | Should -Not -BeNullOrEmpty
        }

        It 'Should handle request compression' {
            # Arrange
            $largePayload = @{
                data = 'x' * 1MB
            }
            
            # Act
            $result = Invoke-PSCompassOneRequest -Method 'POST' -Endpoint '/api/v1/assets' -Body $largePayload -UseCompression
            
            # Assert
            $result.Headers['Content-Encoding'] | Should -Be 'gzip'
            $result.StatusCode | Should -Be 201
        }

        It 'Should validate request payloads' {
            # Arrange
            $invalidPayload = @{
                invalid = $null
            }
            
            # Act & Assert
            { Invoke-PSCompassOneRequest -Method 'POST' -Endpoint '/api/v1/assets' -Body $invalidPayload } |
                Should -Throw -ErrorId 'ValidationError'
        }
    }

    Context 'Platform Compatibility' {
        It 'Should handle platform-specific paths' {
            # Arrange
            $platform = $PSVersionTable.Platform
            $config = $script:platformConfig[$platform]
            
            # Act
            $result = Test-PSCompassOnePlatformSupport
            
            # Assert
            $result.PathSeparator | Should -Be $config.PathSeparator
            $result.SecurityProtocol | Should -Be $config.SecurityProtocol
        }

        It 'Should handle platform-specific certificates' {
            # Arrange
            $platform = $PSVersionTable.Platform
            $config = $script:platformConfig[$platform]
            
            # Act
            $result = Test-PSCompassOneCertificates
            
            # Assert
            $result.CertificateStore | Should -Not -BeNullOrEmpty
            $result.CertificateValidation | Should -BeTrue
        }

        It 'Should validate cross-platform encodings' {
            # Arrange
            $testString = "Test`nString`r`nWith`tSpecial©Chars"
            
            # Act
            $result = Test-PSCompassOneEncoding -InputString $testString
            
            # Assert
            $result.Encoding | Should -Be 'UTF8'
            $result.PreservesSpecialChars | Should -BeTrue
        }
    }

    Context 'Performance Monitoring' {
        It 'Should meet response time thresholds' {
            # Arrange
            $endpoint = '/api/v1/assets'
            $threshold = $script:performanceThresholds.ResponseTime
            
            # Act
            $timer = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Invoke-PSCompassOneRequest -Method 'GET' -Endpoint $endpoint
            $timer.Stop()
            
            # Assert
            $timer.ElapsedMilliseconds | Should -BeLessOrEqual $threshold
            $result.StatusCode | Should -Be 200
        }

        It 'Should handle concurrent requests' {
            # Arrange
            $requests = 1..5 | ForEach-Object {
                @{
                    Method = 'GET'
                    Endpoint = '/api/v1/assets'
                }
            }
            
            # Act
            $results = $requests | ForEach-Object -ThrottleLimit 3 -Parallel {
                Invoke-PSCompassOneRequest @$_
            }
            
            # Assert
            $results.Count | Should -Be 5
            $results | ForEach-Object { $_.StatusCode | Should -Be 200 }
        }

        It 'Should manage memory usage' {
            # Arrange
            $threshold = $script:performanceThresholds.MemoryUsage
            
            # Act
            $memoryBefore = [System.GC]::GetTotalMemory($true)
            1..100 | ForEach-Object {
                Invoke-PSCompassOneRequest -Method 'GET' -Endpoint '/api/v1/assets'
            }
            $memoryAfter = [System.GC]::GetTotalMemory($true)
            
            # Assert
            ($memoryAfter - $memoryBefore) | Should -BeLessOrEqual $threshold
        }

        It 'Should implement connection pooling' {
            # Arrange
            $connectionLimit = 10
            
            # Act
            $result = Test-PSCompassOneConnections -ConnectionLimit $connectionLimit
            
            # Assert
            $result.ActiveConnections | Should -BeLessOrEqual $connectionLimit
            $result.ConnectionPooling | Should -BeTrue
        }
    }

    Context 'Error Handling' {
        It 'Should handle rate limiting' {
            # Arrange
            $requests = 1..1001  # Exceed rate limit of 1000/hour
            
            # Act & Assert
            { $requests | ForEach-Object { 
                Invoke-PSCompassOneRequest -Method 'GET' -Endpoint '/api/v1/assets'
            } } | Should -Throw -ErrorId 'RateLimitExceeded'
        }

        It 'Should handle network failures' {
            # Arrange
            Mock Invoke-WebRequest { throw [System.Net.WebException]::new() }
            
            # Act & Assert
            { Invoke-PSCompassOneRequest -Method 'GET' -Endpoint '/api/v1/assets' } |
                Should -Throw -ErrorId 'NetworkError'
        }

        It 'Should handle API errors' {
            # Arrange
            $invalidEndpoint = '/api/v1/invalid'
            
            # Act & Assert
            { Invoke-PSCompassOneRequest -Method 'GET' -Endpoint $invalidEndpoint } |
                Should -Throw -ErrorId 'ApiError'
        }

        It 'Should implement retry logic' {
            # Arrange
            $endpoint = '/api/v1/assets'
            Mock Invoke-WebRequest { throw [System.Net.WebException]::new() } -Count 2
            
            # Act
            $result = Invoke-PSCompassOneRequest -Method 'GET' -Endpoint $endpoint -MaxRetries 3
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.StatusCode | Should -Be 200
        }
    }
}

AfterAll {
    # Cleanup test environment
    if ($script:testEnv) {
        Remove-Item -Path $script:testEnv.TestDataPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}