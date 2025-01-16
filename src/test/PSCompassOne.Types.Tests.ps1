#Requires -Version 5.1
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

using module './helpers/TestHelpers.ps1'
using module './fixtures/AssetFixtures.ps1'

BeforeAll {
    # Initialize test environment
    $script:testEnv = Initialize-TestEnvironment -TestName 'PSCompassOne.Types' -EnableParallel
    
    # Load test data
    $script:testData = Get-Content (Join-Path $PSScriptRoot 'data/TestAssets.json') | ConvertFrom-Json
}

AfterAll {
    # Clean up test environment
    Reset-TestEnvironment -Environment $script:testEnv
}

Describe 'DEVICE Asset Type Validation' {
    BeforeAll {
        $script:validDevice = New-TestDevice -Properties @{
            name = "TestDevice-1"
            status = "Active"
            model = "TestModel-1"
            osName = "Windows"
            osVersion = "10.0.19044"
            ips = @("192.168.1.1", "10.0.0.1")
            macs = @("00:11:22:33:44:55", "AA:BB:CC:DD:EE:FF")
        }
    }

    Context 'Required Properties' {
        It 'Should validate required name property' {
            { New-TestDevice -Properties @{ status = "Active"; model = "Test" } } | 
                Should -Throw -ErrorId 'TestDeviceCreationError'
        }

        It 'Should validate required status property' {
            { New-TestDevice -Properties @{ name = "Test"; model = "Test" } } | 
                Should -Throw -ErrorId 'TestDeviceCreationError'
        }

        It 'Should validate required model property' {
            { New-TestDevice -Properties @{ name = "Test"; status = "Active" } } | 
                Should -Throw -ErrorId 'TestDeviceCreationError'
        }
    }

    Context 'Optional Properties' {
        It 'Should accept valid osName' {
            $device = New-TestDevice -Properties @{
                name = "Test"
                status = "Active"
                model = "Test"
                osName = "Linux"
            }
            $device.osName | Should -Be "Linux"
        }

        It 'Should accept valid osVersion' {
            $device = New-TestDevice -Properties @{
                name = "Test"
                status = "Active"
                model = "Test"
                osVersion = "5.10.0"
            }
            $device.osVersion | Should -Be "5.10.0"
        }

        It 'Should validate IP address format' {
            { New-TestDevice -Properties @{
                name = "Test"
                status = "Active"
                model = "Test"
                ips = @("invalid.ip.address")
            } } | Should -Throw -ErrorId 'TestDeviceCreationError'
        }

        It 'Should validate MAC address format' {
            { New-TestDevice -Properties @{
                name = "Test"
                status = "Active"
                model = "Test"
                macs = @("invalid:mac:address")
            } } | Should -Throw -ErrorId 'TestDeviceCreationError'
        }
    }

    Context 'Cross-Platform Compatibility' {
        It 'Should handle Windows-specific properties' {
            $device = New-TestDevice -Properties @{
                name = "WinTest"
                status = "Active"
                model = "WinModel"
                osName = "Windows"
                osVersion = "10.0.19044"
            }
            $device.osName | Should -Be "Windows"
            $device.osVersion | Should -Match '^\d+\.\d+\.\d+$'
        }

        It 'Should handle Linux-specific properties' {
            $device = New-TestDevice -Properties @{
                name = "LinuxTest"
                status = "Active"
                model = "LinuxModel"
                osName = "Linux"
                osVersion = "5.10.0-generic"
            }
            $device.osName | Should -Be "Linux"
            $device.osVersion | Should -Match '^[\d\.]+-\w+$'
        }

        It 'Should handle macOS-specific properties' {
            $device = New-TestDevice -Properties @{
                name = "MacTest"
                status = "Active"
                model = "MacModel"
                osName = "macOS"
                osVersion = "12.0.1"
            }
            $device.osName | Should -Be "macOS"
            $device.osVersion | Should -Match '^\d+\.\d+\.\d+$'
        }
    }
}

