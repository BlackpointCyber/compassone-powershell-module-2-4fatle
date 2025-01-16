#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

using namespace System.Collections.Generic
using namespace System.Net.Http

# Import helper functions from MockHelpers.ps1
. "$PSScriptRoot/../helpers/MockHelpers.ps1"

# Asset type definitions and required properties
$script:AssetTypes = @('DEVICE', 'CONTAINER', 'SOFTWARE', 'USER', 'PROCESS')
$script:RequiredProperties = @{
    'DEVICE'    = @('name', 'status', 'model')
    'CONTAINER' = @('name', 'status', 'image')
    'SOFTWARE'  = @('name', 'status', 'version')
    'USER'      = @('name', 'email', 'username')
    'PROCESS'   = @('name', 'pid', 'status')
}

# Default mock configuration
$script:DefaultMockConfig = @{
    CacheEnabled = $true
    ErrorSimulation = $true
    RateLimiting = $true
    BulkOperations = $true
}

<#
.SYNOPSIS
    Creates enhanced mock implementations for asset-related API endpoints.
.DESCRIPTION
    Provides comprehensive mock implementations for asset API endpoints with support for
    bulk operations, error simulation, cross-platform compatibility, and caching.
.PARAMETER AssetType
    The type of asset to mock (DEVICE, CONTAINER, SOFTWARE, USER, PROCESS)
.PARAMETER MockConfiguration
    Configuration hashtable for customizing mock behavior
.EXAMPLE
    New-AssetMock -AssetType 'DEVICE' -MockConfiguration @{ ErrorSimulation = $true }
#>
function New-AssetMock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('DEVICE', 'CONTAINER', 'SOFTWARE', 'USER', 'PROCESS')]
        [string]$AssetType,

        [Parameter()]
        [hashtable]$MockConfiguration = $script:DefaultMockConfig
    )

    # Merge with default configuration
    $config = $script:DefaultMockConfig.Clone()
    if ($MockConfiguration) {
        foreach ($key in $MockConfiguration.Keys) {
            $config[$key] = $MockConfiguration[$key]
        }
    }

    # Create mock collection
    $mocks = @{}

    # GET /assets endpoint mock
    $mocks['GetAssets'] = New-ApiMock -EndpointPath "/api/v1/assets" `
        -ValidationScript {
            param($Parameters)
            Mock-GetAssets -AssetType $AssetType -QueryParameters $Parameters
        }

    # GET /assets/{id} endpoint mock
    $mocks['GetAssetById'] = New-ApiMock -EndpointPath "/api/v1/assets/{id}" `
        -ValidationScript {
            param($Parameters)
            
            if (-not $Parameters.ContainsKey('id')) {
                return $false
            }

            $mockData = Get-MockData -DataType $AssetType -Scenario 'SingleAsset'
            
            if ($config.ErrorSimulation -and $Parameters.id -eq 'error') {
                throw [HttpRequestException]::new(
                    "Asset not found", $null, [System.Net.HttpStatusCode]::NotFound)
            }

            New-MockResponse -StatusCode 200 -Content $mockData
        }

    # POST /assets endpoint mock with bulk support
    $mocks['CreateAsset'] = New-ApiMock -EndpointPath "/api/v1/assets" `
        -ValidationScript {
            param($Parameters)
            
            # Validate required properties
            $requiredProps = $script:RequiredProperties[$AssetType]
            foreach ($prop in $requiredProps) {
                if (-not $Parameters.ContainsKey($prop)) {
                    throw [ArgumentException]::new("Missing required property: $prop")
                }
            }

            # Handle bulk operations
            if ($config.BulkOperations -and $Parameters -is [array]) {
                $results = @()
                foreach ($item in $Parameters) {
                    $results += @{
                        id = [guid]::NewGuid().ToString()
                        type = $AssetType
                    } + $item
                }
                return New-MockResponse -StatusCode 201 -Content $results
            }

            # Single asset creation
            $result = @{
                id = [guid]::NewGuid().ToString()
                type = $AssetType
            } + $Parameters

            New-MockResponse -StatusCode 201 -Content $result
        }

    # PUT /assets/{id} endpoint mock
    $mocks['UpdateAsset'] = New-ApiMock -EndpointPath "/api/v1/assets/{id}" `
        -ValidationScript {
            param($Parameters)
            
            if (-not $Parameters.ContainsKey('id')) {
                return $false
            }

            if ($config.ErrorSimulation -and $Parameters.id -eq 'error') {
                throw [HttpRequestException]::new(
                    "Asset not found", $null, [System.Net.HttpStatusCode]::NotFound)
            }

            $result = @{
                id = $Parameters.id
                type = $AssetType
            } + $Parameters

            New-MockResponse -StatusCode 200 -Content $result
        }

    # DELETE /assets/{id} endpoint mock
    $mocks['DeleteAsset'] = New-ApiMock -EndpointPath "/api/v1/assets/{id}" `
        -ValidationScript {
            param($Parameters)
            
            if (-not $Parameters.ContainsKey('id')) {
                return $false
            }

            if ($config.ErrorSimulation -and $Parameters.id -eq 'error') {
                throw [HttpRequestException]::new(
                    "Asset not found", $null, [System.Net.HttpStatusCode]::NotFound)
            }

            New-MockResponse -StatusCode 204
        }

    return $mocks
}

<#
.SYNOPSIS
    Enhanced mock for the GET /assets endpoint with advanced filtering and pagination.
.DESCRIPTION
    Implements a comprehensive mock for asset listing with support for filtering,
    pagination, sorting, and caching.
.PARAMETER AssetType
    The type of asset being mocked
.PARAMETER QueryParameters
    Query parameters for filtering and sorting
.PARAMETER PaginationOptions
    Options for result pagination
#>
function Mock-GetAssets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AssetType,

        [Parameter()]
        [hashtable]$QueryParameters = @{},

        [Parameter()]
        [hashtable]$PaginationOptions = @{
            limit = 50
            offset = 0
        }
    )

    # Load mock data
    $mockData = Get-MockData -DataType $AssetType -Scenario 'List'

    # Apply filters
    if ($QueryParameters.ContainsKey('filter')) {
        $filter = $QueryParameters.filter
        $mockData = $mockData | Where-Object {
            foreach ($key in $filter.Keys) {
                if ($_.$key -ne $filter[$key]) {
                    return $false
                }
            }
            return $true
        }
    }

    # Apply sorting
    if ($QueryParameters.ContainsKey('sort')) {
        $sortField = $QueryParameters.sort
        $sortDescending = $sortField.StartsWith('-')
        $sortField = $sortField.TrimStart('-')
        
        $mockData = $mockData | Sort-Object -Property $sortField -Descending:$sortDescending
    }

    # Apply pagination
    $total = $mockData.Count
    $limit = [Math]::Min($PaginationOptions.limit, 100)
    $offset = $PaginationOptions.offset
    
    $pagedData = $mockData | 
        Select-Object -Skip $offset -First $limit

    # Construct response with pagination metadata
    $response = @{
        data = $pagedData
        metadata = @{
            total = $total
            limit = $limit
            offset = $offset
            hasMore = ($offset + $limit) -lt $total
        }
    }

    New-MockResponse -StatusCode 200 -Content $response
}

# Export the main mock creation function
Export-ModuleMember -Function New-AssetMock