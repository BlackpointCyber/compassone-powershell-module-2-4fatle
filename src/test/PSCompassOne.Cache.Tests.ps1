#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

BeforeAll {
    # Import test helpers and initialize mock API
    . "$PSScriptRoot/helpers/TestHelpers.ps1"
    . "$PSScriptRoot/mocks/MockAPI.ps1"

    # Initialize test environment
    $script:testEnv = Initialize-TestEnvironment -TestName 'CacheTests'
    Initialize-MockApi

    # Cache configuration for tests
    $script:cacheConfig = @{
        MaxSize = 100MB
        DefaultTTL = [TimeSpan]::FromHours(1)
        CleanupInterval = [TimeSpan]::FromMinutes(5)
        CompressionThreshold = 1MB
    }

    # Platform-specific cache paths
    $script:cachePaths = @{
        Windows = "$env:LOCALAPPDATA\PSCompassOne\Cache"
        Linux = "$env:HOME/.local/share/PSCompassOne/Cache"
        MacOS = "$env:HOME/Library/Caches/PSCompassOne"
    }
}

Describe 'Cache Initialization Tests' {
    BeforeEach {
        # Clean up any existing cache files
        Get-ChildItem -Path $script:cachePaths[$script:testEnv.Platform] -ErrorAction SilentlyContinue | 
            Remove-Item -Force -Recurse
    }

    It 'Should create cache directory with correct permissions' {
        # Arrange
        $platform = $script:testEnv.Platform
        $cachePath = $script:cachePaths[$platform]

        # Act
        $result = Initialize-PSCompassOneCache -Path $cachePath -Config $script:cacheConfig

        # Assert
        $result | Should -Not -BeNullOrEmpty
        Test-Path $cachePath | Should -BeTrue

        # Platform-specific permission checks
        switch ($platform) {
            'Windows' {
                $acl = Get-Acl $cachePath
                $acl.Access | Where-Object { $_.IdentityReference -match $env:USERNAME } |
                    Select-Object -ExpandProperty FileSystemRights |
                    Should -Contain 'FullControl'
            }
            default {
                $permissions = (Get-Item $cachePath).Mode
                $permissions | Should -Match '^d.*7.*$'
            }
        }
    }

    It 'Should initialize cache with correct configuration' {
        # Arrange
        $cachePath = $script:cachePaths[$script:testEnv.Platform]

        # Act
        $cache = Initialize-PSCompassOneCache -Path $cachePath -Config $script:cacheConfig

        # Assert
        $cache.MaxSize | Should -Be $script:cacheConfig.MaxSize
        $cache.DefaultTTL | Should -Be $script:cacheConfig.DefaultTTL
        $cache.CleanupInterval | Should -Be $script:cacheConfig.CleanupInterval
        $cache.CompressionThreshold | Should -Be $script:cacheConfig.CompressionThreshold
    }

    It 'Should handle concurrent cache initialization' {
        # Arrange
        $cachePath = $script:cachePaths[$script:testEnv.Platform]
        $jobs = 1..5 | ForEach-Object {
            Start-Job -ScriptBlock {
                param($Path, $Config)
                Initialize-PSCompassOneCache -Path $Path -Config $Config
            } -ArgumentList $cachePath, $script:cacheConfig
        }

        # Act
        $results = $jobs | Wait-Job | Receive-Job

        # Assert
        $results.Count | Should -Be 5
        $results | ForEach-Object {
            $_.Path | Should -Be $cachePath
            $_.IsInitialized | Should -BeTrue
        }
    }
}

Describe 'Cache Operations Tests' {
    BeforeAll {
        $script:cache = Initialize-PSCompassOneCache -Path $script:cachePaths[$script:testEnv.Platform] -Config $script:cacheConfig
    }

    It 'Should store and retrieve cache items correctly' {
        # Arrange
        $key = "test-key-$(New-Guid)"
        $value = @{
            data = "test-data"
            timestamp = Get-Date
        }

        # Act
        $script:cache.Set($key, $value)
        $result = $script:cache.Get($key)

        # Assert
        $result | Should -Not -BeNullOrEmpty
        $result.data | Should -Be $value.data
        $result.timestamp | Should -Be $value.timestamp
    }

    It 'Should compress large cache items' {
        # Arrange
        $key = "large-item-$(New-Guid)"
        $value = @{
            data = "x" * (2MB)
            timestamp = Get-Date
        }

        # Act
        $script:cache.Set($key, $value)
        $cacheFile = Join-Path $script:cache.Path "$key.cache"

        # Assert
        (Get-Item $cacheFile).Length | Should -BeLessThan (2MB)
        $result = $script:cache.Get($key)
        $result.data.Length | Should -Be $value.data.Length
    }

    It 'Should handle concurrent cache access' {
        # Arrange
        $key = "concurrent-test-$(New-Guid)"
        $value = "test-value"
        $jobs = 1..10 | ForEach-Object {
            Start-Job -ScriptBlock {
                param($Key, $Value, $CachePath, $Config)
                $cache = Initialize-PSCompassOneCache -Path $CachePath -Config $Config
                $cache.Set($Key, $Value)
                $cache.Get($Key)
            } -ArgumentList $key, $value, $script:cachePaths[$script:testEnv.Platform], $script:cacheConfig
        }

        # Act
        $results = $jobs | Wait-Job | Receive-Job

        # Assert
        $results | Should -Not -ContainNullOrEmpty
        $results | Should -Contain $value
    }
}

