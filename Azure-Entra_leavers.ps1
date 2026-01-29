# Paths to secrets
# This script is used to offboarding the user by disabliong the given user account in AD entra and remove it from the license group

$tenantIdPath     = "C:\automatewithravi\TenantId.txt"
$clientIdPath     = "C:\automatewithravi\ClientId.txt"
$clientSecretPath = "C:\automatewithravi\ClientSecret.txt"
$customDomainPath = "C:\automatewithravi\CustomDomain.txt"
$groupIdPath      = "C:\automatewithravi\GroupId.txt" # <-- TXT file containing Azure AD Group ObjectId

# Read in all secrets (strip whitespace)
$TenantId     = (Get-Content $tenantIdPath     -Raw).Trim()
$ClientId     = (Get-Content $clientIdPath     -Raw).Trim()
$ClientSecret = (Get-Content $clientSecretPath -Raw).Trim()
$customDomain = (Get-Content $customDomainPath -Raw).Trim()
$groupId      = (Get-Content $groupIdPath      -Raw).Trim()

# User info to disable and remove from group
$userName        = "jinitatestuser"                    # Change for each offboarding
$userUPN         = "$userName@$customDomain"         # Format: johndoe@yourdomain.com

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

# --- Find the user by UPN ---
$encodedUPN = [System.Net.WebUtility]::UrlEncode($userUPN)
$userObjectId = $null

try {
    $GetUserResp = Invoke-RestMethod -Method Get -Uri "$GraphUsersUrl/$encodedUPN" -Headers $Headers -ErrorAction Stop
    if ($GetUserResp -and $GetUserResp.id) {
        $userObjectId = $GetUserResp.id
        Write-Host "Found user: $userUPN (ObjectId: $userObjectId)"
    } else {
        Write-Host "ERROR: User found but no ObjectId returned."
        return
    }
} catch {
    $errorDetails = $_.Exception.Response.GetResponseStream() | 
                    % { if ($_ -ne $null) { (New-Object IO.StreamReader $_).ReadToEnd() } else { $_ } }
    Write-Host "ERROR: Could not find user $userUPN. Error: $($errorDetails)"
    return
}

if (-not $userObjectId) {
    Write-Host "ERROR: Could not retrieve user's ObjectId!"
    return
}

# --- Remove user from group ---
$removeMemberUri = "$GraphGroupsUrl/$groupId/members/$userObjectId/`$ref"

try {
    Invoke-RestMethod -Method Delete -Uri $removeMemberUri -Headers $Headers -ErrorAction Stop
    Write-Host "SUCCESS: User $userUPN removed from group $groupId."
} catch {
    $errorDetails = $_.Exception.Response.GetResponseStream() |
                    % { if ($_ -ne $null) { (New-Object IO.StreamReader $_).ReadToEnd() } else { $_ } }
    Write-Host "WARNING: Failed to remove user from group: $($errorDetails)"
    # Continue to disable user even if group removal fails
    if ($errorDetails -and $errorDetails -match '"code":"Authorization_RequestDenied"') {
        Write-Host "`nERROR: Authorization_RequestDenied -- Insufficient privileges. To remove users from groups via Microsoft Graph, your app registration MUST have one of the following delegated or application permissions:"
        Write-Host "    - GroupMember.ReadWrite.All (Application, needs admin consent)"
        Write-Host "    - Directory.ReadWrite.All (Application, needs admin consent)"
        Write-Host ""
        Write-Host "Go to Azure Portal > App registrations > [Your App] > API permissions, and click 'Add a permission' for Microsoft Graph (Application permissions) and add GroupMember.ReadWrite.All."
        Write-Host "Then click 'Grant admin consent'."
    }
}

# --- Disable the user ---
$DisableUserBody = @{
    accountEnabled = $false
} | ConvertTo-Json

try {
    Invoke-RestMethod -Method Patch -Uri "$GraphUsersUrl/$userObjectId" -Headers $Headers -Body $DisableUserBody -ErrorAction Stop
    Write-Host "SUCCESS: User $userUPN has been disabled (accountEnabled = false)."
} catch {
    $errorDetails = $_.Exception.Response.GetResponseStream() |
                    % { if ($_ -ne $null) { (New-Object IO.StreamReader $_).ReadToEnd() } else { $_ } }
    Write-Host "ERROR: Failed to disable user: $($errorDetails)"
    if ($errorDetails -and $errorDetails -match '"code":"Authorization_RequestDenied"') {
        Write-Host "`nERROR: Authorization_RequestDenied -- Insufficient privileges. To disable users via Microsoft Graph, your app registration MUST have one of the following delegated or application permissions:"
        Write-Host "    - User.ReadWrite.All (Application, needs admin consent)"
        Write-Host "    - Directory.ReadWrite.All (Application, needs admin consent)"
        Write-Host ""
        Write-Host "Go to Azure Portal > App registrations > [Your App] > API permissions, and click 'Add a permission' for Microsoft Graph (Application permissions) and add User.ReadWrite.All."
        Write-Host "Then click 'Grant admin consent'."
    }
}

<#
NOTES ON AUTHORIZATION:
For this script to work, your Azure AD app registration needs:
    - Microsoft Graph > Application permissions > GroupMember.ReadWrite.All (to remove from group)
    - Microsoft Graph > Application permissions > User.ReadWrite.All (to disable user)
    OR
    - Microsoft Graph > Application permissions > Directory.ReadWrite.All (covers both)
    - Click 'Grant admin consent' as a Global Admin
#>
