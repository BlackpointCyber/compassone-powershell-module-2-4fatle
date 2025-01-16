#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

using namespace System.Collections.Generic
using namespace System.Net.Http

# Import required functions and configuration
. "$PSScriptRoot/../helpers/MockHelpers.ps1"

# Global state for mock endpoints and responses
$script:MockApiEndpoints = @{}
$script:MockResponses = @{}

# Rate limiting configuration
$script:RateLimitConfig = @{
    RequestsPerHour = 1000
    RequestCount = @{}
    LastReset = [DateTime]::UtcNow
}

<#
.SYNOPSIS
    Initializes all mock API endpoints for testing.
.DESCRIPTION
    Sets up comprehensive mock implementations of the CompassOne REST API endpoints
    with support for validation, rate limiting, and response caching.
#>
function Initialize-MockApi {
    [CmdletBinding()]
    param()

    # Initialize mock endpoints
    $script:MockApiEndpoints = @{}
    $script:MockResponses = @{}

    # Initialize core endpoints
    New-MockAssetEndpoint
    New-MockFindingEndpoint
    New-MockAuthEndpoint

    # Validate mock endpoint health
    $endpoints = $script:MockApiEndpoints.Keys
    Write-Verbose "Initialized $(($endpoints).Count) mock endpoints"
}

<#
.SYNOPSIS
    Creates mock endpoints for asset operations.
.DESCRIPTION
    Implements sophisticated mock endpoints for asset CRUD operations with
    support for validation, caching, and error simulation.
#>
function New-MockAssetEndpoint {
    [CmdletBinding()]
    param()

    # GET /api/v1/assets
    $script:MockApiEndpoints['/api/v1/assets'] = New-ApiMock -EndpointPath '/api/v1/assets' `
        -ResponseData (Get-MockData -DataType 'Assets' -Scenario 'List') `
        -ValidationScript {
            param($Parameters)
            
            # Validate pagination parameters
            if ($Parameters.ContainsKey('pageSize')) {
                if ($Parameters.pageSize -lt 1 -or $Parameters.pageSize -gt 100) {
                    return $false
                }
            }
            
            return $true
        }

    # GET /api/v1/assets/{id}
    $script:MockApiEndpoints['/api/v1/assets/{id}'] = New-ApiMock -EndpointPath '/api/v1/assets/{id}' `
        -ResponseData (Get-MockData -DataType 'Assets' -Scenario 'Single') `
        -ValidationScript {
            param($Parameters)
            return Test-MockParameters -Parameters $Parameters -RequiredParams @('id')
        }

    # POST /api/v1/assets
    $script:MockApiEndpoints['/api/v1/assets'] = New-ApiMock -EndpointPath '/api/v1/assets' `
        -ResponseData (Get-MockData -DataType 'Assets' -Scenario 'Create') `
        -ValidationScript {
            param($Parameters)
            return Test-MockParameters -Parameters $Parameters -RequiredParams @('name', 'type')
        }

    # PUT /api/v1/assets/{id}
    $script:MockApiEndpoints['/api/v1/assets/{id}'] = New-ApiMock -EndpointPath '/api/v1/assets/{id}' `
        -ResponseData (Get-MockData -DataType 'Assets' -Scenario 'Update') `
        -ValidationScript {
            param($Parameters)
            return Test-MockParameters -Parameters $Parameters -RequiredParams @('id')
        }

    # DELETE /api/v1/assets/{id}
    $script:MockApiEndpoints['/api/v1/assets/{id}'] = New-ApiMock -EndpointPath '/api/v1/assets/{id}' `
        -ResponseData $null `
        -ValidationScript {
            param($Parameters)
            return Test-MockParameters -Parameters $Parameters -RequiredParams @('id')
        }
}

<#
.SYNOPSIS
    Creates mock endpoints for finding operations.
.DESCRIPTION
    Implements comprehensive mock endpoints for finding operations with
    support for advanced search and correlation capabilities.
#>
function New-MockFindingEndpoint {
    [CmdletBinding()]
    param()

    # GET /api/v1/findings
    $script:MockApiEndpoints['/api/v1/findings'] = New-ApiMock -EndpointPath '/api/v1/findings' `
        -ResponseData (Get-MockData -DataType 'Findings' -Scenario 'List') `
        -ValidationScript {
            param($Parameters)
            
            # Validate search parameters
            if ($Parameters.ContainsKey('query')) {
                if ($Parameters.query.Length -gt 256) {
                    return $false
                }
            }
            
            return $true
        }

    # GET /api/v1/findings/{id}
    $script:MockApiEndpoints['/api/v1/findings/{id}'] = New-ApiMock -EndpointPath '/api/v1/findings/{id}' `
        -ResponseData (Get-MockData -DataType 'Findings' -Scenario 'Single') `
        -ValidationScript {
            param($Parameters)
            return Test-MockParameters -Parameters $Parameters -RequiredParams @('id')
        }

    # POST /api/v1/findings
    $script:MockApiEndpoints['/api/v1/findings'] = New-ApiMock -EndpointPath '/api/v1/findings' `
        -ResponseData (Get-MockData -DataType 'Findings' -Scenario 'Create') `
        -ValidationScript {
            param($Parameters)
            return Test-MockParameters -Parameters $Parameters -RequiredParams @('title', 'severity')
        }
}

<#
.SYNOPSIS
    Creates mock endpoints for authentication operations.
.DESCRIPTION
    Implements secure mock endpoints for authentication with token
    lifecycle management and security validation.
#>
function New-MockAuthEndpoint {
    [CmdletBinding()]
    param()

    # POST /api/v1/auth/token
    $script:MockApiEndpoints['/api/v1/auth/token'] = New-ApiMock -EndpointPath '/api/v1/auth/token' `
        -ResponseData @{
            token = "mock-jwt-token"
            expires = ([DateTime]::UtcNow.AddHours(1)).ToString('o')
            tokenType = "Bearer"
        } `
        -ValidationScript {
            param($Parameters)
            return Test-MockParameters -Parameters $Parameters -RequiredParams @('apiKey')
        }

    # POST /api/v1/auth/validate
    $script:MockApiEndpoints['/api/v1/auth/validate'] = New-ApiMock -EndpointPath '/api/v1/auth/validate' `
        -ResponseData @{
            valid = $true
            expires = ([DateTime]::UtcNow.AddHours(1)).ToString('o')
        } `
        -ValidationScript {
            param($Parameters)
            return Test-MockParameters -Parameters $Parameters -RequiredParams @('token')
        }

    # POST /api/v1/auth/refresh
    $script:MockApiEndpoints['/api/v1/auth/refresh'] = New-ApiMock -EndpointPath '/api/v1/auth/refresh' `
        -ResponseData @{
            token = "mock-jwt-token-refreshed"
            expires = ([DateTime]::UtcNow.AddHours(1)).ToString('o')
            tokenType = "Bearer"
        } `
        -ValidationScript {
            param($Parameters)
            return Test-MockParameters -Parameters $Parameters -RequiredParams @('refreshToken')
        }
}

# Export public functions
Export-ModuleMember -Function @(
    'Initialize-MockApi',
    'New-MockAssetEndpoint',
    'New-MockFindingEndpoint',
    'New-MockAuthEndpoint'
)