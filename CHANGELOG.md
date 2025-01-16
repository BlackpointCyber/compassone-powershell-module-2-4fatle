# Changelog

[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/PSCompassOne)](https://www.powershellgallery.com/packages/PSCompassOne)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/dt/PSCompassOne)](https://www.powershellgallery.com/packages/PSCompassOne)
[![License](https://img.shields.io/github/license/blackpoint/pscompassone)](LICENSE)
[![Build Status](https://img.shields.io/github/workflow/status/blackpoint/pscompassone/CI)](https://github.com/blackpoint/pscompassone/actions)

All notable changes to the PSCompassOne PowerShell module will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) and follows the format of [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- Initial implementation of asset relationship management cmdlets
  - `Get-PSCompassOneAssetRelationship`
  - `New-PSCompassOneAssetRelationship`
  - `Remove-PSCompassOneAssetRelationship`

### Changed
- Enhanced error handling for rate-limited API responses with exponential backoff
- Improved pipeline support for bulk asset operations

### Deprecated
- Legacy authentication method using plain text credentials
  - Use SecretStore-based authentication instead

### Fixed
- Corrected parameter validation for asset tag operations
- Resolved timezone handling in asset timestamp conversions

### Security
- Updated TLS requirements to enforce TLS 1.2 or higher
- Implemented additional input sanitization for API requests

## [1.0.0] - 2024-01-20

### Breaking Changes
> ⚠️ This release contains breaking changes that require action

- Removed support for PowerShell 5.0 and below
  - Upgrade to PowerShell 5.1 or 7.x to use this version
- Changed authentication model to use SecretStore exclusively
  - Migrate credentials to SecretStore using `Set-PSCompassOneConfiguration`

### Added
- Core asset management cmdlets
  - `Get-PSCompassOneAsset`
  - `New-PSCompassOneAsset`
  - `Set-PSCompassOneAsset`
  - `Remove-PSCompassOneAsset`
- Security finding management
  - `Get-PSCompassOneFinding`
  - `Set-PSCompassOneFindingStatus`
- Incident response automation
  - `Get-PSCompassOneIncident`
  - `New-PSCompassOneIncidentNote`
- Tag management system
  - `Get-PSCompassOneTag`
  - `New-PSCompassOneTag`
  - `Remove-PSCompassOneTag`
- Comprehensive pipeline support for all cmdlets
- Cross-platform compatibility for Windows, Linux, and macOS

### Changed
- Modernized module structure following PowerShell best practices
- Enhanced error messages with actionable troubleshooting steps
- Improved performance for bulk operations through batching
- Updated parameter validation for stricter input checking

### Security
- [CVE-2024-0001] Fixed potential credential exposure in verbose logging
  - Severity: High
  - Added credential masking in all output streams
- Implemented secure credential storage using SecretStore
- Added certificate validation for API endpoints
- Enhanced token management with automatic refresh

### Dependencies
- Added Microsoft.PowerShell.SecretStore 1.0.0 or higher
- Updated PowerShellGet requirement to 2.2.5 or higher
- Requires PowerShell 5.1 or PowerShell 7.x

### Documentation
- Added comprehensive cmdlet help with examples
- Created security best practices guide
- Improved error message documentation
- Added migration guide for breaking changes

## [0.1.0] - 2024-01-10

### Added
- Initial alpha release
- Basic asset management functionality
- Simple authentication system
- Core API integration

[Unreleased]: https://github.com/blackpoint/pscompassone/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/blackpoint/pscompassone/compare/v0.1.0...v1.0.0
[0.1.0]: https://github.com/blackpoint/pscompassone/releases/tag/v0.1.0