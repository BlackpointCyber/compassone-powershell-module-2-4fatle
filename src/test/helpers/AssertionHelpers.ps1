#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

# Import test configuration
$TestConfig = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot '../config/test-config.psd1')

# Asset validation functions
function Assert-AssetProperties {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSObject]$Asset,

        [Parameter(Mandatory = $true)]
        [ValidateSet('DEVICE', 'CONTAINER', 'SOFTWARE', 'USER', 'PROCESS')]
        [string]$AssetType,

        [Parameter(Mandatory = $false)]
        [hashtable]$ValidationOptions = @{}
    )

    try {
        # Verify asset is not null
        if ($null -eq $Asset) {
            throw [System.ArgumentNullException]::new('Asset', 'Asset object cannot be null')
        }

        # Verify asset is a PSObject
        if ($Asset -isnot [PSObject]) {
            throw [System.ArgumentException]::new('Asset must be a PSObject', 'Asset')
        }

        # Get required properties for asset type
        $requiredProps = $TestConfig.RequiredProperties[$AssetType]
        if (-not $requiredProps) {
            throw [System.ArgumentException]::new("Invalid asset type: $AssetType", 'AssetType')
        }

        # Validate required properties
        foreach ($prop in $requiredProps) {
            if (-not $Asset.PSObject.Properties.Name.Contains($prop)) {
                throw [System.ArgumentException]::new("Missing required property: $prop for asset type: $AssetType")
            }

            # Validate property is not null or empty
            if ([string]::IsNullOrWhiteSpace($Asset.$prop)) {
                throw [System.ArgumentException]::new("Required property cannot be null or empty: $prop")
            }
        }

        # Validate optional properties if present
        $optionalProps = $TestConfig.OptionalProperties[$AssetType]
        foreach ($prop in $Asset.PSObject.Properties.Name) {
            if ($prop -notin $requiredProps -and $prop -notin $optionalProps) {
                throw [System.ArgumentException]::new("Unknown property for asset type $AssetType`: $prop")
            }
        }

        # Apply custom validation rules
        if ($TestConfig.ValidationRules[$AssetType]) {
            foreach ($rule in $TestConfig.ValidationRules[$AssetType]) {
                $result = & $rule $Asset
                if (-not $result) {
                    throw [System.ArgumentException]::new("Validation rule failed for asset type $AssetType`: $($rule.ToString())")
                }
            }
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'AssetValidationError',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $Asset
            )
        )
    }
}

function Assert-ApiResponse {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSObject]$Response,

        [Parameter(Mandatory = $true)]
        [ValidateRange(100, 599)]
        [int]$ExpectedStatusCode,

        [Parameter(Mandatory = $false)]
        [hashtable]$ExpectedHeaders = @{}
    )

    try {
        # Verify response object
        if ($null -eq $Response) {
            throw [System.ArgumentNullException]::new('Response', 'Response object cannot be null')
        }

        # Validate status code
        if ($Response.StatusCode -ne $ExpectedStatusCode) {
            throw [System.ArgumentException]::new(
                "Expected status code $ExpectedStatusCode but got $($Response.StatusCode)",
                'ExpectedStatusCode'
            )
        }

        # Validate required headers
        foreach ($header in $ExpectedHeaders.Keys) {
            if (-not $Response.Headers.Contains($header)) {
                throw [System.ArgumentException]::new("Missing required header: $header")
            }
            if ($Response.Headers[$header] -ne $ExpectedHeaders[$header]) {
                throw [System.ArgumentException]::new(
                    "Header value mismatch for $header. Expected: $($ExpectedHeaders[$header]), Got: $($Response.Headers[$header])"
                )
            }
        }

        # Validate response content
        if ($Response.Content -and -not [string]::IsNullOrEmpty($Response.Content)) {
            if ($Response.Headers['Content-Type'] -match 'application/json') {
                try {
                    $null = $Response.Content | ConvertFrom-Json
                }
                catch {
                    throw [System.ArgumentException]::new('Invalid JSON content in response')
                }
            }
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'ApiResponseValidationError',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $Response
            )
        )
    }
}

function Assert-ObjectEquality {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSObject]$Expected,

        [Parameter(Mandatory = $true)]
        [PSObject]$Actual,

        [Parameter(Mandatory = $false)]
        [hashtable]$ComparisonOptions = @{}
    )

    try {
        # Verify objects are not null
        if ($null -eq $Expected) {
            throw [System.ArgumentNullException]::new('Expected', 'Expected object cannot be null')
        }
        if ($null -eq $Actual) {
            throw [System.ArgumentNullException]::new('Actual', 'Actual object cannot be null')
        }

        # Compare object types
        if ($Expected.GetType() -ne $Actual.GetType()) {
            throw [System.ArgumentException]::new(
                "Type mismatch. Expected: $($Expected.GetType().Name), Actual: $($Actual.GetType().Name)"
            )
        }

        # Compare properties
        $expectedProps = $Expected.PSObject.Properties
        $actualProps = $Actual.PSObject.Properties

        if ($expectedProps.Count -ne $actualProps.Count) {
            throw [System.ArgumentException]::new(
                "Property count mismatch. Expected: $($expectedProps.Count), Actual: $($actualProps.Count)"
            )
        }

        foreach ($prop in $expectedProps) {
            if (-not $actualProps[$prop.Name]) {
                throw [System.ArgumentException]::new("Missing property in actual object: $($prop.Name)")
            }

            # Handle nested objects recursively
            if ($prop.Value -is [PSObject] -and $actualProps[$prop.Name].Value -is [PSObject]) {
                Assert-ObjectEquality -Expected $prop.Value -Actual $actualProps[$prop.Name].Value -ComparisonOptions $ComparisonOptions
            }
            elseif ($prop.Value -ne $actualProps[$prop.Name].Value) {
                throw [System.ArgumentException]::new(
                    "Value mismatch for property $($prop.Name). Expected: $($prop.Value), Actual: $($actualProps[$prop.Name].Value)"
                )
            }
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'ObjectEqualityError',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                @{Expected = $Expected; Actual = $Actual}
            )
        )
    }
}

function Assert-ErrorResponse {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$Error,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedErrorId,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorCategory]$ExpectedCategory
    )

    try {
        # Verify error record
        if ($null -eq $Error) {
            throw [System.ArgumentNullException]::new('Error', 'Error record cannot be null')
        }

        # Validate error ID
        if ($Error.FullyQualifiedErrorId -notmatch $ExpectedErrorId) {
            throw [System.ArgumentException]::new(
                "Error ID mismatch. Expected: $ExpectedErrorId, Actual: $($Error.FullyQualifiedErrorId)",
                'ExpectedErrorId'
            )
        }

        # Validate error category
        if ($Error.CategoryInfo.Category -ne $ExpectedCategory) {
            throw [System.ArgumentException]::new(
                "Error category mismatch. Expected: $ExpectedCategory, Actual: $($Error.CategoryInfo.Category)",
                'ExpectedCategory'
            )
        }

        # Validate error has message
        if ([string]::IsNullOrWhiteSpace($Error.Exception.Message)) {
            throw [System.ArgumentException]::new('Error message cannot be empty')
        }

        # Validate exception type
        if ($null -eq $Error.Exception) {
            throw [System.ArgumentException]::new('Error must contain an exception')
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'ErrorValidationFailed',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $Error
            )
        )
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Assert-AssetProperties',
    'Assert-ApiResponse',
    'Assert-ObjectEquality',
    'Assert-ErrorResponse'
)