Describe 'Cache Expiration Tests' {
    BeforeAll {
        $script:cache = Initialize-PSCompassOneCache -Path $script:cachePaths[$script:testEnv.Platform] -Config $script:cacheConfig
    }

    It 'Should expire items after TTL' {
        # Arrange
        $key = "expiring-item-$(New-Guid)"
        $value = "test-value"
        $ttl = [TimeSpan]::FromSeconds(1)

        # Act
        $script:cache.Set($key, $value, $ttl)
        Start-Sleep -Seconds 2
        $result = $script:cache.Get($key)

        # Assert
        $result | Should -BeNullOrEmpty
    }

    It 'Should perform background cleanup of expired items' {
        # Arrange
        1..10 | ForEach-Object {
            $key = "cleanup-test-$_"
            $script:cache.Set($key, "value-$_", [TimeSpan]::FromSeconds(1))
        }

        # Act
        Start-Sleep -Seconds 2
        $script:cache.RunCleanup()
        $remainingFiles = Get-ChildItem -Path $script:cache.Path -Filter "cleanup-test-*.cache"

        # Assert
        $remainingFiles.Count | Should -Be 0
    }

    It 'Should maintain cache size within limits' {
        # Arrange
        $originalMaxSize = $script:cache.MaxSize
        $script:cache.MaxSize = 5MB

        # Act
        1..100 | ForEach-Object {
            $key = "size-test-$_"
            $value = "x" * (100KB)
            $script:cache.Set($key, $value)
        }

        # Assert
        $cacheSize = (Get-ChildItem $script:cache.Path -Recurse | Measure-Object -Property Length -Sum).Sum
        $cacheSize | Should -BeLessThan $script:cache.MaxSize

        # Cleanup
        $script:cache.MaxSize = $originalMaxSize
    }
}

Describe 'Cache Performance Tests' {
    BeforeAll {
        $script:cache = Initialize-PSCompassOneCache -Path $script:cachePaths[$script:testEnv.Platform] -Config $script:cacheConfig
    }

    It 'Should maintain hit ratio above 80%' {
        # Arrange
        $iterations = 1000
        $hitCount = 0
        $keys = 1..10 | ForEach-Object { "perf-test-$_" }
        $keys | ForEach-Object { $script:cache.Set($_, "value-$_") }

        # Act
        1..$iterations | ForEach-Object {
            $key = $keys | Get-Random
            if ($script:cache.Get($key)) {
                $hitCount++
            }
        }

        # Assert
        $hitRatio = $hitCount / $iterations
        $hitRatio | Should -BeGreaterThan 0.8
    }

    It 'Should handle high concurrency without errors' {
        # Arrange
        $errorCount = 0
        $jobs = 1..50 | ForEach-Object {
            Start-Job -ScriptBlock {
                param($CachePath, $Config)
                try {
                    $cache = Initialize-PSCompassOneCache -Path $CachePath -Config $Config
                    1..100 | ForEach-Object {
                        $key = "concurrent-$_"
                        $cache.Set($key, "value-$_")
                        $cache.Get($key)
                    }
                    return $true
                }
                catch {
                    return $false
                }
            } -ArgumentList $script:cachePaths[$script:testEnv.Platform], $script:cacheConfig
        }

        # Act
        $results = $jobs | Wait-Job | Receive-Job

        # Assert
        $results | Where-Object { -not $_ } | Measure-Object | Select-Object -ExpandProperty Count |
            Should -Be 0
    }
}

AfterAll {
    # Cleanup test environment
    Get-ChildItem -Path $script:cachePaths[$script:testEnv.Platform] -ErrorAction SilentlyContinue |
        Remove-Item -Force -Recurse
}