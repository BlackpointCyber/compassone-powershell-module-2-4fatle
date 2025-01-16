#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

# Import required modules and dependencies
using module '../helpers/TestHelpers.ps1'
Import-Module -Name Pester -MinimumVersion 5.0.0

# Base incident properties
$script:BaseIncidentProperties = @{
    Id = $null  # Will be generated dynamically
    Title = "Test Incident"
    Description = "Test incident for automated testing"
    Status = "New"
    CreatedAt = $null  # Will be set at creation time
    UpdatedAt = $null  # Will be set at creation time
    Severity = "Medium"
    Priority = "Normal"
    AssignedTo = $null
    Tags = @()
    RelatedAssets = @()
    Notes = @()
}

function New-TestIncident {
    [CmdletBinding()]
    param (
        [Parameter()]
        [hashtable]$Properties = @{},

        [Parameter()]
        [switch]$EnableParallel
    )

    try {
        # Initialize test environment if needed
        $testEnv = Initialize-TestEnvironment -TestName "IncidentTests" -EnableParallel:$EnableParallel

        # Create base incident object
        $incident = [PSCustomObject]@{
            Id = [System.Guid]::NewGuid().ToString()
            CreatedAt = Get-Date
            UpdatedAt = Get-Date
        }

        # Merge base properties
        foreach ($prop in $script:BaseIncidentProperties.Keys) {
            if ($prop -notin @('Id', 'CreatedAt', 'UpdatedAt')) {
                $incident | Add-Member -NotePropertyName $prop -NotePropertyValue $script:BaseIncidentProperties[$prop]
            }
        }

        # Merge custom properties
        foreach ($prop in $Properties.Keys) {
            $incident | Add-Member -NotePropertyName $prop -NotePropertyValue $Properties[$prop] -Force
        }

        # Add platform-specific metadata
        $incident | Add-Member -NotePropertyName 'TestContext' -NotePropertyValue @{
            Platform = $PSVersionTable.Platform
            PSVersion = $PSVersionTable.PSVersion
            TestId = $testEnv.TestId
            ParallelExecution = $EnableParallel.IsPresent
        }

        return $incident
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'TestIncidentCreationError',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $Properties
            )
        )
    }
}

function New-ActiveIncident {
    [CmdletBinding()]
    param (
        [Parameter()]
        [ValidateSet('Low', 'Medium', 'High', 'Critical')]
        [string]$Severity = 'Medium',

        [Parameter()]
        [hashtable]$Properties = @{},

        [Parameter()]
        [switch]$EnableParallel
    )

    try {
        # Create base incident
        $baseProperties = @{
            Status = 'Active'
            Severity = $Severity
            ActivatedAt = Get-Date
            LastActivityAt = Get-Date
        }

        # Merge with provided properties
        $mergedProperties = $Properties + $baseProperties

        $incident = New-TestIncident -Properties $mergedProperties -EnableParallel:$EnableParallel

        # Add active-specific tracking
        $incident | Add-Member -NotePropertyName 'ActivityLog' -NotePropertyValue @(
            @{
                Timestamp = Get-Date
                Action = 'Activated'
                User = $env:USERNAME
                Details = "Incident activated with severity: $Severity"
            }
        )

        return $incident
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'ActiveIncidentCreationError',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $Properties
            )
        )
    }
}

function New-ResolvedIncident {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResolutionNote,

        [Parameter()]
        [hashtable]$Properties = @{},

        [Parameter()]
        [switch]$EnableParallel
    )

    try {
        # Validate resolution note
        if ([string]::IsNullOrWhiteSpace($ResolutionNote)) {
            throw [System.ArgumentException]::new('Resolution note cannot be empty')
        }

        # Create base incident
        $baseProperties = @{
            Status = 'Resolved'
            ResolvedAt = Get-Date
            ResolutionNote = $ResolutionNote
            Resolution = @{
                Note = $ResolutionNote
                Timestamp = Get-Date
                ResolvedBy = $env:USERNAME
            }
        }

        # Merge with provided properties
        $mergedProperties = $Properties + $baseProperties

        $incident = New-TestIncident -Properties $mergedProperties -EnableParallel:$EnableParallel

        # Add resolution audit trail
        $incident | Add-Member -NotePropertyName 'AuditTrail' -NotePropertyValue @(
            @{
                Timestamp = Get-Date
                Action = 'Resolved'
                User = $env:USERNAME
                Details = "Incident resolved: $ResolutionNote"
            }
        )

        return $incident
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'ResolvedIncidentCreationError',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $Properties
            )
        )
    }
}

function New-EscalatedIncident {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$EscalationReason,

        [Parameter()]
        [hashtable]$Properties = @{},

        [Parameter()]
        [switch]$EnableParallel
    )

    try {
        # Validate escalation reason
        if ([string]::IsNullOrWhiteSpace($EscalationReason)) {
            throw [System.ArgumentException]::new('Escalation reason cannot be empty')
        }

        # Create base incident
        $baseProperties = @{
            Status = 'Escalated'
            Severity = 'High'
            Priority = 'High'
            EscalatedAt = Get-Date
            EscalationReason = $EscalationReason
            EscalationDetails = @{
                Reason = $EscalationReason
                Timestamp = Get-Date
                EscalatedBy = $env:USERNAME
                PreviousSeverity = $Properties.Severity ?? 'Medium'
            }
        }

        # Merge with provided properties
        $mergedProperties = $Properties + $baseProperties

        $incident = New-TestIncident -Properties $mergedProperties -EnableParallel:$EnableParallel

        # Add escalation tracking
        $incident | Add-Member -NotePropertyName 'EscalationHistory' -NotePropertyValue @(
            @{
                Timestamp = Get-Date
                Action = 'Escalated'
                User = $env:USERNAME
                Reason = $EscalationReason
                FromSeverity = $Properties.Severity ?? 'Medium'
                ToSeverity = 'High'
            }
        )

        return $incident
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'EscalatedIncidentCreationError',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $Properties
            )
        )
    }
}

# Export functions
Export-ModuleMember -Function @(
    'New-TestIncident',
    'New-ActiveIncident',
    'New-ResolvedIncident',
    'New-EscalatedIncident'
)