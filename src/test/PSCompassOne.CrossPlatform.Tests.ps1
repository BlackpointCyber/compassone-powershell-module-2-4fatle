#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

# Import required test helpers and configuration
. "$PSScriptRoot/helpers/TestHelpers.ps1"
Import-Module "$PSScriptRoot/mocks/MockAPI.ps1"

Describe 'PSCompassOne Cross-Platform Compatibility Tests' {
    BeforeAll {
        # Initialize test environment with platform-specific settings
        $script:testEnv = Initialize-TestEnvironment -TestName 'CrossPlatformTests' -UseMockData
        
        # Initialize mock API for testing
        Initialize-MockApi

        # Platform-specific paths for testing
        $script:platformPaths = @{
            Windows = @{
                ConfigPath = "$env:APPDATA\PSCompassOne"
                CachePath = "$env:TEMP\PSCompassOne"
                LogPath = "$env:APPDATA\PSCompassOne\Logs"
            }
            Linux = @{
                ConfigPath = "$env:HOME/.config/PSCompassOne"
                CachePath = "/tmp/PSCompassOne"
                LogPath = "$env:HOME/.local/share/PSCompassOne/logs"
            }
            MacOS = @{
                ConfigPath = "$env:HOME/Library/Application Support/PSCompassOne"
                CachePath = "/tmp/PSCompassOne"
                LogPath = "$env:HOME/Library/Logs/PSCompassOne"
            }
        }

        # Determine current platform
        $script:currentPlatform = if ($IsWindows) { 'Windows' } elseif ($IsLinux) { 'Linux' } else { 'MacOS' }
        $script:paths = $platformPaths[$currentPlatform]
    }

    Context 'Platform Detection and Configuration' {
        It 'Should correctly identify the current platform' {
            $detected = if ($IsWindows) { 'Windows' } elseif ($IsLinux) { 'Linux' } else { 'MacOS' }
            $detected | Should -Be $currentPlatform
        }

        It 'Should use platform-appropriate path separators' {
            $separator = [System.IO.Path]::DirectorySeparatorChar
            $expectedSeparator = if ($IsWindows) { '\' } else { '/' }
            $separator | Should -Be $expectedSeparator
        }

        It 'Should use platform-appropriate line endings' {
            $lineEnding = [System.Environment]::NewLine
            $expectedEnding = if ($IsWindows) { "`r`n" } else { "`n" }
            $lineEnding | Should -Be $expectedEnding
        }
    }

    Context 'File System Operations' {
        BeforeAll {
            # Create test directories
            $script:testPaths = @(
                $paths.ConfigPath,
                $paths.CachePath,
                $paths.LogPath
            )
            
            foreach ($path in $testPaths) {
                if (-not (Test-Path $path)) {
                    New-Item -Path $path -ItemType Directory -Force
                }
            }
        }

        It 'Should create and access configuration directory' {
            Test-Path $paths.ConfigPath | Should -BeTrue
            $configFile = Join-Path $paths.ConfigPath 'settings.json'
            Set-Content -Path $configFile -Value '{"test": true}'
            Test-Path $configFile | Should -BeTrue
            $content = Get-Content $configFile -Raw | ConvertFrom-Json
            $content.test | Should -BeTrue
        }

        It 'Should handle file permissions correctly' {
            $testFile = Join-Path $paths.ConfigPath 'permissions-test.txt'
            Set-Content -Path $testFile -Value 'test'
            
            if (-not $IsWindows) {
                # Set Unix-style permissions
                chmod 600 $testFile
                $mode = (Get-Item $testFile).Mode
                $mode | Should -Match '^-rw-------'
            } else {
                # Verify Windows ACLs
                $acl = Get-Acl $testFile
                $acl.Access.Count | Should -BeGreaterThan 0
            }
        }

        It 'Should handle long paths appropriately' {
            $longPath = Join-Path $paths.CachePath ('a' * 100)
            
            if ($IsWindows) {
                # Windows requires long path support
                $longPathEnabled = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -ErrorAction SilentlyContinue).LongPathsEnabled
                if (-not $longPathEnabled) {
                    Set-ItResult -Skipped -Because 'Long path support not enabled on Windows'
                    return
                }
            }

            New-Item -Path $longPath -ItemType Directory -Force
            Test-Path $longPath | Should -BeTrue
        }

        AfterAll {
            # Cleanup test files
            foreach ($path in $testPaths) {
                if (Test-Path $path) {
                    Remove-Item -Path $path -Recurse -Force
                }
            }
        }
    }

    Context 'Storage Operations' {
        BeforeAll {
            $script:testStoragePath = Join-Path $paths.CachePath 'test-storage'
            New-Item -Path $testStoragePath -ItemType Directory -Force
        }

        It 'Should handle platform-specific storage locations' {
            $result = Test-CrossPlatformStorage -StoragePath $testStoragePath -StorageOptions @{
                CreateSubfolders = $true
                TestFileOperations = $true
            }
            $result | Should -BeTrue
        }

        It 'Should handle file locking correctly' {
            $lockFile = Join-Path $testStoragePath 'lock-test.txt'
            $fileStream = $null
            
            try {
                # Create file with exclusive lock
                $fileStream = [System.IO.File]::Open(
                    $lockFile,
                    [System.IO.FileMode]::Create,
                    [System.IO.FileAccess]::ReadWrite,
                    [System.IO.FileShare]::None
                )

                # Attempt to access locked file
                $canAccess = Test-CrossPlatformPaths -TestPath $lockFile -PathOptions @{
                    CheckLocking = $true
                }
                $canAccess | Should -BeFalse
            }
            finally {
                if ($fileStream) {
                    $fileStream.Close()
                    $fileStream.Dispose()
                }
            }
        }

        It 'Should handle concurrent file access' {
            $concurrentFile = Join-Path $testStoragePath 'concurrent-test.txt'
            Set-Content -Path $concurrentFile -Value 'initial'

            $jobs = 1..3 | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($path)
                    Add-Content -Path $path -Value "append-$_"
                } -ArgumentList $concurrentFile
            }

            $jobs | Wait-Job | Receive-Job
            $content = Get-Content $concurrentFile
            $content.Count | Should -BeGreaterThan 1
        }

        AfterAll {
            if (Test-Path $testStoragePath) {
                Remove-Item -Path $testStoragePath -Recurse -Force
            }
        }
    }

    Context 'API Integration' {
        It 'Should handle platform-specific network configurations' {
            # Test proxy settings if configured
            $proxyEnabled = [System.Net.WebRequest]::DefaultWebProxy.IsBypassed("http://localhost") -eq $false
            if ($proxyEnabled) {
                $env:HTTPS_PROXY | Should -Not -BeNullOrEmpty
            }

            # Test SSL/TLS configuration
            $securityProtocol = [System.Net.ServicePointManager]::SecurityProtocol
            $securityProtocol | Should -Match 'Tls12|Tls13'
        }

        It 'Should handle platform-specific SSL certificate validation' {
            # Mock certificate validation
            $certValidation = {
                param($sender, $cert, $chain, $errors)
                return $true
            }

            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $certValidation
            
            try {
                $response = Invoke-RestMethod -Uri $testEnv.ApiEndpoint -Method Get
                $response | Should -Not -BeNullOrEmpty
            }
            finally {
                # Reset certificate validation
                [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $null
            }
        }

        It 'Should handle platform-specific connection pooling' {
            # Test connection pooling settings
            $maxConnections = [System.Net.ServicePointManager]::DefaultConnectionLimit
            $maxConnections | Should -BeGreaterThan 1

            # Verify connection reuse
            1..3 | ForEach-Object {
                $response = Invoke-RestMethod -Uri $testEnv.ApiEndpoint -Method Get
                $response | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Error Handling' {
        It 'Should handle platform-specific error messages' {
            $errorFile = Join-Path $paths.LogPath 'error-test.log'
            
            try {
                throw [System.IO.FileNotFoundException]::new(
                    "File not found: $errorFile",
                    $errorFile
                )
            }
            catch {
                $_.Exception.Message | Should -Match $(
                    if ($IsWindows) {
                        'File not found:'
                    } else {
                        'No such file'
                    }
                )
            }
        }

        It 'Should log errors with platform-appropriate format' {
            $errorLog = Join-Path $paths.LogPath 'test-errors.log'
            
            try {
                throw 'Test error'
            }
            catch {
                $timestamp = Get-Date -Format $(
                    if ($IsWindows) {
                        'MM/dd/yyyy HH:mm:ss'
                    } else {
                        'yyyy-MM-dd HH:mm:ss'
                    }
                )
                Add-Content -Path $errorLog -Value "[$timestamp] $_"
            }

            Test-Path $errorLog | Should -BeTrue
            $logContent = Get-Content $errorLog -Raw
            $logContent | Should -Match $(
                if ($IsWindows) {
                    '\[\d{2}/\d{2}/\d{4}'
                } else {
                    '\[\d{4}-\d{2}-\d{2}'
                }
            )
        }
    }

    AfterAll {
        # Cleanup test environment
        foreach ($path in $testPaths) {
            if (Test-Path $path) {
                Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}