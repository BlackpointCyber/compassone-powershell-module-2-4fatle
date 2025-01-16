# Stage 1: Builder stage for development and testing
FROM mcr.microsoft.com/powershell:7.3 AS builder

# Set environment variables for builder stage
ENV PSModulePath=/usr/local/share/powershell/Modules \
    PSCOMPASSONE_CONFIG=/etc/pscompassone/config \
    PSCOMPASSONE_TEST=true \
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

# Install development dependencies
RUN pwsh -c 'Install-Module -Name PSScriptAnalyzer -RequiredVersion 1.20.0 -Force -Scope AllUsers' && \
    pwsh -c 'Install-Module -Name Pester -Force -Scope AllUsers' && \
    pwsh -c 'Install-Module -Name Microsoft.PowerShell.SecretStore -RequiredVersion 1.0.0 -Force -Scope AllUsers'

# Create module directory structure
WORKDIR /build
COPY . .

# Run tests and analysis
RUN pwsh -c 'Invoke-ScriptAnalyzer -Path . -Recurse' && \
    pwsh -c 'Invoke-Pester ./test -CI'

# Generate documentation and prepare production artifacts
RUN pwsh -c 'New-ExternalHelp -Path ./docs -OutputPath ./out/en-US' && \
    mkdir -p /out/PSCompassOne && \
    cp -r ./src/* /out/PSCompassOne/ && \
    cp -r ./out/en-US /out/PSCompassOne/

# Stage 2: Production runtime with minimal footprint
FROM mcr.microsoft.com/powershell:7.3-alpine AS final

# Set environment variables for production
ENV PSModulePath=/usr/local/share/powershell/Modules \
    PSCOMPASSONE_CONFIG=/etc/pscompassone/config \
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

# Create non-root user and group
RUN addgroup -S pscompassone && \
    adduser -S pscompassone -G pscompassone

# Install production dependencies
RUN pwsh -c 'Install-Module -Name Microsoft.PowerShell.SecretStore -RequiredVersion 1.0.0 -Force -Scope AllUsers'

# Create necessary directories with proper permissions
RUN mkdir -p /etc/pscompassone/config && \
    mkdir -p /var/log/pscompassone && \
    chown -R pscompassone:pscompassone /etc/pscompassone /var/log/pscompassone && \
    chmod -R 755 /etc/pscompassone && \
    chmod -R 755 /var/log/pscompassone

# Copy verified module from builder stage
COPY --from=builder --chown=pscompassone:pscompassone /out/PSCompassOne /usr/local/share/powershell/Modules/PSCompassOne

# Configure security settings
RUN chmod -R 755 /usr/local/share/powershell/Modules/PSCompassOne

# Set up volume mounts
VOLUME ["/etc/pscompassone/config", "/var/log/pscompassone"]

# Switch to non-root user
USER pscompassone

# Health check configuration
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ["pwsh", "-c", "Import-Module PSCompassOne; Test-PSCompassOneConnection"]

# Container metadata labels
LABEL org.opencontainers.image.source="https://github.com/blackpoint/pscompassone" \
      org.opencontainers.image.description="PSCompassOne PowerShell Module Container" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="Blackpoint" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      com.blackpoint.pscompassone.version="${VERSION}" \
      com.blackpoint.pscompassone.build.date="${BUILD_DATE}" \
      com.blackpoint.pscompassone.build.commit="${GIT_COMMIT}"

# Security options
SECURITY_OPT no-new-privileges=true \
             read-only=true \
             seccomp=unconfined=false \
             selinux-enabled=true

# Drop all capabilities and add only required ones
DROP_CAPS ALL
ADD_CAPS NET_BIND_SERVICE

# Set entrypoint
ENTRYPOINT ["pwsh"]