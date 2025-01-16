# PowerShell Data File
# Version: 1.0.0
# Purpose: Environment-specific test settings for PSCompassOne module test suite
# Required Modules:
# - PowerShellGet v2.2.5
# - Microsoft.PowerShell.Security (Built-in)

@{
    # Environment configuration hashtable containing all test environment settings
    EnvironmentSettings = @{
        # Basic environment identification
        Environment = 'Development'
        ApiBaseUrl = 'https://api.dev.compassone.local'
        ApiVersion = 'v1'

        # File system paths (platform-agnostic)
        TestDataPath = './data'
        LogPath = './logs'
        TempPath = './temp'
        MockDataPath = './mocks'
        CertificatePath = './certs'

        # Proxy configuration
        ProxyEnabled = $false
        ProxyServer = ''
        ProxyPort = 0
        ProxyCredential = $null

        # Security settings
        UseSSL = $true
        ValidateCertificates = $true
        CompressionEnabled = $true

        # Test execution settings
        DefaultTimeoutSeconds = 30
        MaxConcurrentTests = 4
        TestParallelization = $true

        # Resource constraints
        MaxMemoryMB = 1024
        MaxCPUCount = 2

        # Cloud environment settings
        CloudProvider = $null
        CloudRegion = $null
        ContainerRegistry = $null
        ContainerTag = 'latest'

        # Logging configuration
        LogLevel = 'Information'

        # Retry policy
        RetryAttempts = 3
        RetryDelaySeconds = 5
    }
}