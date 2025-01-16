#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

# Import required modules and test data
using module '../helpers/TestHelpers.ps1'
$TestFindings = Get-Content -Path (Join-Path $PSScriptRoot '../data/TestFindings.json') | ConvertFrom-Json

# Global constants for finding properties
$script:FindingSeverityLevels = @('Critical', 'High', 'Medium', 'Low', 'Info')
$script:FindingStatusTypes = @('Open', 'InProgress', 'Resolved', 'Closed')

function New-FindingFixture {
    [CmdletBinding()]
    param (
        [Parameter()]
        [hashtable]$Properties = @{},

        [Parameter()]
        [switch]$SkipValidation,

        [Parameter()]
        [string]$Template
    )

    try {
        # Get base template if specified
        $baseTemplate = if ($Template) {
            $TestFindings | Where-Object { $_.id -match $Template } | Select-Object -First 1
        } else {
            $TestFindings[0]
        }

        # Create base finding object
        $finding = [PSCustomObject]@{
            id = [System.Guid]::NewGuid().ToString()
            title = $Properties.title ?? $baseTemplate.title ?? "Test Finding"
            description = $Properties.description ?? $baseTemplate.description ?? "Test finding description"
            severity = $Properties.severity ?? $baseTemplate.severity ?? "Medium"
            status = $Properties.status ?? $baseTemplate.status ?? "Open"
            createdAt = $Properties.createdAt ?? (Get-Date).ToUniversalTime().ToString('o')
            updatedAt = $Properties.updatedAt ?? (Get-Date).ToUniversalTime().ToString('o')
            assetId = $Properties.assetId ?? $baseTemplate.assetId ?? "test-asset-001"
            tags = $Properties.tags ?? $baseTemplate.tags ?? @()
            relatedFindings = $Properties.relatedFindings ?? $baseTemplate.relatedFindings ?? @()
        }

        # Skip validation if requested
        if (-not $SkipValidation) {
            # Validate severity
            if ($finding.severity -notin $script:FindingSeverityLevels) {
                throw "Invalid severity level: $($finding.severity)"
            }

            # Validate status
            if ($finding.status -notin $script:FindingStatusTypes) {
                throw "Invalid status type: $($finding.status)"
            }

            # Validate required fields
            if ([string]::IsNullOrWhiteSpace($finding.title)) {
                throw "Finding title cannot be empty"
            }

            if ([string]::IsNullOrWhiteSpace($finding.description)) {
                throw "Finding description cannot be empty"
            }

            # Validate dates
            try {
                [datetime]::Parse($finding.createdAt)
                [datetime]::Parse($finding.updatedAt)
            }
            catch {
                throw "Invalid date format in finding"
            }

            # Validate related findings format
            foreach ($relatedId in $finding.relatedFindings) {
                if (-not [guid]::TryParse($relatedId, [ref]$null)) {
                    throw "Invalid related finding ID format: $relatedId"
                }
            }
        }

        return $finding
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'FindingFixtureCreationError',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $Properties
            )
        )
    }
}

function New-FindingCollectionFixture {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 1000)]
        [int]$Count,

        [Parameter()]
        [hashtable]$Properties = @{},

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$ThrottleLimit = 5
    )

    try {
        $findings = @()
        
        # Create findings in parallel if count is large
        if ($Count -gt 10) {
            $findings = 1..$Count | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
                $finding = New-FindingFixture -Properties $using:Properties
                $finding.id = [System.Guid]::NewGuid().ToString()
                $finding
            }
        }
        else {
            # Create findings sequentially for small collections
            $findings = 1..$Count | ForEach-Object {
                $finding = New-FindingFixture -Properties $Properties
                $finding.id = [System.Guid]::NewGuid().ToString()
                $finding
            }
        }

        return $findings
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'FindingCollectionCreationError',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                @{Count = $Count; Properties = $Properties}
            )
        )
    }
}

function New-RelatedFindingFixture {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ParentFindingId,

        [Parameter()]
        [hashtable]$Properties = @{},

        [Parameter()]
        [ValidateSet('Causes', 'RelatesTo', 'Duplicates')]
        [string]$RelationType = 'RelatesTo'
    )

    try {
        # Create the related finding
        $relatedFinding = New-FindingFixture -Properties $Properties

        # Add relationship to parent
        $relatedFinding.relatedFindings = @($ParentFindingId)

        # Add relationship metadata
        $relatedFinding | Add-Member -NotePropertyName 'relationshipType' -NotePropertyValue $RelationType
        $relatedFinding | Add-Member -NotePropertyName 'parentFindingId' -NotePropertyValue $ParentFindingId

        # Validate relationship
        if (-not [guid]::TryParse($ParentFindingId, [ref]$null)) {
            throw "Invalid parent finding ID format: $ParentFindingId"
        }

        return $relatedFinding
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'RelatedFindingCreationError',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                @{ParentFindingId = $ParentFindingId; Properties = $Properties}
            )
        )
    }
}

# Export functions
Export-ModuleMember -Function @(
    'New-FindingFixture',
    'New-FindingCollectionFixture',
    'New-RelatedFindingFixture'
)