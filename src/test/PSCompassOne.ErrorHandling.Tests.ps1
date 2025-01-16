#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

BeforeAll {
    # Import test helpers and configuration
    . "$PSScriptRoot/helpers/TestHelpers.ps1"
    . "$PSScriptRoot/mocks/MockAPI.ps1"
    $TestConfig = Import-PowerShellDataFile -Path "$PSScriptRoot/config/test-config.psd1"

    # Initialize test environment
    $testEnv = Initialize-TestEnvironment -TestName 'ErrorHandling' -UseMockData
    Initialize-MockApi
}

Describe 'PSCompassOne Error Handling' {
    Context 'Parameter Validation Errors' {
        It 'Should handle missing required parameters' {
            # Test asset creation without required parameters
            $command = { New-PSCompassOneAsset }
            $command | Should -Throw -ErrorId 'ParameterBindingValidationException'

            # Validate error details
            $error[0] | Should -Not -BeNullOrEmpty
            $error[0].Exception.Message | Should -Match 'Parameter .* is mandatory'
            $error[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
        }

        It 'Should handle invalid parameter types' {
            # Test with wrong parameter type
            $command = { Get-PSCompassOneAsset -Id @{invalid='type'} }
            $command | Should -Throw -ErrorId 'ParameterBindingException'

            # Validate error formatting
            $error[0].Exception.Message | Should -Match 'Cannot process argument transformation'
        }

        It 'Should handle invalid parameter values' {
            # Test with invalid value ranges
            $command = { Get-PSCompassOneAsset -PageSize 0 }
            $command | Should -Throw -ErrorId 'ValidationException'
            
            $error[0].Exception.Message | Should -Match 'PageSize must be greater than 0'
        }
    }

    Context 'API Errors' {
        BeforeAll {
            # Mock API errors
            Mock Invoke-RestMethod {
                throw [System.Net.WebException]::new(
                    'The remote server returned an error: (401) Unauthorized.',
                    $null,
                    [System.Net.WebExceptionStatus]::ProtocolError,
                    [PSCustomObject]@{
                        StatusCode = 401
                        StatusDescription = 'Unauthorized'
                    }
                )
            } -ParameterFilter { $Uri -match '/auth' }
        }

        It 'Should handle authentication errors' {
            $command = { Connect-PSCompassOne -ApiKey 'invalid_key' }
            $command | Should -Throw -ErrorId 'AuthenticationError'
            
            # Verify secure error handling
            $error[0].Exception.Message | Should -Not -Match 'invalid_key'
            $error[0].Exception.Message | Should -Match 'Authentication failed'
        }

        It 'Should handle rate limiting' {
            Mock Invoke-RestMethod {
                throw [System.Net.WebException]::new(
                    'Too Many Requests',
                    $null,
                    [System.Net.WebExceptionStatus]::ProtocolError,
                    [PSCustomObject]@{
                        StatusCode = 429
                        StatusDescription = 'Too Many Requests'
                    }
                )
            }

            $command = { Get-PSCompassOneAsset -Id 'test123' }
            $command | Should -Throw -ErrorId 'RateLimitExceeded'
            
            # Verify retry information
            $error[0].Exception.Message | Should -Match 'Rate limit exceeded'
            $error[0].Exception.Message | Should -Match 'Please retry'
        }

        It 'Should handle server errors' {
            Mock Invoke-RestMethod {
                throw [System.Net.WebException]::new(
                    'Internal Server Error',
                    $null,
                    [System.Net.WebExceptionStatus]::ProtocolError,
                    [PSCustomObject]@{
                        StatusCode = 500
                        StatusDescription = 'Internal Server Error'
                    }
                )
            }

            $command = { Get-PSCompassOneAsset -Id 'test123' }
            $command | Should -Throw -ErrorId 'ServerError'
            
            # Verify generic error message
            $error[0].Exception.Message | Should -Match 'An unexpected error occurred'
        }
    }

    Context 'Pipeline Errors' {
        It 'Should handle pipeline input errors' {
            $invalidInput = @(
                [PSCustomObject]@{ Id = 'invalid1'; Type = 'Invalid' },
                [PSCustomObject]@{ Id = 'invalid2'; Type = 'Invalid' }
            )

            $command = { $invalidInput | Set-PSCompassOneAsset }
            $command | Should -Throw -ErrorId 'PipelineValidationError'

            # Verify pipeline error details
            $error[0].Exception.Message | Should -Match 'Pipeline input validation failed'
        }

        It 'Should handle partial pipeline failures' {
            $mixedInput = @(
                [PSCustomObject]@{ Id = 'valid1'; Type = 'DEVICE' },
                [PSCustomObject]@{ Id = 'invalid1'; Type = 'Invalid' },
                [PSCustomObject]@{ Id = 'valid2'; Type = 'DEVICE' }
            )

            $result = $mixedInput | Set-PSCompassOneAsset -ErrorAction SilentlyContinue
            $error.Count | Should -BeGreaterThan 0
            $result.Count | Should -Be 2
        }
    }

    Context 'Error Recovery' {
        It 'Should implement retry logic for transient errors' {
            $retryCount = 0
            Mock Invoke-RestMethod {
                $retryCount++
                if ($retryCount -lt 3) {
                    throw [System.Net.WebException]::new(
                        'Service Unavailable',
                        $null,
                        [System.Net.WebExceptionStatus]::ProtocolError,
                        [PSCustomObject]@{
                            StatusCode = 503
                            StatusDescription = 'Service Unavailable'
                        }
                    )
                }
                return @{ success = $true }
            }

            $result = Get-PSCompassOneAsset -Id 'test123'
            $retryCount | Should -Be 3
            $result.success | Should -Be $true
        }

        It 'Should handle cleanup after critical errors' {
            Mock Invoke-RestMethod {
                throw [System.OutOfMemoryException]::new('Critical error')
            }

            $command = { Get-PSCompassOneAsset -Id 'test123' }
            $command | Should -Throw -ErrorId 'CriticalError'

            # Verify resource cleanup
            $error[0].Exception.Message | Should -Match 'Critical error occurred'
        }
    }

    Context 'Security Error Handling' {
        It 'Should securely handle credential errors' {
            $command = { Connect-PSCompassOne -ApiKey 'sensitive_key_12345' }
            $command | Should -Throw -ErrorId 'AuthenticationError'

            # Verify sensitive data is not exposed
            $error[0].Exception.Message | Should -Not -Match 'sensitive_key_12345'
        }

        It 'Should handle authorization errors securely' {
            Mock Invoke-RestMethod {
                throw [System.UnauthorizedAccessException]::new(
                    'Access denied to resource'
                )
            }

            $command = { Get-PSCompassOneAsset -Id 'restricted123' }
            $command | Should -Throw -ErrorId 'AuthorizationError'

            # Verify secure error message
            $error[0].Exception.Message | Should -Match 'Access denied'
            $error[0].Exception.Message | Should -Not -Match 'restricted123'
        }
    }
}

AfterAll {
    # Clean up test environment
    Reset-TestEnvironment
}