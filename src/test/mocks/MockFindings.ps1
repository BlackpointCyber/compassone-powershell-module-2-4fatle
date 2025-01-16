#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

using namespace System.Collections.Generic

# Import required functions and data
. "$PSScriptRoot/../helpers/MockHelpers.ps1"
$TestFindings = Get-Content -Path "$PSScriptRoot/../data/TestFindings.json" | ConvertFrom-Json

# Cache for finding correlations
$script:FindingCorrelationCache = [Dictionary[string,object]]::new()

<#
.SYNOPSIS
    Creates a new mock for finding-related API endpoints with support for complex correlation patterns.
.DESCRIPTION
    Creates a comprehensive mock implementation for finding API endpoints, supporting correlation patterns,
    error simulation, and advanced response customization.
.PARAMETER EndpointPath
    The API endpoint path to mock
.PARAMETER Parameters
    Parameters for the mock endpoint
.PARAMETER CorrelationConfig
    Configuration for finding correlation behavior
.PARAMETER ErrorSimulation
    Configuration for simulating error conditions
#>
function New-FindingMock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$EndpointPath,

        [Parameter()]
        [hashtable]$Parameters = @{},

        [Parameter()]
        [hashtable]$CorrelationConfig = @{},

        [Parameter()]
        [hashtable]$ErrorSimulation = @{}
    )

    # Validate endpoint path
    if (-not $EndpointPath.StartsWith('/api/v1/findings')) {
        throw [System.ArgumentException]::new(
            "Invalid findings endpoint path: $EndpointPath")
    }

    # Configure error simulation if specified
    if ($ErrorSimulation.Count -gt 0) {
        if ($ErrorSimulation.ContainsKey('probability') -and 
            (Get-Random -Minimum 0 -Maximum 100) -lt $ErrorSimulation.probability) {
            return New-FindingMockResponse -StatusCode 500 -ErrorDetails @{
                message = $ErrorSimulation.message ?? "Simulated error"
                code = $ErrorSimulation.code ?? "INTERNAL_ERROR"
            }
        }
    }

    # Create mock based on endpoint type
    $mockObject = {
        param($Params)

        switch -Regex ($EndpointPath) {
            '/api/v1/findings$' {
                # GET /api/v1/findings - List findings
                if ($Params.Method -eq 'GET') {
                    $findings = Get-FindingMockData -Parameters $Params
                    return New-FindingMockResponse -StatusCode 200 -FindingData $findings
                }
                # POST /api/v1/findings - Create finding
                elseif ($Params.Method -eq 'POST') {
                    $newFinding = $Params.Body | ConvertFrom-Json
                    return New-FindingMockResponse -StatusCode 201 -FindingData $newFinding
                }
            }
            '/api/v1/findings/(\{?[a-f0-9-]+\}?)$' {
                $findingId = $matches[1]
                # GET /api/v1/findings/{id} - Get finding by ID
                if ($Params.Method -eq 'GET') {
                    $finding = Get-FindingMockData -Id $findingId
                    if (-not $finding) {
                        return New-FindingMockResponse -StatusCode 404 -ErrorDetails @{
                            message = "Finding not found"
                            code = "FINDING_NOT_FOUND"
                        }
                    }
                    return New-FindingMockResponse -StatusCode 200 -FindingData $finding
                }
                # PUT /api/v1/findings/{id} - Update finding
                elseif ($Params.Method -eq 'PUT') {
                    $updatedFinding = $Params.Body | ConvertFrom-Json
                    return New-FindingMockResponse -StatusCode 200 -FindingData $updatedFinding
                }
                # DELETE /api/v1/findings/{id} - Delete finding
                elseif ($Params.Method -eq 'DELETE') {
                    return New-FindingMockResponse -StatusCode 204
                }
            }
            '/api/v1/findings/(\{?[a-f0-9-]+\}?)/correlations$' {
                $findingId = $matches[1]
                # GET /api/v1/findings/{id}/correlations - Get correlated findings
                if ($Params.Method -eq 'GET') {
                    $correlations = Get-FindingMockData -Id $findingId -IncludeCorrelations $true
                    return New-FindingMockResponse -StatusCode 200 -FindingData $correlations
                }
            }
        }

        # Return 405 for unsupported methods
        return New-FindingMockResponse -StatusCode 405 -ErrorDetails @{
            message = "Method not allowed"
            code = "METHOD_NOT_ALLOWED"
        }
    }

    return $mockObject
}

