# PowerShell: Create Microsoft 365 (Azure AD) User via Microsoft Graph API and Add to Group
# This version checks for Authorization_RequestDenied and explains what to do for insufficient privileges
# This script can be used to onboard the new user and add in to the licensing group

# Paths to secrets
$tenantIdPath     = "C:\automatewithravi\TenantId.txt"
$clientIdPath     = "C:\automatewithravi\ClientId.txt"
$clientSecretPath = "C:\automatewithravi\ClientSecret.txt"
$customDomainPath = "C:\automatewithravi\CustomDomain.txt"
$passwordPath     = "C:\automatewithravi\Password.txt"
$groupIdPath      = "C:\automatewithravi\GroupId.txt" # <-- TXT file containing Azure AD Group ObjectId

# Read in all secrets (strip whitespace)
$TenantId     = (Get-Content $tenantIdPath     -Raw).Trim()
$ClientId     = (Get-Content $clientIdPath     -Raw).Trim()
$ClientSecret = (Get-Content $clientSecretPath -Raw).Trim()
$customDomain = (Get-Content $customDomainPath -Raw).Trim()
$userPassword = (Get-Content $passwordPath -Raw).Trim()
$groupId      = (Get-Content $groupIdPath      -Raw).Trim()

# New user info (edit as needed for onboarding)
$userName        = "jinitatestuser"                    # Change for each onboarding
$userDisplayName = "jinita Testuser"
$userNick        = $userName
$userUPN         = "$userName@$customDomain"         # Format: johndoe@yourdomain.com

# Create user object with only mandatory fields
$NewUser = @{
  accountEnabled    = $true
  displayName       = $userDisplayName
  mailNickname      = $userNick
  userPrincipalName = $userUPN        # Mandatory: must be unique & under a verified/registered domain!
  passwordProfile   = @{
    password = $userPassword
    forceChangePasswordNextSignIn = $true
  }
}
# userPrincipalName is mandatory because it is the unique logon name used for email/Cloud/login.

# Microsoft Graph endpoints
$GraphUsersUrl   = "https://graph.microsoft.com/v1.0/users"
$GraphGroupsUrl  = "https://graph.microsoft.com/v1.0/groups"

# Get Graph access token (client credentials grant)
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

# Prepare body for user creation
$UserBody = ($NewUser | ConvertTo-Json -Depth 5)

# --- Create the user ---
try {
    $CreateResponse = Invoke-RestMethod -Method Post -Uri $GraphUsersUrl -Headers $Headers -Body $UserBody -ErrorAction Stop
    Write-Host "User creation requested: $userUPN"
} catch {
    $errorDetails = $_.Exception.Response.GetResponseStream() | 
                    % { if ($_ -ne $null) { (New-Object IO.StreamReader $_).ReadToEnd() } else { $_ } }
    Write-Host "Error while creating the user: $($errorDetails)"
    return
}

# --- Wait and confirm creation with up to 3 attempts, 10 seconds between tries ---
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

# Do the confirmation
$UserObj = Confirm-AADUser -Upn $userUPN -GraphUsersUrl $GraphUsersUrl -Headers $Headers

if (-not $UserObj) {
    Write-Host "User was NOT confirmed in Entra/Azure AD. Exiting without adding to group."
    return
}

# Add user (by objectId) to a group (@odata.id correct for users)
$ObjectId = $UserObj.id
if (-not $ObjectId) {
    Write-Host "Could not retrieve created user's ObjectId!"
    return
}
$MemberAddBody = @{
    "@odata.id" = "https://graph.microsoft.com/v1.0/users/$ObjectId"
} | ConvertTo-Json

$addMemberUri = "$GraphGroupsUrl/$groupId/members/`$ref"

try {
    $addGroupResp = Invoke-RestMethod -Method Post -Uri $addMemberUri -Headers $Headers -Body $MemberAddBody -ErrorAction Stop
    Write-Host "User $userUPN added to group $groupId successfully."
} catch {
    $errorDetails = $_.Exception.Response.GetResponseStream() |
                    % { if ($_ -ne $null) { (New-Object IO.StreamReader $_).ReadToEnd() } else { $_ } }
    Write-Host "Failed to add user to group: $($errorDetails)"
    if ($errorDetails -and $errorDetails -match '"code":"Authorization_RequestDenied"') {
        Write-Host "`nERROR: Authorization_RequestDenied -- Insufficient privileges. To add users to groups via Microsoft Graph, your app registration MUST have one of the following delegated or application permissions:"
        Write-Host "    - GroupMember.ReadWrite.All (Application, needs admin consent)"
        Write-Host "    - Directory.ReadWrite.All (Application, needs admin consent)"
        Write-Host ""
        Write-Host "Go to Azure Portal > App registrations > [Your App] > API permissions, and click 'Add a permission' for Microsoft Graph (Application permissions) and add GroupMember.ReadWrite.All."
        Write-Host "Then click 'Grant admin consent'."
        Write-Host ""
        Write-Host "You may need to re-authenticate or wait for permissions to propagate before retrying this script."
    }
}

<#
NOTES ON AUTHORIZATION:
If you see "Authorization_RequestDenied" or "Insufficient privileges", ensure your Azure AD app registration has:
    - Microsoft Graph > Application permissions > GroupMember.ReadWrite.All
    - Click 'Grant admin consent' as a Global Admin
    - Your token must be from the correct tenant and reflect the correct permissions!
#>














