#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

using namespace System.Collections.Generic
using namespace System.Net.Http

# Import test configuration
$TestConfig = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot '../config/test-config.psd1')
$TestConfiguration = $TestConfig.TestConfiguration

# Cache for mock data
$script:MockDataCache = [Dictionary[string,object]]::new()

<#
.SYNOPSIS
    Creates a new mock object for API endpoints with configurable responses and validation.
.DESCRIPTION
    Creates a comprehensive mock object for API testing with support for response customization,
    parameter validation, and error simulation.
.PARAMETER EndpointPath
    The API endpoint path to mock
.PARAMETER ResponseData
    Hashtable containing the mock response data
.PARAMETER ValidationScript
    Script block for parameter validation
.EXAMPLE
    New-ApiMock -EndpointPath '/api/v1/assets' -ResponseData @{ id = '123'; name = 'test' }
#>
function New-ApiMock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$EndpointPath,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$ResponseData,

        [Parameter()]
        [scriptblock]$ValidationScript
    )

    # Construct full endpoint URL
    $fullEndpoint = Join-Path $TestConfiguration.ApiEndpoint `
                             ($EndpointPath.TrimStart('/'))

    # Create default validation if none provided
    if (-not $ValidationScript) {
        $ValidationScript = { $true }
    }

    # Create the mock with validation and response handling
    $mockObject = {
        param($Parameters)

        # Validate parameters if script provided
        if (-not (& $ValidationScript $Parameters)) {
            throw [System.ArgumentException]::new(
                "Invalid parameters provided to mock endpoint: $EndpointPath")
        }

        # Create and return mock response
        New-MockResponse -StatusCode 200 -Content $ResponseData
    }

    return $mockObject
}

<#
.SYNOPSIS
    Creates a standardized mock response object.
.DESCRIPTION
    Generates a mock response with proper headers and formatted content for API testing.
.PARAMETER StatusCode
    HTTP status code for the response
.PARAMETER Content
    Response content object
.PARAMETER Headers
    Additional headers to include
.EXAMPLE
    New-MockResponse -StatusCode 200 -Content @{ id = '123' }
#>
function New-MockResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(100,599)]
        [int]$StatusCode,

        [Parameter()]
        [object]$Content,

        [Parameter()]
        [hashtable]$Headers = @{}
    )

    # Standard headers
    $defaultHeaders = @{
        'Content-Type' = 'application/json'
        'Request-Id' = [guid]::NewGuid().ToString()
        'X-RateLimit-Limit' = '1000'
        'X-RateLimit-Remaining' = '999'
        'X-RateLimit-Reset' = ([DateTimeOffset]::UtcNow.AddHours(1)).ToUnixTimeSeconds()
    }

    # Combine default and custom headers
    $responseHeaders = $defaultHeaders + $Headers

    # Create response object
    $response = @{
        StatusCode = $StatusCode
        Headers = $responseHeaders
        Content = $Content | ConvertTo-Json -Depth 10
    }

    return $response
}

<#
.SYNOPSIS
    Validates parameters passed to mock endpoints.
.DESCRIPTION
    Performs comprehensive parameter validation including type checking and value validation.
.PARAMETER Parameters
    Parameters to validate
.PARAMETER RequiredParams
    Array of required parameter names
.EXAMPLE
    Test-MockParameters -Parameters $params -RequiredParams @('id', 'name')
#>
function Test-MockParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Parameters,

        [Parameter()]
        [string[]]$RequiredParams = @()
    )

    # Check required parameters
    foreach ($param in $RequiredParams) {
        if (-not $Parameters.ContainsKey($param)) {
            Write-Error "Missing required parameter: $param"
            return $false
        }
    }

    # Validate parameter types and values
    foreach ($key in $Parameters.Keys) {
        $value = $Parameters[$key]

        # Null check
        if ($null -eq $value) {
            Write-Error "Parameter '$key' cannot be null"
            return $false
        }

        # String length validation for string parameters
        if ($value -is [string] -and $value.Length -gt 256) {
            Write-Error "Parameter '$key' exceeds maximum length of 256 characters"
            return $false
        }
    }

    return $true
}

<#
.SYNOPSIS
    Retrieves mock data with cross-platform support and caching.
.DESCRIPTION
    Loads and caches mock data from test data files with platform-specific path handling.
.PARAMETER DataType
    Type of mock data to retrieve
.PARAMETER Scenario
    Specific test scenario to load
.EXAMPLE
    Get-MockData -DataType 'Assets' -Scenario 'BasicList'
#>
function Get-MockData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DataType,

        [Parameter()]
        [string]$Scenario = 'Default'
    )

    # Generate cache key
    $cacheKey = "$DataType-$Scenario"

    # Check cache first
    if ($script:MockDataCache.ContainsKey($cacheKey)) {
        return $script:MockDataCache[$cacheKey]
    }

    # Construct platform-agnostic path
    $dataPath = Join-Path $TestConfiguration.TestDataPath `
                         "$DataType.json"

    # Verify file exists
    if (-not (Test-Path $dataPath)) {
        throw [System.IO.FileNotFoundException]::new(
            "Mock data file not found: $dataPath")
    }

    try {
        # Load and parse JSON data
        $mockData = Get-Content -Path $dataPath -Raw | 
                   ConvertFrom-Json -ErrorAction Stop

        # Filter by scenario if specified
        if ($Scenario -ne 'Default' -and 
            $mockData.PSObject.Properties.Name -contains 'Scenarios') {
            $mockData = $mockData.Scenarios.$Scenario
        }

        # Cache the results
        $script:MockDataCache[$cacheKey] = $mockData

        return $mockData
    }
    catch {
        throw [System.InvalidOperationException]::new(
            "Failed to load mock data: $_")
    }
}

# Export functions
Export-ModuleMember -Function @(
    'New-ApiMock',
    'New-MockResponse',
    'Test-MockParameters',
    'Get-MockData'
)