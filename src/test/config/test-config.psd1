@{
    # PSCompassOne Test Configuration
    # Version: 1.0.0
    # PowerShellGet Version: 2.2.5
    # Microsoft.PowerShell.Security: Built-in

    TestConfiguration = @{
        # API Configuration
        # Validates URL format with optional port and path segments
        ApiEndpoint = [ValidatePattern('^https?://[\w.-]+(?::\d+)?(?:/[\w.-]*)*$')] [string]''

        # API Version in semantic versioning format (major.minor.patch)
        ApiVersion = [ValidatePattern('^\d+\.\d+\.\d+$')] [string]''

        # Test Data Path with validation for valid filesystem path
        TestDataPath = [ValidateScript({Test-Path $_ -IsValid})] [string]''

        # Retry Configuration
        # Maximum number of retry attempts (1-10)
        MaxRetries = [ValidateRange(1,10)] [int]3

        # Delay between retry attempts in seconds (1-30)
        RetryDelaySeconds = [ValidateRange(1,30)] [int]2

        # Operation timeout in seconds (1-300)
        TimeoutSeconds = [ValidateRange(1,300)] [int]30

        # Logging and Debug Settings
        # Enable verbose logging output
        EnableVerboseLogging = [bool]$false

        # Enable debug output for detailed troubleshooting
        EnableDebugOutput = [bool]$false

        # Test Execution Configuration
        # Use mock data instead of real API calls
        UseMockData = [bool]$false

        # Skip tests marked as long-running
        SkipLongRunningTests = [bool]$false

        # Enable parallel test execution
        ParallelTestExecution = [bool]$true

        # Test Categories to include
        TestCategories = [string[]]@()

        # Tests to exclude from execution
        ExcludedTests = [string[]]@()
    }
}