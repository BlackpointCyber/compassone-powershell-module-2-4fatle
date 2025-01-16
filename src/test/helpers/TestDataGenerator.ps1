#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Microsoft.PowerShell.Utility'; ModuleVersion='7.0.0' }

# Import test data templates
$script:TestAssets = Get-Content -Path (Join-Path $PSScriptRoot '../data/TestAssets.json') | ConvertFrom-Json
$script:TestFindings = Get-Content -Path (Join-Path $PSScriptRoot '../data/TestFindings.json') | ConvertFrom-Json
$script:TestIncidents = Get-Content -Path (Join-Path $PSScriptRoot '../data/TestIncidents.json') | ConvertFrom-Json

function New-TestAsset {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('DEVICE', 'CONTAINER', 'SOFTWARE', 'USER', 'PROCESS')]
        [string]$AssetType,

        [Parameter()]
        [hashtable]$Properties = @{},

        [Parameter()]
        [switch]$RandomizeOptional,

        [Parameter()]
        [switch]$CrossPlatform
    )

    try {
        # Select appropriate template based on asset type
        $template = switch ($AssetType) {
            'DEVICE' { Get-Random -InputObject $script:TestAssets.deviceAssets }
            'CONTAINER' { Get-Random -InputObject $script:TestAssets.containerAssets }
            'SOFTWARE' { Get-Random -InputObject $script:TestAssets.softwareAssets }
            'USER' { Get-Random -InputObject $script:TestAssets.userAssets }
            'PROCESS' { Get-Random -InputObject $script:TestAssets.processAssets }
        }

        # Create base asset object
        $asset = [PSCustomObject]@{
            Id = [System.Guid]::NewGuid().ToString()
            Type = $AssetType
            CreatedAt = Get-Date
            UpdatedAt = Get-Date
            Status = 'Active'
        }

        # Copy template properties
        foreach ($prop in $template.PSObject.Properties) {
            $asset | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
        }

        # Override with provided properties
        foreach ($prop in $Properties.Keys) {
            $asset | Add-Member -NotePropertyName $prop -NotePropertyValue $Properties[$prop] -Force
        }

        # Add platform-specific properties if cross-platform is enabled
        if ($CrossPlatform) {
            $asset | Add-Member -NotePropertyName 'Platform' -NotePropertyValue $PSVersionTable.Platform
            $asset | Add-Member -NotePropertyName 'PlatformVersion' -NotePropertyValue $PSVersionTable.PSVersion.ToString()
        }

        # Randomize optional properties if specified
        if ($RandomizeOptional) {
            switch ($AssetType) {
                'DEVICE' {
                    if (-not $Properties.ContainsKey('ips')) {
                        $asset.ips = @("192.168.$((Get-Random -Minimum 1 -Maximum 255)).$((Get-Random -Minimum 1 -Maximum 255))")
                    }
                    if (-not $Properties.ContainsKey('macs')) {
                        $asset.macs = @(([string]::Join(':', (1..6 | ForEach-Object { '{0:X2}' -f (Get-Random -Minimum 0 -Maximum 255) }))))
                    }
                }
                'CONTAINER' {
                    if (-not $Properties.ContainsKey('ports')) {
                        $asset.ports = @(Get-Random -Minimum 1024 -Maximum 65535)
                    }
                    if (-not $Properties.ContainsKey('imageTag')) {
                        $asset.imageTag = "v$((Get-Random -Minimum 1 -Maximum 10)).$((Get-Random -Minimum 0 -Maximum 100))"
                    }
                }
                'SOFTWARE' {
                    if (-not $Properties.ContainsKey('license')) {
                        $asset.license = (Get-Random -InputObject @('MIT', 'Apache-2.0', 'GPL-3.0', 'Proprietary'))
                    }
                    if (-not $Properties.ContainsKey('hipaa')) {
                        $asset.hipaa = (Get-Random -InputObject @($true, $false))
                    }
                }
                'USER' {
                    if (-not $Properties.ContainsKey('mfaEnabled')) {
                        $asset.mfaEnabled = (Get-Random -InputObject @($true, $false))
                    }
                    if (-not $Properties.ContainsKey('admin')) {
                        $asset.admin = (Get-Random -InputObject @($true, $false))
                    }
                }
                'PROCESS' {
                    if (-not $Properties.ContainsKey('ppid')) {
                        $asset.ppid = Get-Random -Minimum 1 -Maximum 65535
                    }
                    if (-not $Properties.ContainsKey('hash')) {
                        $asset.hash = [System.Convert]::ToHexString((1..32 | ForEach-Object { Get-Random -Minimum 0 -Maximum 255 }))
                    }
                }
            }
        }

        return $asset
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'TestAssetCreationError',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $Properties
            )
        )
    }
}

function New-TestFinding {
    [CmdletBinding()]
    param (
        [Parameter()]
        [ValidateSet('Critical', 'High', 'Medium', 'Low', 'Info')]
        [string]$Severity = 'Medium',

        [Parameter()]
        [ValidateSet('Open', 'InProgress', 'Resolved', 'Closed')]
        [string]$Status = 'Open',

        [Parameter()]
        [string]$AssetId,

        [Parameter()]
        [string[]]$RelatedFindings,

        [Parameter()]
        [hashtable]$SecurityContext = @{}
    )

    try {
        # Select random finding template
        $template = Get-Random -InputObject $script:TestFindings

        # Create base finding object
        $finding = [PSCustomObject]@{
            Id = [System.Guid]::NewGuid().ToString()
            Title = $template.title
            Description = $template.description
            Severity = $Severity
            Status = $Status
            CreatedAt = Get-Date
            UpdatedAt = Get-Date
            AssetId = $AssetId ?? $template.assetId
            Tags = $template.tags
            RelatedFindings = $RelatedFindings ?? $template.relatedFindings
            SecurityContext = @{
                CVSS = $SecurityContext.CVSS ?? (Get-Random -Minimum 1.0 -Maximum 10.0)
                Impact = $SecurityContext.Impact ?? 'Unknown'
                Vector = $SecurityContext.Vector ?? 'N/A'
                References = $SecurityContext.References ?? @()
            }
            AuditTrail = @(
                @{
                    Timestamp = Get-Date
                    Action = 'Created'
                    User = $env:USERNAME
                    Details = "Finding created with severity: $Severity"
                }
            )
        }

        return $finding
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'TestFindingCreationError',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $SecurityContext
            )
        )
    }
}

