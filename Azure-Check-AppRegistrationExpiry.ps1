#Requires -Version 5.1
<#
.SYNOPSIS  Checks Azure AD App Registration secret and certificate expiry via Graph API.
.DESCRIPTION
    Authenticates using Managed Identity (system or user-assigned).
    Scans all App Registrations and prints expired / expiring credentials to the console.
.PARAMETER ExpiryThresholdDays  Days before expiry to alert. Default: 30.
.PARAMETER ManagedIdentityClientId  Optional. Client ID for user-assigned MI only.
#>
[CmdletBinding()]
param (
    [int]$ExpiryThresholdDays       = 30,
    [string]$ManagedIdentityClientId = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── 1. Get Managed Identity token ───────────────────────────────────────────
function Get-MIToken {
    param ([string]$ClientId = "")
    $res = "https://graph.microsoft.com/"
    if ($env:MSI_ENDPOINT -and $env:MSI_SECRET) {
        $uri = "$($env:MSI_ENDPOINT)?resource=$res&api-version=2017-09-01"
        if ($ClientId) { $uri += "&client_id=$ClientId" }
        return (Invoke-RestMethod -Uri $uri -Headers @{ Secret = $env:MSI_SECRET }).access_token
    }
    $uri = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$res"
    if ($ClientId) { $uri += "&client_id=$ClientId" }
    return (Invoke-RestMethod -Uri $uri -Headers @{ Metadata = "true" }).access_token
}

# ── 2. Graph paged GET ───────────────────────────────────────────────────────
function Get-GraphData {
    param ([string]$Token, [string]$Uri)
    $h = @{ Authorization = "Bearer $Token" }; $out = @()
    do {
        $r = Invoke-RestMethod -Method Get -Uri $Uri -Headers $h
        if ($r.value) { $out += @($r.value) }
        $Uri = $null
        if ($r.PSObject.Properties.Name -contains '@odata.nextLink') { $Uri = $r.'@odata.nextLink' }
    } while ($Uri)
    return $out
}

# ── 3. Credential status ─────────────────────────────────────────────────────
function Get-Status {
    param ([datetime]$Expiry, [int]$Days)
    $left = ($Expiry - (Get-Date)).Days
    if     ($Expiry -lt (Get-Date)) { return @{ Status="EXPIRED";  DaysLeft=$left; Color="Red"    } }
    elseif ($left -le $Days)         { return @{ Status="EXPIRING"; DaysLeft=$left; Color="Yellow" } }
    else                               { return @{ Status="OK";       DaysLeft=$left; Color="Green"  } }
}

# ── MAIN ─────────────────────────────────────────────────────────────────────
Write-Host "`n=== App Registration Credential Expiry Checker ===" -ForegroundColor Cyan
Write-Host "Threshold : $ExpiryThresholdDays days  |  $(Get-Date -Format 'dd MMM yyyy HH:mm') UTC`n"

$token = Get-MIToken -ClientId $ManagedIdentityClientId
$apps  = @(Get-GraphData -Token $token `
           -Uri "https://graph.microsoft.com/v1.0/applications?`$select=id,appId,displayName,passwordCredentials,keyCredentials&`$top=999")
Write-Host "Found $($apps.Count) application(s). Scanning...`n"

$findings = @()
foreach ($app in $apps) {
    $hits = @()
    foreach ($cred in (@($app.passwordCredentials) + @($app.keyCredentials))) {
        if (-not $cred.endDateTime) { continue }
        $s    = Get-Status -Expiry ([datetime]$cred.endDateTime) -Days $ExpiryThresholdDays
        $type = if ($cred.PSObject.Properties.Name -contains 'keyType') { "Certificate" } else { "Secret" }
        if ($s.Status -ne "OK") {
            $hits += [PSCustomObject]@{
                AppDisplayName = $app.displayName; AppClientId = $app.appId; Type = $type
                CredentialName = if ($cred.displayName) { $cred.displayName } else { $cred.keyId }
                ExpiryDate = ([datetime]$cred.endDateTime).ToString("dd MMM yyyy")
                Status = $s.Status; DaysLeft = $s.DaysLeft; Color = $s.Color
            }
        }
    }
    if ($hits.Count -gt 0) {
        Write-Host "--- $($app.displayName)" -ForegroundColor White
        foreach ($h in $hits) {
            Write-Host ("  [{0}] {1,-13} {2,-30} Expires: {3}  ({4} days)" -f
                $h.Status, $h.Type, $h.CredentialName, $h.ExpiryDate, $h.DaysLeft) `
                -ForegroundColor $h.Color
        }
        $findings += $hits
    }
}

Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
if ($findings.Count -eq 0) {
    Write-Host "No credentials expiring within $ExpiryThresholdDays days." -ForegroundColor Green
} else {
    Write-Host ("Total: {0}  |  Expired: {1}  |  Expiring: {2}" -f
        $findings.Count,
        @($findings | Where-Object Status -eq "EXPIRED").Count,
        @($findings | Where-Object Status -eq "EXPIRING").Count)
    $findings | Select-Object AppDisplayName, Type, CredentialName, ExpiryDate, Status, DaysLeft |
        Sort-Object DaysLeft | Format-Table -AutoSize
}
Write-Host "=== Done ===`n" -ForegroundColor Cyan
