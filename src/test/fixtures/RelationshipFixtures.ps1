#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

# Import required modules and test helpers
using module '../helpers/TestHelpers.ps1'

# Define valid relationship types and directions as constants
$script:ValidRelationshipTypes = @('connects_to', 'depends_on', 'contains', 'manages', 'monitors')
$script:ValidDirections = @('inbound', 'outbound', 'bidirectional')

function New-RelationshipFixture {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('connects_to', 'depends_on', 'contains', 'manages', 'monitors')]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [ValidateSet('inbound', 'outbound', 'bidirectional')]
        [string]$Direction,

        [Parameter()]
        [hashtable]$Properties = @{}
    )

    try {
        # Generate unique identifiers
        $relationshipId = [System.Guid]::NewGuid().ToString()
        $sourceId = [System.Guid]::NewGuid().ToString()
        $targetId = [System.Guid]::NewGuid().ToString()

        # Create base relationship object
        $relationship = [PSCustomObject]@{
            Id = $relationshipId
            Type = $Type
            Direction = $Direction
            SourceId = $sourceId
            TargetId = $targetId
            CreatedAt = (Get-Date).ToUniversalTime()
            UpdatedAt = (Get-Date).ToUniversalTime()
            Status = 'Active'
            Metadata = @{
                TestGenerated = $true
                TestTimestamp = (Get-Date).ToUniversalTime().ToString('o')
            }
        }

        # Add custom properties if provided
        foreach ($key in $Properties.Keys) {
            if ($relationship.PSObject.Properties.Name -contains $key) {
                throw [System.ArgumentException]::new("Cannot override built-in property: $key")
            }
            $relationship | Add-Member -NotePropertyName $key -NotePropertyValue $Properties[$key]
        }

        # Validate the complete fixture
        if (-not (Test-RelationshipFixture -Fixture $relationship)) {
            throw [System.ArgumentException]::new("Invalid relationship fixture")
        }

        return $relationship
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'RelationshipFixtureCreationError',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $Properties
            )
        )
    }
}

function New-ComplexRelationshipFixture {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateRange(2, 100)]
        [int]$NodeCount,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Chain', 'Star', 'Mesh', 'Tree')]
        [string]$Pattern
    )

    try {
        $relationships = @()
        $nodes = @()

        # Create nodes
        for ($i = 0; $i -lt $NodeCount; $i++) {
            $nodes += New-TestAsset -AssetType 'DEVICE' -Properties @{
                name = "TestNode$i"
                model = "TestModel"
            }
        }

        # Create relationships based on pattern
        switch ($Pattern) {
            'Chain' {
                for ($i = 0; $i -lt ($NodeCount - 1); $i++) {
                    $relationships += New-RelationshipFixture -Type 'connects_to' -Direction 'bidirectional' -Properties @{
                        SourceId = $nodes[$i].Id
                        TargetId = $nodes[$i + 1].Id
                    }
                }
            }
            'Star' {
                for ($i = 1; $i -lt $NodeCount; $i++) {
                    $relationships += New-RelationshipFixture -Type 'manages' -Direction 'outbound' -Properties @{
                        SourceId = $nodes[0].Id
                        TargetId = $nodes[$i].Id
                    }
                }
            }
            'Mesh' {
                for ($i = 0; $i -lt $NodeCount; $i++) {
                    for ($j = $i + 1; $j -lt $NodeCount; $j++) {
                        $relationships += New-RelationshipFixture -Type 'connects_to' -Direction 'bidirectional' -Properties @{
                            SourceId = $nodes[$i].Id
                            TargetId = $nodes[$j].Id
                        }
                    }
                }
            }
            'Tree' {
                for ($i = 0; $i -lt [math]::Floor($NodeCount / 2); $i++) {
                    $leftChild = 2 * $i + 1
                    $rightChild = 2 * $i + 2

                    if ($leftChild -lt $NodeCount) {
                        $relationships += New-RelationshipFixture -Type 'contains' -Direction 'outbound' -Properties @{
                            SourceId = $nodes[$i].Id
                            TargetId = $nodes[$leftChild].Id
                        }
                    }
                    if ($rightChild -lt $NodeCount) {
                        $relationships += New-RelationshipFixture -Type 'contains' -Direction 'outbound' -Properties @{
                            SourceId = $nodes[$i].Id
                            TargetId = $nodes[$rightChild].Id
                        }
                    }
                }
            }
        }

        return @{
            Nodes = $nodes
            Relationships = $relationships
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'ComplexRelationshipFixtureCreationError',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                @{NodeCount = $NodeCount; Pattern = $Pattern}
            )
        )
    }
}

function Test-RelationshipFixture {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSObject]$Fixture
    )

    try {
        # Validate required properties
        $requiredProps = @('Id', 'Type', 'Direction', 'SourceId', 'TargetId', 'CreatedAt', 'UpdatedAt', 'Status')
        foreach ($prop in $requiredProps) {
            if (-not $Fixture.PSObject.Properties.Name.Contains($prop)) {
                Write-Error "Missing required property: $prop"
                return $false
            }
        }

        # Validate property values
        if (-not [guid]::TryParse($Fixture.Id, [ref]$null)) {
            Write-Error "Invalid Id format: $($Fixture.Id)"
            return $false
        }

        if ($Fixture.Type -notin $script:ValidRelationshipTypes) {
            Write-Error "Invalid relationship type: $($Fixture.Type)"
            return $false
        }

        if ($Fixture.Direction -notin $script:ValidDirections) {
            Write-Error "Invalid direction: $($Fixture.Direction)"
            return $false
        }

        if (-not [guid]::TryParse($Fixture.SourceId, [ref]$null)) {
            Write-Error "Invalid SourceId format: $($Fixture.SourceId)"
            return $false
        }

        if (-not [guid]::TryParse($Fixture.TargetId, [ref]$null)) {
            Write-Error "Invalid TargetId format: $($Fixture.TargetId)"
            return $false
        }

        # Validate timestamps
        if (-not ($Fixture.CreatedAt -is [datetime])) {
            Write-Error "Invalid CreatedAt format: $($Fixture.CreatedAt)"
            return $false
        }

        if (-not ($Fixture.UpdatedAt -is [datetime])) {
            Write-Error "Invalid UpdatedAt format: $($Fixture.UpdatedAt)"
            return $false
        }

        # Validate status
        if ($Fixture.Status -notin @('Active', 'Inactive', 'Deleted')) {
            Write-Error "Invalid status: $($Fixture.Status)"
            return $false
        }

        return $true
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'RelationshipFixtureValidationError',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $Fixture
            )
        )
    }
}

# Export functions
Export-ModuleMember -Function @(
    'New-RelationshipFixture',
    'New-ComplexRelationshipFixture',
    'Test-RelationshipFixture'
)