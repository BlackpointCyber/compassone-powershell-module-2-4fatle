# Contributing to PSCompassOne

## Table of Contents
- [Introduction](#introduction)
- [Quick Start Guide](#quick-start-guide)
- [Development Environment Setup](#development-environment-setup)
- [Security Requirements](#security-requirements)
- [Coding Standards](#coding-standards)
- [Testing Requirements](#testing-requirements)
- [Pull Request Process](#pull-request-process)
- [Issue Guidelines](#issue-guidelines)
- [Code Review Process](#code-review-process)
- [Release Process](#release-process)
- [Troubleshooting](#troubleshooting)
- [Community Guidelines](#community-guidelines)

## Introduction

PSCompassOne is a security-focused PowerShell module providing enterprise-grade integration with Blackpoint's CompassOne cybersecurity platform. Our development process emphasizes:

- Security-first approach
- Enterprise-ready code quality
- Compliance with industry standards
- Comprehensive testing
- Detailed documentation

## Quick Start Guide

1. **Fork and Clone**
   ```powershell
   git clone https://github.com/yourusername/PSCompassOne.git
   cd PSCompassOne
   ```

2. **Install Prerequisites**
   ```powershell
   Install-Module -Name PSScriptAnalyzer -RequiredVersion 1.20.0 -Force
   Install-Module -Name Pester -RequiredVersion 5.0.0 -Force
   Install-Module -Name platyPS -RequiredVersion 2.0.0 -Force
   Install-Module -Name Microsoft.PowerShell.SecretStore -RequiredVersion 1.0.0 -Force
   ```

3. **Configure Development Environment**
   ```powershell
   ./build/setup-dev-environment.ps1
   ```

## Development Environment Setup

### Required Software
- PowerShell 7.x or later
- Visual Studio Code
- Git 2.x or later
- .NET SDK 6.0 or later

### VS Code Extensions
- PowerShell (ms-vscode.powershell)
- PSScriptAnalyzer
- GitLens
- Code Spell Checker

### Platform-Specific Setup

#### Windows
```powershell
# Install PowerShell 7
winget install Microsoft.PowerShell

# Install Required Modules
Install-Module -Name PSScriptAnalyzer, Pester, platyPS, Microsoft.PowerShell.SecretStore -Force

# Configure Git for signing
git config --global commit.gpgsign true
git config --global user.signingkey YOUR_KEY_ID
```

#### Linux/macOS
```bash
# Install PowerShell 7
# Linux
wget https://github.com/PowerShell/PowerShell/releases/latest
sudo dpkg -i powershell*.deb

# macOS
brew install powershell

# Configure Git for signing
git config --global commit.gpgsign true
git config --global user.signingkey YOUR_KEY_ID
```

## Security Requirements

### Code Signing
- All PowerShell scripts must be signed using an approved certificate
- Commits must be GPG signed
- Modules must be signed before distribution

### Credential Handling
- Never store credentials in code
- Use SecretStore for credential management
- Implement credential rotation mechanisms

### API Security
- Use TLS 1.2 or later
- Implement rate limiting
- Follow least privilege principle
- Validate all inputs
- Sanitize all outputs

### Compliance Requirements
- Maintain HIPAA compliance
- Follow SOC 2 requirements
- Implement audit logging
- Ensure data privacy

## Coding Standards

### PowerShell Best Practices
- Use approved PowerShell verbs
- Follow noun-verb naming convention
- Implement pipeline support
- Use proper parameter validation
- Include comment-based help

### Error Handling
```powershell
try {
    # Operation code
}
catch [System.Net.WebException] {
    Write-Error -Exception $_ -Category SecurityError
    throw
}
finally {
    # Cleanup code
}
```

### Logging Standards
- Use Write-Verbose for operational logging
- Use Write-Debug for development logging
- Use Write-Error for error conditions
- Implement security event logging

### Documentation Requirements
- Include comment-based help
- Document security considerations
- Provide examples
- Update README.md
- Maintain CHANGELOG.md

## Testing Requirements

### Unit Testing
- Minimum 85% code coverage
- Test all error conditions
- Include security test cases
- Test parameter validation

### Integration Testing
- Test API integration
- Verify error handling
- Test rate limiting
- Validate security controls

### Security Testing
- Run security static analysis
- Perform penetration testing
- Validate input handling
- Test access controls

### Test Documentation
```powershell
Describe 'Security Tests' {
    It 'Should validate input parameters' {
        # Test code
    }
    It 'Should handle invalid credentials' {
        # Test code
    }
}
```

## Pull Request Process

1. **Branch Naming**
   - feature/description
   - bugfix/description
   - security/description

2. **Required Checks**
   - All tests pass
   - Code coverage maintained
   - Security scan clean
   - Documentation updated
   - Changelog updated

3. **Security Review**
   - Code security review
   - Dependency review
   - Compliance check
   - Vulnerability scan

## Issue Guidelines

### Bug Reports
- Use bug report template
- Include PowerShell version
- Provide error messages
- Include reproduction steps

### Feature Requests
- Use feature request template
- Describe security implications
- Include use cases
- Consider enterprise needs

### Security Issues
- Report privately
- Include impact assessment
- Provide reproduction steps
- Follow responsible disclosure

## Code Review Process

### Security Review Checklist
- [ ] Input validation
- [ ] Error handling
- [ ] Credential management
- [ ] API security
- [ ] Compliance requirements

### Performance Review
- [ ] Resource usage
- [ ] API efficiency
- [ ] Memory management
- [ ] Pipeline optimization

## Release Process

### Version Numbering
- Major.Minor.Patch
- Security updates increment patch
- Breaking changes increment major

### Release Checklist
1. Update version numbers
2. Update changelog
3. Run security scan
4. Sign code
5. Create release notes
6. Tag release
7. Publish to PowerShell Gallery

## Troubleshooting

### Common Issues
1. **Certificate Issues**
   ```powershell
   # Verify certificate
   Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert
   ```

2. **Module Loading**
   ```powershell
   # Check module path
   $env:PSModulePath
   ```

3. **Security Errors**
   ```powershell
   # Check execution policy
   Get-ExecutionPolicy -List
   ```

## Community Guidelines

- Follow the Code of Conduct
- Use inclusive language
- Respect security concerns
- Maintain professionalism
- Support fellow contributors

For additional information, see:
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security Policy](SECURITY.md)
- [Support](SUPPORT.md)