function New-TestIncident {
    [CmdletBinding()]
    param (
        [Parameter()]
        [ValidateSet('Active', 'Escalated', 'Resolved', 'Closed')]
        [string]$Status = 'Active',

        [Parameter()]
        [ValidateSet('Critical', 'High', 'Medium', 'Low')]
        [string]$Severity = 'Medium',

        [Parameter()]
        [string[]]$RelatedAssets,

        [Parameter()]
        [string[]]$RelatedFindings,

        [Parameter()]
        [hashtable]$AuditTrail = @{}
    )

    try {
        # Select random incident template
        $template = Get-Random -InputObject $script:TestIncidents

        # Create base incident object
        $incident = [PSCustomObject]@{
            Id = "INC-$((Get-Random -Minimum 1000 -Maximum 9999))"
            Title = $template.title
            Description = $template.description
            Status = $Status
            Severity = $Severity
            CreatedAt = Get-Date
            UpdatedAt = Get-Date
            AssignedTo = $template.assignedTo
            RelatedAssets = $RelatedAssets ?? $template.relatedAssets
            RelatedFindings = $RelatedFindings ?? $template.relatedFindings
            Tags = $template.tags
            AuditTrail = @(
                @{
                    Timestamp = Get-Date
                    Action = 'Created'
                    User = $env:USERNAME
                    Details = "Incident created with severity: $Severity"
                }
            )
            ParallelExecutionData = $template.parallelExecutionData
        }

        # Add status-specific properties
        switch ($Status) {
            'Escalated' {
                $incident | Add-Member -NotePropertyName 'EscalatedAt' -NotePropertyValue (Get-Date)
                $incident | Add-Member -NotePropertyName 'EscalationReason' -NotePropertyValue 'Test escalation'
            }
            'Resolved' {
                $incident | Add-Member -NotePropertyName 'ResolvedAt' -NotePropertyValue (Get-Date)
                $incident | Add-Member -NotePropertyName 'Resolution' -NotePropertyValue 'Test resolution'
            }
            'Closed' {
                $incident | Add-Member -NotePropertyName 'ClosedAt' -NotePropertyValue (Get-Date)
                $incident | Add-Member -NotePropertyName 'ClosureReason' -NotePropertyValue 'Test closure'
            }
        }

        return $incident
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'TestIncidentCreationError',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $AuditTrail
            )
        )
    }
}

function Get-RandomTestData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Asset', 'Finding', 'Incident')]
        [string]$DataType,

        [Parameter()]
        [int]$Count = 1,

        [Parameter()]
        [switch]$Parallel,

        [Parameter()]
        [hashtable]$ValidationRules = @{}
    )

    try {
        $results = @()

        if ($Parallel -and $Count -gt 1) {
            $jobs = @()
            $runspace = [runspacefactory]::CreateRunspacePool(1, [Environment]::ProcessorCount)
            $runspace.Open()

            for ($i = 0; $i -lt $Count; $i++) {
                $powerShell = [powershell]::Create().AddScript({
                    param($DataType, $ValidationRules)
                    
                    switch ($DataType) {
                        'Asset' { New-TestAsset -AssetType (Get-Random -InputObject @('DEVICE','CONTAINER','SOFTWARE','USER','PROCESS')) -RandomizeOptional }
                        'Finding' { New-TestFinding -Severity (Get-Random -InputObject @('Critical','High','Medium','Low','Info')) }
                        'Incident' { New-TestIncident -Status (Get-Random -InputObject @('Active','Escalated','Resolved','Closed')) }
                    }
                }).AddArgument($DataType).AddArgument($ValidationRules)

                $powerShell.RunspacePool = $runspace

                $jobs += @{
                    PowerShell = $powerShell
                    Handle = $powerShell.BeginInvoke()
                }
            }

            foreach ($job in $jobs) {
                $results += $job.PowerShell.EndInvoke($job.Handle)
                $job.PowerShell.Dispose()
            }

            $runspace.Close()
            $runspace.Dispose()
        }
        else {
            for ($i = 0; $i -lt $Count; $i++) {
                $result = switch ($DataType) {
                    'Asset' { New-TestAsset -AssetType (Get-Random -InputObject @('DEVICE','CONTAINER','SOFTWARE','USER','PROCESS')) -RandomizeOptional }
                    'Finding' { New-TestFinding -Severity (Get-Random -InputObject @('Critical','High','Medium','Low','Info')) }
                    'Incident' { New-TestIncident -Status (Get-Random -InputObject @('Active','Escalated','Resolved','Closed')) }
                }
                $results += $result
            }
        }

        return $results
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'RandomTestDataGenerationError',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                @{DataType = $DataType; Count = $Count}
            )
        )
    }
}

# Export functions
Export-ModuleMember -Function @(
    'New-TestAsset',
    'New-TestFinding',
    'New-TestIncident',
    'Get-RandomTestData'
)