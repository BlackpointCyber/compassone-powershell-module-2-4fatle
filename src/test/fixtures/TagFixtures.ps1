#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

# Import required modules and dependencies
. (Join-Path $PSScriptRoot '../helpers/TestHelpers.ps1')

# Cache for test tag data
$script:TagDataCache = @{}

function New-TestTag {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$Properties
    )

    try {
        # Create base tag object with required properties
        $tag = [PSCustomObject]@{
            Id = [System.Guid]::NewGuid().ToString()
            Name = $Properties.Name ?? "TestTag_$(Get-Random)"
            Type = $Properties.Type ?? 'CUSTOM'
            CreatedAt = $Properties.CreatedAt ?? (Get-Date)
            UpdatedAt = $Properties.UpdatedAt ?? (Get-Date)
            Status = $Properties.Status ?? 'Active'
        }

        # Validate required properties
        if ([string]::IsNullOrWhiteSpace($tag.Name)) {
            throw [System.ArgumentException]::new('Tag name cannot be null or empty')
        }

        # Validate tag type
        if ($tag.Type -notin @('SYSTEM', 'CUSTOM', 'ASSET')) {
            throw [System.ArgumentException]::new('Invalid tag type. Must be SYSTEM, CUSTOM, or ASSET')
        }

        # Add optional properties if provided
        $optionalProps = @('Description', 'Color', 'Icon', 'Metadata', 'ParentId')
        foreach ($prop in $optionalProps) {
            if ($Properties.ContainsKey($prop)) {
                $tag | Add-Member -NotePropertyName $prop -NotePropertyValue $Properties[$prop]
            }
        }

        # Add relationships if specified
        if ($Properties.ContainsKey('Relationships')) {
            $tag | Add-Member -NotePropertyName 'Relationships' -NotePropertyValue @()
            foreach ($rel in $Properties.Relationships) {
                if (-not ($rel.SourceId -and $rel.TargetId -and $rel.Type)) {
                    throw [System.ArgumentException]::new('Invalid relationship structure')
                }
                $tag.Relationships += $rel
            }
        }

        return $tag
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'TestTagCreationError',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $Properties
            )
        )
    }
}

function New-TestAssetTagRelationship {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$AssetId,

        [Parameter(Mandatory = $true)]
        [string]$TagId
    )

    try {
        # Validate input parameters
        if ([string]::IsNullOrWhiteSpace($AssetId)) {
            throw [System.ArgumentException]::new('AssetId cannot be null or empty')
        }
        if ([string]::IsNullOrWhiteSpace($TagId)) {
            throw [System.ArgumentException]::new('TagId cannot be null or empty')
        }

        # Create relationship object
        $relationship = [PSCustomObject]@{
            Id = [System.Guid]::NewGuid().ToString()
            SourceId = $AssetId
            TargetId = $TagId
            Type = 'ASSET_TAG'
            CreatedAt = Get-Date
            UpdatedAt = Get-Date
            Status = 'Active'
        }

        return $relationship
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'TestRelationshipCreationError',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                @{AssetId = $AssetId; TagId = $TagId}
            )
        )
    }
}

function Get-TestTagData {
    [CmdletBinding()]
    param (
        [Parameter()]
        [ValidateSet('SYSTEM', 'CUSTOM', 'ASSET')]
        [string]$TagType
    )

    try {
        # Check cache first
        $cacheKey = $TagType ?? 'ALL'
        if ($script:TagDataCache.ContainsKey($cacheKey)) {
            Write-Verbose "Returning cached tag data for type: $cacheKey"
            return $script:TagDataCache[$cacheKey]
        }

        # Load test data from JSON file
        $testDataPath = Join-Path $PSScriptRoot '../data/TestTags.json'
        if (-not (Test-Path $testDataPath)) {
            throw [System.IO.FileNotFoundException]::new("Test data file not found: $testDataPath")
        }

        $tagData = Get-Content $testDataPath -Raw | ConvertFrom-Json

        # Validate JSON schema
        if (-not ($tagData.PSObject.Properties.Name -contains 'systemTags' -and 
                 $tagData.PSObject.Properties.Name -contains 'customTags' -and
                 $tagData.PSObject.Properties.Name -contains 'assetTags')) {
            throw [System.ArgumentException]::new('Invalid test data schema')
        }

        # Filter by tag type if specified
        $result = switch ($TagType) {
            'SYSTEM' { $tagData.systemTags }
            'CUSTOM' { $tagData.customTags }
            'ASSET' { $tagData.assetTags }
            default { 
                @($tagData.systemTags) + @($tagData.customTags) + @($tagData.assetTags)
            }
        }

        # Cache the results
        $script:TagDataCache[$cacheKey] = $result

        return $result
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'TestDataRetrievalError',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $TagType
            )
        )
    }
}

function Initialize-TagTestData {
    [CmdletBinding()]
    param (
        [Parameter()]
        [switch]$UseMockData
    )

    try {
        # Initialize test environment
        $testEnv = Initialize-TestEnvironment -TestName 'TagTests' -UseMockData:$UseMockData -EnableParallel

        # Set up tag-specific test configuration
        $testConfig = @{
            Environment = $testEnv
            TagTypes = @('SYSTEM', 'CUSTOM', 'ASSET')
            ValidationRules = @{
                RequiredProperties = @('Id', 'Name', 'Type', 'Status')
                ValidTypes = @('SYSTEM', 'CUSTOM', 'ASSET')
                MaxNameLength = 100
                MaxDescriptionLength = 500
            }
            MockResponses = @{
                Tags = Get-TestTagData
                Relationships = @()
            }
        }

        # Set up tag-specific mocks if using mock data
        if ($UseMockData) {
            Mock New-PSCompassOneTag {
                param($Properties)
                return New-TestTag -Properties $Properties
            }

            Mock Get-PSCompassOneTag {
                param($Id)
                $tags = Get-TestTagData
                return $tags | Where-Object { $_.Id -eq $Id }
            }

            Mock Get-PSCompassOneTagRelationship {
                param($AssetId, $TagId)
                return New-TestAssetTagRelationship -AssetId $AssetId -TagId $TagId
            }
        }

        return $testConfig
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'TagTestInitializationError',
                [System.Management.Automation.ErrorCategory]::OperationStopped,
                $null
            )
        )
    }
}

# Export functions
Export-ModuleMember -Function @(
    'New-TestTag',
    'New-TestAssetTagRelationship',
    'Get-TestTagData',
    'Initialize-TagTestData'
)