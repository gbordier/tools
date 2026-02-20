<#
.SYNOPSIS
    Creates an Entra ID (Azure AD) App Registration with the permissions
    required by Get-TeamsRoomQuality-Graph.ps1 and outputs a .env.json file.

.DESCRIPTION
    This script performs the following steps:
      1. Connects to Microsoft Graph with delegated (interactive) permissions.
      2. Checks for an existing .env.json – if it contains a ClientId, the
         script re-uses that App Registration instead of creating a new one.
      3. Otherwise creates a new App Registration.
      4. Adds the required APPLICATION permissions:
           • CallRecords.Read.All
           • User.Read.All
      5. Grants tenant-wide admin consent for those permissions.
      6. Creates a client secret (valid for the specified number of months).
      7. Writes / updates the .env.json file with TenantId, ClientId,
         and the new ClientSecret.

    Prerequisites
    ─────────────
    • PowerShell 7+
    • Microsoft.Graph module (the script will install it if missing).
    • You must sign in as a user with at least the
      "Application Administrator" + "Cloud Application Administrator" roles
      (or Global Administrator) to create the app and grant admin consent.

.PARAMETER AppDisplayName
    Display name for the new App Registration.
    Default: "Teams Room Quality Reporter"

.PARAMETER SecretExpirationMonths
    How many months the client secret should be valid. Default: 12.

.PARAMETER OutputPath
    Directory where the .env.json file will be written.
    Defaults to the current directory.

.EXAMPLE
    .\Register-TeamsRoomQualityApp.ps1

.EXAMPLE
    .\Register-TeamsRoomQualityApp.ps1 -AppDisplayName "My TR Quality App" -SecretExpirationMonths 24

.EXAMPLE
    .\Register-TeamsRoomQualityApp.ps1 -OutputPath "C:\Secrets"
#>

[CmdletBinding()]
param(
    [string]$AppDisplayName = 'Teams Room Quality Reporter',

    [ValidateRange(1, 24)]
    [int]$SecretExpirationMonths = 12,

    [string]$OutputPath = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

#region ── Helper Functions ──────────────────────────────────────────────────────

function Write-Step  { param([string]$Msg) Write-Information "▶  $Msg" }
function Write-Detail { param([string]$Msg) Write-Information "   $Msg" }

function Ensure-GraphModules {
    $requiredModules = @(
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.Applications'
    )
    foreach ($mod in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $mod)) {
            Write-Detail "Installing $mod …"
            Install-Module -Name $mod -Scope CurrentUser -Force -AllowClobber
        }
        Import-Module $mod -ErrorAction Stop
    }
}

#endregion

#region ── Main ──────────────────────────────────────────────────────────────────

Write-Step "Ensuring required Microsoft.Graph modules are available …"
Ensure-GraphModules

# ── 1. Interactive sign-in ──────────────────────────────────────────────────
Write-Step "Connecting to Microsoft Graph (interactive sign-in) …"
Write-Detail "You need Application Administrator (or Global Admin) privileges."

# We need scopes to create apps and grant admin consent
Connect-MgGraph -Scopes @(
    'Application.ReadWrite.All',
    'AppRoleAssignment.ReadWrite.All',
    'DelegatedPermissionGrant.ReadWrite.All'
) -NoWelcome

$ctx = Get-MgContext
if (-not $ctx) { throw 'Microsoft Graph authentication failed.' }

$tenantId = $ctx.TenantId
Write-Detail "Signed in to tenant $tenantId as $($ctx.Account)"

# ── 2. Resolve Microsoft Graph service principal & required permissions ─────
Write-Step "Resolving Microsoft Graph API permission IDs …"

# Microsoft Graph's well-known appId is always 00000003-0000-0000-c000-000000000000
$graphAppId = '00000003-0000-0000-c000-000000000000'
$graphSp    = Get-MgServicePrincipal -Filter "appId eq '$graphAppId'"

if (-not $graphSp) {
    throw "Could not find the Microsoft Graph service principal in this tenant."
}

# Build a lookup table: permission name → AppRole object
$appRoleLookup = @{}
foreach ($role in $graphSp.AppRoles) {
    $appRoleLookup[$role.Value] = $role
}

$requiredPermissions = @(
    'CallRecords.Read.All',
    'User.Read.All'
)

$permissionIds = @()
foreach ($perm in $requiredPermissions) {
    if (-not $appRoleLookup.ContainsKey($perm)) {
        throw "Permission '$perm' not found in Microsoft Graph AppRoles."
    }
    $permissionIds += $appRoleLookup[$perm]
    Write-Detail "$perm  →  $($appRoleLookup[$perm].Id)"
}

# ── 3. Create or re-use App Registration ───────────────────────────────────
$envFilePath = Join-Path $OutputPath '.env.json'
$app = $null

# 3a. Check whether an existing .env.json already references an app
if (Test-Path $envFilePath) {
    try {
        $existingEnv = Get-Content -Path $envFilePath -Raw | ConvertFrom-Json
    } catch { $existingEnv = $null }

    if ($existingEnv -and -not [string]::IsNullOrEmpty($existingEnv.ClientId)) {
        Write-Step "Found existing .env.json with ClientId $($existingEnv.ClientId) – looking up the app …"
        $app = Get-MgApplication -Filter "appId eq '$($existingEnv.ClientId)'" -ErrorAction SilentlyContinue
        if ($app) {
            Write-Detail "Re-using existing app '$($app.DisplayName)' ($($app.AppId)) from .env.json."
        }
        else {
            Write-Warning "The ClientId $($existingEnv.ClientId) from .env.json was not found in this tenant. A new app will be created."
        }
    }
}