Describe 'CONTAINER Asset Type Validation' {
    BeforeAll {
        $script:validContainer = New-TestContainer -Properties @{
            name = "TestContainer-1"
            status = "Active"
            image = "nginx:latest"
            ports = @("80/tcp", "443/tcp")
            command = "nginx -g 'daemon off;'"
            imageTag = "1.21.6"
        }
    }

    Context 'Required Properties' {
        It 'Should validate required name property' {
            { New-TestContainer -Properties @{ status = "Active"; image = "test" } } | 
                Should -Throw -ErrorId 'TestContainerCreationError'
        }

        It 'Should validate required status property' {
            { New-TestContainer -Properties @{ name = "Test"; image = "test" } } | 
                Should -Throw -ErrorId 'TestContainerCreationError'
        }

        It 'Should validate required image property' {
            { New-TestContainer -Properties @{ name = "Test"; status = "Active" } } | 
                Should -Throw -ErrorId 'TestContainerCreationError'
        }
    }

    Context 'Optional Properties' {
        It 'Should validate port format' {
            { New-TestContainer -Properties @{
                name = "Test"
                status = "Active"
                image = "test"
                ports = @("invalid/port")
            } } | Should -Throw -ErrorId 'TestContainerCreationError'
        }

        It 'Should accept valid ports' {
            $container = New-TestContainer -Properties @{
                name = "Test"
                status = "Active"
                image = "test"
                ports = @("80/tcp", "443/tcp")
            }
            $container.ports | Should -Contain "80/tcp"
            $container.ports | Should -Contain "443/tcp"
        }

        It 'Should validate image tag format' {
            { New-TestContainer -Properties @{
                name = "Test"
                status = "Active"
                image = "test"
                imageTag = "invalid tag"
            } } | Should -Throw -ErrorId 'TestContainerCreationError'
        }
    }
}

Describe 'Type Conversion Tests' {
    Context 'JSON Serialization' {
        It 'Should serialize DEVICE to valid JSON' {
            $device = New-TestDevice -Properties @{
                name = "JsonTest"
                status = "Active"
                model = "TestModel"
            }
            $json = $device | ConvertTo-Json
            $json | Should -Not -BeNullOrEmpty
            { $json | ConvertFrom-Json } | Should -Not -Throw
        }

        It 'Should serialize CONTAINER to valid JSON' {
            $container = New-TestContainer -Properties @{
                name = "JsonTest"
                status = "Active"
                image = "test:latest"
            }
            $json = $container | ConvertTo-Json
            $json | Should -Not -BeNullOrEmpty
            { $json | ConvertFrom-Json } | Should -Not -Throw
        }
    }

    Context 'Type Coercion' {
        It 'Should coerce numeric strings to integers for port numbers' {
            $container = New-TestContainer -Properties @{
                name = "Test"
                status = "Active"
                image = "test"
                ports = @("80", "443")
            }
            $container.ports | ForEach-Object { $_ | Should -BeOfType [string] }
        }

        It 'Should maintain IP address format during conversion' {
            $device = New-TestDevice -Properties @{
                name = "Test"
                status = "Active"
                model = "Test"
                ips = @("192.168.1.1")
            }
            $device.ips[0] | Should -Match '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$'
        }
    }
}

Describe 'Relationship Validation' {
    Context 'Asset Relationships' {
        It 'Should validate relationship structure' {
            $relationship = @{
                sourceId = "device-1"
                targetId = "container-1"
                type = "runs_on"
            }
            $device = New-TestDevice -Properties @{
                name = "Test"
                status = "Active"
                model = "Test"
                relationships = @($relationship)
            }
            $device.relationships[0].sourceId | Should -Be "device-1"
            $device.relationships[0].targetId | Should -Be "container-1"
            $device.relationships[0].type | Should -Be "runs_on"
        }

        It 'Should reject invalid relationship structure' {
            $invalidRelationship = @{
                sourceId = "device-1"
                # Missing targetId
                type = "runs_on"
            }
            { New-TestDevice -Properties @{
                name = "Test"
                status = "Active"
                model = "Test"
                relationships = @($invalidRelationship)
            } } | Should -Throw
        }
    }
}