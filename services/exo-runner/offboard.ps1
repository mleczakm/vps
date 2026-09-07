# Exchange Online offboarding actions, invoked by server.ps1.
# App-only authentication with a certificate registered on the
# "n8n M365 Offboarding Automation" Entra app (Exchange.ManageAsApp + Exchange Administrator role).

$ErrorActionPreference = 'Stop'

function Connect-Exo {
    if (-not $env:EXO_APP_ID)        { throw 'EXO_APP_ID not set' }
    if (-not $env:EXO_ORGANIZATION)  { throw 'EXO_ORGANIZATION not set' }
    if (-not $env:EXO_CERT_PATH)     { throw 'EXO_CERT_PATH not set' }
    if (-not (Test-Path $env:EXO_CERT_PATH)) { throw "certificate file not found at $env:EXO_CERT_PATH" }

    $securePass = if ($env:EXO_CERT_PASSWORD) {
        ConvertTo-SecureString -String $env:EXO_CERT_PASSWORD -AsPlainText -Force
    } else { $null }

    $params = @{
        AppId               = $env:EXO_APP_ID
        Organization        = $env:EXO_ORGANIZATION
        CertificateFilePath = $env:EXO_CERT_PATH
        ShowBanner          = $false
        SkipLoadingFormatData = $true
        CommandName         = @('Get-Mailbox', 'Set-Mailbox', 'Get-MailboxStatistics',
                                'Add-MailboxPermission', 'Get-MailboxPermission')
        ErrorAction         = 'Stop'
    }
    if ($securePass) { $params['CertificatePassword'] = $securePass }

    Connect-ExchangeOnline @params
}

function Disconnect-Exo {
    try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue } catch { }
}

# Returns a hashtable describing the outcome. Throws on hard failure.
function Invoke-OffboardAction {
    param(
        [Parameter(Mandatory)] [string] $Action,
        [Parameter(Mandatory)] [string] $Upn,
        [string]  $DelegateUpn,
        [string]  $ForwardTo,
        [bool]    $KeepCopy = $true,
        [bool]    $DryRun   = $true
    )

    Connect-Exo
    try {
        switch ($Action) {

            'get-mailbox-info' {
                $mbx  = Get-Mailbox -Identity $Upn -ErrorAction Stop
                $stat = Get-MailboxStatistics -Identity $Upn -ErrorAction SilentlyContinue
                return @{
                    action               = $Action
                    upn                  = $Upn
                    recipientTypeDetails = "$($mbx.RecipientTypeDetails)"
                    totalItemSize        = "$($stat.TotalItemSize)"
                    itemCount            = "$($stat.ItemCount)"
                    archiveStatus        = "$($mbx.ArchiveStatus)"
                    litigationHold       = [bool]$mbx.LitigationHoldEnabled
                    inPlaceHolds         = @($mbx.InPlaceHolds)
                    forwardingSmtp       = "$($mbx.ForwardingSmtpAddress)"
                    hiddenFromGAL        = [bool]$mbx.HiddenFromAddressListsEnabled
                    # Shared mailbox needs a licence when > 50 GB, or with an archive / any hold.
                    canBeUnlicensedShared = ($mbx.ArchiveStatus -eq 'None' -and
                                             -not $mbx.LitigationHoldEnabled -and
                                             @($mbx.InPlaceHolds).Count -eq 0)
                }
            }

            'convert-to-shared' {
                if ($DryRun) { return @{ action = $Action; upn = $Upn; dryRun = $true; wouldRun = "Set-Mailbox -Identity $Upn -Type Shared" } }
                Set-Mailbox -Identity $Upn -Type Shared -ErrorAction Stop
                $mbx = Get-Mailbox -Identity $Upn
                return @{ action = $Action; upn = $Upn; recipientTypeDetails = "$($mbx.RecipientTypeDetails)"; converted = ($mbx.RecipientTypeDetails -eq 'SharedMailbox') }
            }

            'grant-fullaccess' {
                if (-not $DelegateUpn) { return @{ action = $Action; upn = $Upn; skipped = $true; reason = 'no delegateUpn supplied' } }
                if ($DryRun) { return @{ action = $Action; upn = $Upn; delegate = $DelegateUpn; dryRun = $true; wouldRun = "Add-MailboxPermission -Identity $Upn -User $DelegateUpn -AccessRights FullAccess -AutoMapping `$true" } }
                Add-MailboxPermission -Identity $Upn -User $DelegateUpn -AccessRights FullAccess -AutoMapping $true -Confirm:$false -ErrorAction Stop | Out-Null
                return @{ action = $Action; upn = $Upn; delegate = $DelegateUpn; granted = $true }
            }

            'set-forwarding' {
                if (-not $ForwardTo) { return @{ action = $Action; upn = $Upn; skipped = $true; reason = 'no forwardTo supplied' } }
                if ($DryRun) { return @{ action = $Action; upn = $Upn; forwardTo = $ForwardTo; keepCopy = $KeepCopy; dryRun = $true; wouldRun = "Set-Mailbox -Identity $Upn -ForwardingSmtpAddress $ForwardTo -DeliverToMailboxAndForward `$$KeepCopy" } }
                Set-Mailbox -Identity $Upn -ForwardingSmtpAddress $ForwardTo -DeliverToMailboxAndForward:$KeepCopy -ErrorAction Stop
                return @{ action = $Action; upn = $Upn; forwardTo = $ForwardTo; keepCopy = $KeepCopy; forwardingSet = $true }
            }

            'clear-forwarding' {
                if ($DryRun) { return @{ action = $Action; upn = $Upn; dryRun = $true; wouldRun = "Set-Mailbox -Identity $Upn -ForwardingSmtpAddress `$null -DeliverToMailboxAndForward `$false" } }
                Set-Mailbox -Identity $Upn -ForwardingSmtpAddress $null -DeliverToMailboxAndForward:$false -ErrorAction Stop
                return @{ action = $Action; upn = $Upn; forwardingCleared = $true }
            }

            'hide-from-gal' {
                if ($DryRun) { return @{ action = $Action; upn = $Upn; dryRun = $true; wouldRun = "Set-Mailbox -Identity $Upn -HiddenFromAddressListsEnabled `$true" } }
                Set-Mailbox -Identity $Upn -HiddenFromAddressListsEnabled $true -ErrorAction Stop
                return @{ action = $Action; upn = $Upn; hiddenFromGAL = $true }
            }

            default { throw "unknown action: '$Action'" }
        }
    }
    finally {
        Disconnect-Exo
    }
}
