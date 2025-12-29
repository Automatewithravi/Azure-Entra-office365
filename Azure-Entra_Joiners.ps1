# PowerShell: Create Microsoft 365 (Azure AD) User via Microsoft Graph API (all secrets in files, custom UPN).

# Paths to secrets
$tenantIdPath     = "C:\automatewithravi\TenantId.txt"
$clientIdPath     = "C:\automatewithravi\ClientId.txt"
$clientSecretPath = "C:\automatewithravi\ClientSecret.txt"
$customDomainPath = "C:\automatewithravi\CustomDomain.txt"
$passwordPath     = "C:\automatewithravi\Password.txt"

# Read secrets
$TenantId     = Get-Content $tenantIdPath     -Raw
$ClientId     = Get-Content $clientIdPath     -Raw
$ClientSecret = Get-Content $clientSecretPath -Raw
$customDomain = (Get-Content $customDomainPath -Raw).Trim()   # e.g. mycompany.com
$userPassword = (Get-Content $passwordPath -Raw).Trim()

# Key: userPrincipalName MUST be unique and use a verified domain!
$userName = "Krithikatestuser"                       # Change for each onboarding
$userDisplayName = "Krithika Testuser"
$userNick = $userName
$userUPN = "$userName@$customDomain"             # UPN = login id, must have your custom domain

# Mandatory fields only
$NewUser = @{
  accountEnabled    = $true
  displayName       = $userDisplayName
  mailNickname      = $userNick
  userPrincipalName = $userUPN
  passwordProfile   = @{
    password = $userPassword
    forceChangePasswordNextSignIn = $true
  }
}

# Microsoft recommends content-type: application/json without charset
$GraphUsersUrl = "https://graph.microsoft.com/v1.0/users"

# Get access token with client credentials grant
$Body = @{
    grant_type    = "client_credentials"
    client_id     = $ClientId
    client_secret = $ClientSecret
    scope         = "https://graph.microsoft.com/.default"
}
$TokenRequest = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Body $Body
$AccessToken = $TokenRequest.access_token

$Headers = @{
    Authorization = "Bearer $AccessToken"
    "Content-Type" = "application/json"
}

# Make sure no trailing newlines break our payload
$UserBody = ($NewUser | ConvertTo-Json -Depth 5)

# Create the user
try {
    $CreateResponse = Invoke-RestMethod -Method Post -Uri $GraphUsersUrl -Headers $Headers -Body $UserBody -ErrorAction Stop
    Write-Host "User creation requested: $userUPN"
} catch {
    $errorDetails = $_.Exception.Response.GetResponseStream() | 
                    % { if ($_ -ne $null) { (New-Object IO.StreamReader $_).ReadToEnd() } else { $_ } }
    Write-Host "Error while creating the user: $($errorDetails)"
    return
}

# Wait and confirm creation with up to 3 attempts, 10 seconds apart
function Confirm-AADUser {
    param($Upn, $GraphUsersUrl, $Headers, $MaxTries = 3, $SleepSec = 10)
    $encodedUPN = [System.Net.WebUtility]::UrlEncode($Upn)
    for ($i=1; $i -le $MaxTries; $i++) {
        try {
            $GetUserResp = Invoke-RestMethod -Method Get -Uri "$GraphUsersUrl/$encodedUPN" -Headers $Headers -ErrorAction Stop
            if ($GetUserResp -and $GetUserResp.userPrincipalName) {
                Write-Host "SUCCESS: User $($GetUserResp.userPrincipalName) created in Azure Entra."
                return $GetUserResp
            }
        } catch {
            Write-Host "Not yet found in Azure Entra (try $i/$MaxTries)..."
            if ($i -lt $MaxTries) { Start-Sleep -Seconds $SleepSec }
        }
    }
    Write-Host "FAILED to confirm user creation after $MaxTries attempts."
    return $null
}

Confirm-AADUser -Upn $userUPN -GraphUsersUrl $GraphUsersUrl -Headers $Headers

<#
EXPLANATION:

Exact endpoint:   POST https://graph.microsoft.com/v1.0/users
                  GET  https://graph.microsoft.com/v1.0/users/{userPrincipalName}

Mandatory fields: userPrincipalName, displayName, mailNickname, accountEnabled, passwordProfile
Why UPN required: This is the unique sign-in (login) name for Azure AD/M365; must use one of your verified/registered domains.
How to use custom domain: Place your domain (e.g. mycompany.com) in C:\automatewithravi\CustomDomain.txt and script uses it to build UPN/email.
Secrets: ALL credentials and password are read from files at C:\automatewithravi\
Password: Value is read from password file.
Confirmation: Script GETs user from /users/{upn}, up to 3 attempts, 10 seconds apart.

Set up note: App must have Application permissions for User.ReadWrite.All, with admin consent in Azure.
#>








