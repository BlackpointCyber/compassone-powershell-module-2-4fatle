#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

using namespace System.Collections.Generic
using namespace System.Net.Http

# Import required mock helper functions
. "$PSScriptRoot/../helpers/MockHelpers.ps1"

# Relationship type and direction enums
$RELATIONSHIP_TYPES = @('connects_to', 'depends_on', 'contains', 'manages', 'monitors')
$RELATIONSHIP_DIRECTIONS = @('inbound', 'outbound', 'bidirectional')

<#
.SYNOPSIS
    Creates comprehensive mock implementations for relationship API endpoints.
.DESCRIPTION
    Implements mock endpoints for relationship CRUD operations with validation,
    error handling, and test scenario support.
#>
function New-RelationshipMock {
    [CmdletBinding()]
    param()

    # GET /relationships - List relationships with filtering and pagination
    $listRelationshipsMock = New-ApiMock -EndpointPath '/relationships' `
        -ResponseData { Get-RelationshipMockData } `
        -ValidationScript {
            param($Parameters)
            
            # Validate pagination parameters
            if ($Parameters.ContainsKey('page_size') -and 
                ($Parameters.page_size -lt 1 -or $Parameters.page_size -gt 100)) {
                return $false
            }

            # Validate filter parameters
            if ($Parameters.ContainsKey('type') -and 
                $Parameters.type -notin $RELATIONSHIP_TYPES) {
                return $false
            }

            if ($Parameters.ContainsKey('direction') -and 
                $Parameters.direction -notin $RELATIONSHIP_DIRECTIONS) {
                return $false
            }

            return $true
        }

    # GET /relationships/{id} - Get specific relationship
    $getRelationshipMock = New-ApiMock -EndpointPath '/relationships/{id}' `
        -ResponseData { Get-RelationshipMockData -Scenario 'SingleRelationship' } `
        -ValidationScript {
            param($Parameters)
            
            # Validate relationship ID format (UUID)
            if (-not ($Parameters.id -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')) {
                return $false
            }

            return $true
        }

    # POST /relationships - Create new relationship
    $createRelationshipMock = New-ApiMock -EndpointPath '/relationships' `
        -ResponseData { Get-RelationshipMockData -Scenario 'NewRelationship' } `
        -ValidationScript {
            param($Parameters)
            
            # Validate required parameters
            if (-not (Test-MockParameters -Parameters $Parameters -RequiredParams @(
                'source_id', 'target_id', 'type', 'direction'))) {
                return $false
            }

            # Validate relationship type
            if ($Parameters.type -notin $RELATIONSHIP_TYPES) {
                return $false
            }

            # Validate direction
            if ($Parameters.direction -notin $RELATIONSHIP_DIRECTIONS) {
                return $false
            }

            # Validate asset IDs (UUID format)
            $uuidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
            if (-not ($Parameters.source_id -match $uuidPattern -and 
                     $Parameters.target_id -match $uuidPattern)) {
                return $false
            }

            # Validate optional properties
            if ($Parameters.ContainsKey('properties')) {
                if ($Parameters.properties.ContainsKey('tags') -and 
                    $Parameters.properties.tags -isnot [array]) {
                    return $false
                }
            }

            return $true
        }

    # PUT /relationships/{id} - Update relationship
    $updateRelationshipMock = New-ApiMock -EndpointPath '/relationships/{id}' `
        -ResponseData { Get-RelationshipMockData -Scenario 'UpdatedRelationship' } `
        -ValidationScript {
            param($Parameters)
            
            # Validate relationship ID
            if (-not ($Parameters.id -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')) {
                return $false
            }

            # Validate update parameters
            if ($Parameters.ContainsKey('type') -and 
                $Parameters.type -notin $RELATIONSHIP_TYPES) {
                return $false
            }

            if ($Parameters.ContainsKey('direction') -and 
                $Parameters.direction -notin $RELATIONSHIP_DIRECTIONS) {
                return $false
            }

            return $true
        }

    # DELETE /relationships/{id} - Delete relationship
    $deleteRelationshipMock = New-ApiMock -EndpointPath '/relationships/{id}' `
        -ResponseData @{ status = 'deleted' } `
        -ValidationScript {
            param($Parameters)
            
            # Validate relationship ID
            if (-not ($Parameters.id -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')) {
                return $false
            }

            return $true
        }

    return @{
        ListRelationships = $listRelationshipsMock
        GetRelationship = $getRelationshipMock
        CreateRelationship = $createRelationshipMock
        UpdateRelationship = $updateRelationshipMock
        DeleteRelationship = $deleteRelationshipMock
    }
}

<#
.SYNOPSIS
    Retrieves mock relationship data for testing scenarios.
.DESCRIPTION
    Loads and formats mock relationship data from test files with support
    for different test scenarios and proper validation.
.PARAMETER Scenario
    The test scenario to retrieve data for.
#>
function Get-RelationshipMockData {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Scenario = 'Default'
    )

    # Get mock data using helper function
    $mockData = Get-MockData -DataType 'Relationships' -Scenario $Scenario

    # Validate relationship data structure
    foreach ($relationship in $mockData) {
        if (-not (Test-RelationshipMockParameters -Parameters @{
            id = $relationship.id
            source_id = $relationship.source_id
            target_id = $relationship.target_id
            type = $relationship.type
            direction = $relationship.direction
            properties = $relationship.properties
        })) {
            throw "Invalid relationship mock data structure"
        }
    }

    return $mockData
}

<#
.SYNOPSIS
    Validates relationship mock parameters.
.DESCRIPTION
    Performs comprehensive validation of relationship parameters including
    type checking, format validation, and required field verification.
.PARAMETER Parameters
    Hashtable of parameters to validate.
#>
function Test-RelationshipMockParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Parameters
    )

    # Validate required fields
    $requiredParams = @('id', 'source_id', 'target_id', 'type', 'direction')
    foreach ($param in $requiredParams) {
        if (-not $Parameters.ContainsKey($param)) {
            Write-Error "Missing required parameter: $param"
            return $false
        }
    }

    # Validate UUID formats
    $uuidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
    $uuidFields = @('id', 'source_id', 'target_id')
    foreach ($field in $uuidFields) {
        if (-not ($Parameters[$field] -match $uuidPattern)) {
            Write-Error "Invalid UUID format for $field"
            return $false
        }
    }

    # Validate relationship type
    if ($Parameters.type -notin $RELATIONSHIP_TYPES) {
        Write-Error "Invalid relationship type: $($Parameters.type)"
        return $false
    }

    # Validate direction
    if ($Parameters.direction -notin $RELATIONSHIP_DIRECTIONS) {
        Write-Error "Invalid relationship direction: $($Parameters.direction)"
        return $false
    }

    # Validate properties if present
    if ($Parameters.ContainsKey('properties')) {
        $props = $Parameters.properties

        # Validate tags
        if ($props.ContainsKey('tags')) {
            if ($props.tags -isnot [array]) {
                Write-Error "Tags must be an array"
                return $false
            }
            foreach ($tag in $props.tags) {
                if ($tag -isnot [string] -or $tag.Length -gt 64) {
                    Write-Error "Invalid tag format"
                    return $false
                }
            }
        }

        # Validate timestamps
        $dateFields = @('created_at', 'updated_at')
        foreach ($field in $dateFields) {
            if ($props.ContainsKey($field)) {
                try {
                    [datetime]::Parse($props[$field])
                }
                catch {
                    Write-Error "Invalid datetime format for $field"
                    return $false
                }
            }
        }
    }

    return $true
}

# Export functions
Export-ModuleMember -Function @(
    'New-RelationshipMock',
    'Get-RelationshipMockData'
)