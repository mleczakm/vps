# exo-runner: minimal HTTP wrapper around Exchange Online offboarding actions.
# Called only over the internal Docker network by the n8n offboarding workflow.
#
#   GET  /health                 -> { status: "ok" }
#   POST /run   (x-api-key hdr)   -> body { action, upn, delegateUpn?, forwardTo?, keepCopy?, dryRun? }
#
# Actions: get-mailbox-info | convert-to-shared | grant-fullaccess |
#          set-forwarding | clear-forwarding | hide-from-gal

$ErrorActionPreference = 'Stop'
Import-Module Pode

$OffboardScript = Join-Path $PSScriptRoot 'offboard.ps1'

Start-PodeServer {
    Add-PodeEndpoint -Address '0.0.0.0' -Port 8080 -Protocol Http

    New-PodeLoggingMethod -Terminal | Enable-PodeErrorLogging
    New-PodeLoggingMethod -Terminal | Enable-PodeRequestLogging

    Add-PodeRoute -Method Get -Path '/health' -ScriptBlock {
        Write-PodeJsonResponse -Value @{ status = 'ok' }
    }

    Add-PodeRoute -Method Post -Path '/run' -ArgumentList @($OffboardScript) -ScriptBlock {
        param($OffboardScriptPath)

        try {
            . $OffboardScriptPath

            $apiKey   = $env:EXO_RUNNER_API_KEY
            $provided = Get-PodeHeader -Name 'x-api-key'
            if ([string]::IsNullOrWhiteSpace($apiKey) -or $provided -ne $apiKey) {
                Set-PodeResponseStatus -Code 401
                Write-PodeJsonResponse -Value @{ ok = $false; error = 'unauthorized' }
                return
            }

            $data = $WebEvent.Data
            if (-not $data) {
                Set-PodeResponseStatus -Code 400
                Write-PodeJsonResponse -Value @{ ok = $false; error = 'empty or non-JSON body' }
                return
            }

            $action = [string]$data.action
            $upn    = [string]$data.upn
            if ([string]::IsNullOrWhiteSpace($action) -or [string]::IsNullOrWhiteSpace($upn)) {
                Set-PodeResponseStatus -Code 400
                Write-PodeJsonResponse -Value @{ ok = $false; error = "'action' and 'upn' are required" }
                return
            }

            # dryRun defaults to TRUE: a real change must be requested explicitly.
            $dryRun = $true
            if ($null -ne $data.dryRun) { $dryRun = [System.Convert]::ToBoolean([string]$data.dryRun) }
            $keepCopy = $true
            if ($null -ne $data.keepCopy) { $keepCopy = [System.Convert]::ToBoolean([string]$data.keepCopy) }

            $result = Invoke-OffboardAction `
                -Action $action `
                -Upn $upn `
                -DelegateUpn ([string]$data.delegateUpn) `
                -ForwardTo ([string]$data.forwardTo) `
                -KeepCopy $keepCopy `
                -DryRun $dryRun

            Write-PodeJsonResponse -Value @{ ok = $true; result = $result }
        }
        catch {
            Set-PodeResponseStatus -Code 500
            Write-PodeJsonResponse -Value @{ ok = $false; error = "$($_.Exception.Message)" }
        }
    }
}
