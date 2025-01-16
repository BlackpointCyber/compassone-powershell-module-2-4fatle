# PSCompassOne Testing Framework

## Overview

The PSCompassOne testing framework provides comprehensive test coverage for the PSCompassOne PowerShell module, ensuring reliability, security, and performance across all supported platforms. This framework implements industry best practices for PowerShell module testing and maintains high-quality standards for enterprise-grade software.

### Testing Philosophy
- Test-Driven Development (TDD) approach
- Comprehensive coverage across all module features
- Security-first testing methodology
- Cross-platform validation
- Performance benchmarking

### Quality Standards
- Minimum 90% code coverage
- All critical paths tested
- Security compliance validation
- Cross-platform compatibility
- Performance within defined SLAs

## Test Environment Setup

### Prerequisites

#### Required Software
- PowerShell 7.x (recommended) or PowerShell 5.1
- Pester 5.0.0+
- PSScriptAnalyzer 1.20.0+
- Git

#### Development Tools
- Visual Studio Code with PowerShell extension
- PowerShell SecretStore module
- platyPS for documentation testing

### Platform-Specific Setup

#### Windows
```powershell
# Install required modules
Install-Module -Name Pester -MinimumVersion 5.0.0 -Force
Install-Module -Name PSScriptAnalyzer -MinimumVersion 1.20.0 -Force
Install-Module -Name Microsoft.PowerShell.SecretStore -MinimumVersion 1.0.0 -Force
```

#### Linux/macOS
```bash
# Install PowerShell 7.x
# Follow platform-specific installation from Microsoft docs

# Install required modules
pwsh -Command "Install-Module -Name Pester -MinimumVersion 5.0.0 -Force"
pwsh -Command "Install-Module -Name PSScriptAnalyzer -MinimumVersion 1.20.0 -Force"
pwsh -Command "Install-Module -Name Microsoft.PowerShell.SecretStore -MinimumVersion 1.0.0 -Force"
```

### Configuration
- Test configuration: `config/test-config.psd1`
- Credentials: `config/test-credentials.psd1`
- Environment settings: `config/test-environment.psd1`

## Running Tests

### Test Categories

#### Unit Tests
```powershell
Invoke-Pester -Path "PSCompassOne.Types.Tests.ps1"
```

#### Integration Tests
```powershell
Invoke-Pester -Path "PSCompassOne.Integration.Tests.ps1"
```

#### Security Tests
```powershell
Invoke-Pester -Path "PSCompassOne.Security.Tests.ps1"
```

#### Performance Tests
```powershell
Invoke-Pester -Path "PSCompassOne.Performance.Tests.ps1"
```

### Running All Tests
```powershell
# Run all tests with default configuration
./Run-AllTests.ps1

# Run with custom configuration
./Run-AllTests.ps1 -ConfigPath "./custom-config.psd1"
```

## Test Structure

### Directory Layout
```
src/test/
├── config/
│   ├── test-config.psd1
│   ├── test-credentials.psd1
│   └── test-environment.psd1
├── data/
│   ├── TestAssets.json
│   ├── TestFindings.json
│   ├── TestIncidents.json
│   └── TestRelationships.json
├── PSCompassOne.Types.Tests.ps1
├── PSCompassOne.API.Tests.ps1
├── PSCompassOne.Authentication.Tests.ps1
├── PSCompassOne.Integration.Tests.ps1
├── PSCompassOne.Security.Tests.ps1
└── PSCompassOne.Performance.Tests.ps1
```

### Test Patterns
- One test file per module component
- Consistent naming convention
- Hierarchical test organization
- Shared test fixtures
- Mock data separation

## Contributing Tests

### Guidelines
1. Follow existing test patterns
2. Include comprehensive test cases
3. Implement proper mocking
4. Add detailed test documentation
5. Ensure cross-platform compatibility

### Code Review Process
1. Static analysis compliance
2. Code coverage requirements
3. Performance impact assessment
4. Security validation
5. Documentation review

## Test Data Management

### Test Data Sources
- Mock data files in `data/` directory
- Dynamic data generation
- Sanitized production data samples

### Data Security
- No sensitive data in tests
- Secure credential handling
- Data encryption validation
- Access control testing

## Mocking Framework

### API Mocking
```powershell
# Example API mock
Mock Invoke-RestMethod {
    return @{
        status = "success"
        data = Get-Content ".\data\TestAssets.json" | ConvertFrom-Json
    }
}
```

### Credential Mocking
```powershell
# Example credential mock
Mock Get-Secret {
    return @{
        ApiKey = "TEST-API-KEY"
        Token = "TEST-TOKEN"
    }
}
```

## CI/CD Integration

### GitHub Actions Workflow
```yaml
name: Test Pipeline
on: [push, pull_request]
jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [windows-latest, ubuntu-latest, macos-latest]
    steps:
      - uses: actions/checkout@v2
      - name: Run Tests
        run: ./Run-AllTests.ps1
```

### Test Reports
- JUnit XML output
- Code coverage reports
- Performance metrics
- Security scan results

## Security Testing

### Areas Covered
- Authentication mechanisms
- Authorization controls
- Data encryption
- Secure communication
- Credential handling
- Audit logging

### Security Validation
```powershell
# Example security test
Describe "Security Controls" {
    It "Validates TLS requirements" {
        $result = Test-TLSConfiguration
        $result.MinimumTLSVersion | Should -Be "1.2"
    }
}
```

## Performance Testing

### Benchmarks
- Command execution time
- Memory usage
- API response time
- Bulk operation performance

### Performance Tests
```powershell
# Example performance test
Describe "Performance Requirements" {
    It "Completes within SLA" {
        $result = Measure-Command { Get-PSCompassOneAsset }
        $result.TotalMilliseconds | Should -BeLessThan 2000
    }
}
```

## Troubleshooting

### Common Issues
1. Test environment setup problems
2. Mock data inconsistencies
3. Platform-specific failures
4. Performance test variability

### Debug Procedures
1. Enable verbose logging
2. Check test configuration
3. Validate mock data
4. Review error logs

## Test Reports

### Report Types
- Test execution summary
- Code coverage analysis
- Performance metrics
- Security scan results

### Report Location
```
src/test/reports/
├── coverage/
├── performance/
├── security/
└── summary/
```

### Metrics Collection
- Test pass/fail rates
- Code coverage percentage
- Performance benchmarks
- Security compliance status

## Support

### Resources
- [PSCompassOne Documentation](../docs/README.md)
- [PowerShell Testing Guide](https://pester.dev)
- [Security Testing Guidelines](../docs/security/README.md)

### Contact
- GitHub Issues
- Development Team
- Security Team