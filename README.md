# PSCompassOne PowerShell Module

[![Build Status](https://github.com/blackpoint/pscompassone/workflows/CI/badge.svg)](https://github.com/blackpoint/pscompassone/actions)
[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/PSCompassOne)](https://www.powershellgallery.com/packages/PSCompassOne)
[![License](https://img.shields.io/github/license/blackpoint/pscompassone)](LICENSE)
[![PowerShell Support](https://img.shields.io/powershellgallery/p/PSCompassOne)](https://www.powershellgallery.com/packages/PSCompassOne)

PSCompassOne provides native PowerShell access to Blackpoint's CompassOne cybersecurity platform through a comprehensive set of cmdlets. This module enables IT professionals, security engineers, and system administrators to programmatically interact with CompassOne's REST API endpoints for asset management, security monitoring, and incident response workflows.

## Features

### Asset Management
- Complete CRUD operations for all asset types
- Bulk asset operations support
- Asset relationship mapping
- Flexible tag management
- Custom attribute handling

### Security Operations
- Real-time alert monitoring
- Incident management workflows
- Finding correlation
- Security note management
- Audit trail tracking

### Integration Capabilities
- PowerShell pipeline support
- Comprehensive error handling
- Detailed logging
- Cross-platform compatibility

## Requirements

- PowerShell 5.1+ or PowerShell 7.x+
- Supported Platforms:
  - Windows
  - Linux
  - macOS
- Internet connectivity for API communication
- CompassOne API credentials

## Installation

Install from PowerShell Gallery (recommended):

```powershell
Install-Module -Name PSCompassOne -Scope CurrentUser
```

Verify installation:

```powershell
Get-Module -Name PSCompassOne -ListAvailable
```

## Quick Start

1. Connect to CompassOne:

```powershell
Connect-CompassOne -ApiKey 'your-api-key'
```

2. Get asset inventory:

```powershell
Get-CompassOneAsset -Status Active
```

3. Monitor security alerts:

```powershell
Get-CompassOneAlert -Severity High -Last 24h
```

4. Manage incidents:

```powershell
New-CompassOneIncident -Title "Security Event" -Severity High -Description "Suspicious activity detected"
```

## Documentation

- [Cmdlet Reference](docs/cmdlets/README.md) - Detailed cmdlet documentation
- [Examples](docs/examples/README.md) - Code examples and use cases
- [API Integration](docs/api/README.md) - API integration details
- [Troubleshooting](docs/troubleshooting/README.md) - Common issues and solutions

For detailed module documentation:

```powershell
Get-Help about_PSCompassOne
```

For specific cmdlet help:

```powershell
Get-Help Get-CompassOneAsset -Full
```

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details on:

- Development environment setup
- Coding standards
- Testing requirements
- Pull request process

Before contributing, please review our:
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security Policy](SECURITY.md)

## Security

For security-related information:
- Review our [Security Policy](SECURITY.md)
- Report vulnerabilities according to our security guidelines
- Follow security best practices when using API credentials

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Version History

See [CHANGELOG.md](CHANGELOG.md) for version history and release notes.

## Support

- Open an issue on GitHub for bug reports or feature requests
- Review existing issues before opening a new one
- Follow security guidelines when reporting security-related issues

---

Copyright © 2024 Blackpoint. All rights reserved.