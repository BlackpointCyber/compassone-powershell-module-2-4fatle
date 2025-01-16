# Microsoft.PowerShell.Security - Built-in
# Microsoft.PowerShell.SecretStore - v1.0.0

@{
    TestCredentials = @{
        # Secure API credentials
        ApiKey = [System.Security.SecureString]::new()
        ApiSecret = [System.Security.SecureString]::new()

        # Test user credentials
        TestUserName = ''
        TestPassword = [System.Security.SecureString]::new()

        # API token management
        TestApiToken = [System.Security.SecureString]::new()
        TokenExpiry = [DateTime]::new()

        # SecretStore configuration
        SecretStorePath = [System.IO.Path]::Combine($ENV:LOCALAPPDATA, 'PSCompassOne', 'SecretStore')
        SecretStorePassword = [System.Security.SecureString]::new()

        # Credential validation scriptblock
        CredentialValidation = {
            param(
                [Parameter(Mandatory)]
                [System.Security.SecureString]$cred
            )
            
            if (!$cred -or $cred.Length -eq 0) {
                throw 'Invalid credential'
            }
        }

        # Token expiry validation scriptblock
        TokenExpiryCheck = {
            param(
                [Parameter(Mandatory)]
                [DateTime]$expiry
            )
            
            if ($expiry -le [DateTime]::Now) {
                throw 'Token expired'
            }
        }
    }
}