<#
.SYNOPSIS
    Retrieves mock finding data based on specified criteria with correlation support.
.DESCRIPTION
    Gets mock finding data with support for filtering, correlation patterns, and caching.
.PARAMETER Id
    Finding ID to retrieve
.PARAMETER Status
    Filter by finding status
.PARAMETER Severity
    Filter by finding severity
.PARAMETER RelatedFindings
    Array of related finding IDs
.PARAMETER CorrelationRules
    Rules for finding correlation
#>
function Get-FindingMockData {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Id,

        [Parameter()]
        [ValidateSet('Open', 'InProgress', 'Resolved', 'Closed')]
        [string]$Status,

        [Parameter()]
        [ValidateSet('Critical', 'High', 'Medium', 'Low', 'Info')]
        [string]$Severity,

        [Parameter()]
        [string[]]$RelatedFindings,

        [Parameter()]
        [hashtable]$CorrelationRules = @{}
    )

    # Use cached test findings
    $findings = $TestFindings

    # Apply filters
    if ($Id) {
        $findings = $findings | Where-Object { $_.id -eq $Id }
    }
    if ($Status) {
        $findings = $findings | Where-Object { $_.status -eq $Status }
    }
    if ($Severity) {
        $findings = $findings | Where-Object { $_.severity -eq $Severity }
    }

    # Apply correlation rules
    if ($CorrelationRules.Count -gt 0) {
        $findings = $findings | ForEach-Object {
            $finding = $_
            
            # Add correlation metadata
            $finding | Add-Member -NotePropertyName 'correlationMetadata' -NotePropertyValue @{
                correlationId = [guid]::NewGuid().ToString()
                correlationRules = $CorrelationRules
                correlationTimestamp = [datetime]::UtcNow
            } -Force

            # Process related findings
            if ($finding.relatedFindings.Count -gt 0) {
                $relatedData = $finding.relatedFindings | ForEach-Object {
                    $relatedId = $_
                    $TestFindings | Where-Object { $_.id -eq $relatedId }
                }
                $finding | Add-Member -NotePropertyName 'correlatedFindings' -NotePropertyValue $relatedData -Force
            }

            $finding
        }
    }

    return $findings
}

<#
.SYNOPSIS
    Creates a standardized mock response for finding operations.
.DESCRIPTION
    Generates a mock response with proper headers and metadata for finding operations.
.PARAMETER StatusCode
    HTTP status code for the response
.PARAMETER FindingData
    Finding data to include in response
.PARAMETER Headers
    Additional headers to include
.PARAMETER ErrorDetails
    Error details for error responses
#>
function New-FindingMockResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(100,599)]
        [int]$StatusCode,

        [Parameter()]
        [object]$FindingData,

        [Parameter()]
        [hashtable]$Headers = @{},

        [Parameter()]
        [hashtable]$ErrorDetails
    )

    # Add finding-specific headers
    $findingHeaders = @{
        'X-Finding-Count' = if ($FindingData) { @($FindingData).Count } else { 0 }
        'X-Correlation-Id' = [guid]::NewGuid().ToString()
        'X-Finding-Version' = '1.0'
    }

    # Combine with standard headers
    $responseHeaders = $Headers + $findingHeaders

    # Create response content
    $responseContent = if ($ErrorDetails) {
        $ErrorDetails
    }
    else {
        $FindingData
    }

    # Return formatted response
    return New-MockResponse -StatusCode $StatusCode -Content $responseContent -Headers $responseHeaders
}

# Export functions
Export-ModuleMember -Function @(
    'New-FindingMock',
    'Get-FindingMockData',
    'New-FindingMockResponse'
)