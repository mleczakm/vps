FROM mcr.microsoft.com/powershell:7.4-debian-12

# PowerShell modules: Pode (HTTP server) + Exchange Online management (app-only, REST-based)
RUN pwsh -NoProfile -NonInteractive -Command " \
      Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; \
      Install-Module -Name Pode -MinimumVersion 2.10.0 -Scope AllUsers -Force; \
      Install-Module -Name ExchangeOnlineManagement -MinimumVersion 3.5.0 -Scope AllUsers -Force; \
    " \
    && pwsh -NoProfile -Command "Import-Module Pode; Import-Module ExchangeOnlineManagement; 'modules ok'"

WORKDIR /app
COPY server.ps1 offboard.ps1 ./

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=25s --retries=3 \
    CMD pwsh -NoProfile -Command "try { if ((Invoke-WebRequest -UseBasicParsing http://localhost:8080/health).StatusCode -eq 200) { exit 0 } else { exit 1 } } catch { exit 1 }"

CMD ["pwsh", "-NoProfile", "-File", "/app/server.ps1"]