# 3b. Fall back: check by display name
if (-not $app) {
    $existingApp = Get-MgApplication -Filter "displayName eq '$AppDisplayName'" -ErrorAction SilentlyContinue
    if ($existingApp) {
        Write-Warning "An application named '$AppDisplayName' already exists (AppId: $($existingApp.AppId))."
        $choice = Read-Host "Do you want to use the existing app? (Y/N)"
        if ($choice -notin @('Y', 'y', 'Yes', 'yes')) {
            Write-Information "Aborting. Rename the app or remove the existing one first."
            return
        }
        $app = $existingApp
        Write-Detail "Re-using existing app: $($app.AppId)"
    }
}

# 3c. Create a brand-new app if nothing was found
if (-not $app) {
    Write-Step "Creating App Registration '$AppDisplayName' …"

    $resourceAccess = $permissionIds | ForEach-Object {
        @{ Id = $_.Id; Type = 'Role' }   # Type = 'Role' means Application permission
    }

    $appBody = @{
        DisplayName            = $AppDisplayName
        SignInAudience         = 'AzureADMyOrg'
        RequiredResourceAccess = @(
            @{
                ResourceAppId  = $graphAppId
                ResourceAccess = $resourceAccess
            }
        )
    }

    $app = New-MgApplication -BodyParameter $appBody
    Write-Detail "App created – AppId (ClientId): $($app.AppId)"
    Write-Detail "Object Id: $($app.Id)"
}

# ── 4. Create a Service Principal for the app (required for consent) ────────
Write-Step "Ensuring a Service Principal exists for the app …"

$appSp = Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'" -ErrorAction SilentlyContinue
if (-not $appSp) {
    $appSp = New-MgServicePrincipal -AppId $app.AppId
    Write-Detail "Service principal created – Id: $($appSp.Id)"
}
else {
    Write-Detail "Service principal already exists – Id: $($appSp.Id)"
}

# ── 5. Grant admin consent (assign app roles) ──────────────────────────────
Write-Step "Granting admin consent for application permissions …"

foreach ($role in $permissionIds) {
    # Check if already granted
    $existing = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $appSp.Id |
                Where-Object { $_.AppRoleId -eq $role.Id -and $_.ResourceId -eq $graphSp.Id }

    if ($existing) {
        Write-Detail "$($role.Value) – already consented."
        continue
    }

    $body = @{
        PrincipalId = $appSp.Id
        ResourceId  = $graphSp.Id
        AppRoleId   = $role.Id
    }
    New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $appSp.Id -BodyParameter $body | Out-Null
    Write-Detail "$($role.Value) – admin consent granted ✓"
}

# ── 6. Create a client secret ──────────────────────────────────────────────
Write-Step "Creating client secret (valid $SecretExpirationMonths month(s)) …"

$secretBody = @{
    PasswordCredential = @{
        DisplayName = "Auto-generated by Register-TeamsRoomQualityApp"
        EndDateTime = (Get-Date).AddMonths($SecretExpirationMonths).ToUniversalTime()
    }
}

$secret = Add-MgApplicationPassword -ApplicationId $app.Id -BodyParameter $secretBody
$clientSecretValue = $secret.SecretText

if ([string]::IsNullOrEmpty($clientSecretValue)) {
    throw "Failed to retrieve the client secret value. This may happen if the secret was already created. Try again or create one manually in the Azure portal."
}

Write-Detail "Secret created – expires $($secret.EndDateTime)"
Write-Warning "Save the secret now – it cannot be retrieved again after this session!"

# ── 7. Write .env.json ─────────────────────────────────────────────────────
Write-Step "Writing .env.json …"

$envContent = [ordered]@{
    TenantId     = $tenantId
    ClientId     = $app.AppId
    ClientSecret = $clientSecretValue
} | ConvertTo-Json -Depth 2

Set-Content -Path $envFilePath -Value $envContent -Encoding UTF8

Write-Detail "File written: $envFilePath"

# ── 8. Summary ──────────────────────────────────────────────────────────────
Write-Information ''
Write-Information '────────────────────────────────────────────────────────────'
Write-Information '  Registration complete!'
Write-Information "  App Name     : $AppDisplayName"
Write-Information "  Tenant Id    : $tenantId"
Write-Information "  Client Id    : $($app.AppId)"
Write-Information "  Secret Expiry: $($secret.EndDateTime)"
Write-Information "  Permissions  : $($requiredPermissions -join ', ')"
Write-Information "  .env.json    : $envFilePath"
Write-Information '────────────────────────────────────────────────────────────'
Write-Information ''
Write-Information '  Usage:'
Write-Information "    `$env = Get-Content '$envFilePath' | ConvertFrom-Json"
Write-Information '    .\Get-TeamsRoomQuality-Graph.ps1 \'
Write-Information '        -TenantId $env.TenantId \'
Write-Information '        -ClientId $env.ClientId \'
Write-Information '        -ClientSecret $env.ClientSecret'
Write-Information ''

# Disconnect
Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null

#endregion
