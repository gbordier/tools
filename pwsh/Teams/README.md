# Teams Room Call Quality Reports

Two PowerShell scripts for retrieving Microsoft Teams Room call quality data.
Choose the one that fits your authentication model:

| Script | Auth model | Data source | Modules needed | Best for |
|---|---|---|---|---|
| `Get-TeamsRoomQuality.ps1` | **Interactive** (user sign-in popup) | CQD REST API | *None* | Ad-hoc / manual runs |
| `Get-TeamsRoomQuality-Graph.ps1` | **App-only** (client credentials) | Microsoft Graph | `Microsoft.Graph.Authentication` | Automation / scheduled tasks |

---

## Prerequisites

| Requirement | CQD script | Graph script |
|---|---|---|
| PowerShell 7+ | ✅ | ✅ |
| Entra ID admin role¹ | ✅ | — |
| App Registration + admin consent | — | ✅ |
| `Microsoft.Graph.Authentication` module | — | ✅ (auto-installed) |

¹ The interactive user must hold **Teams Administrator**, **Teams Communications Administrator**, or **Global Reader**.

---

## Option A – Interactive / CQD-based (`Get-TeamsRoomQuality.ps1`)

This script uses the Call Quality Dashboard (CQD) REST API.
A browser sign-in popup appears, and no app registration or client secret is needed.

### 1. Run the script

```powershell
# Default: last 7 days, CSV output in the current folder
.\Get-TeamsRoomQuality.ps1

# Custom period and output folder
.\Get-TeamsRoomQuality.ps1 -DaysBack 14 -OutputPath "C:\Reports"
```

### 2. Authenticate

A sign-in window opens automatically. Sign in with an account that has one of the required roles listed above. The window closes once authentication is complete.

### 3. Collect the report

The script writes a CSV file to the output directory.

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `-DaysBack` | `7` | Number of days to look back (1–30) |
| `-OutputPath` | Current directory | Folder for the CSV report |
| `-MinimumCallDurationSeconds` | `60` | Ignore calls shorter than this |
| `-QualityThresholds` | See script | Hashtable of quality thresholds |

---

## Option B – App-only / Graph-based (`Get-TeamsRoomQuality-Graph.ps1`)

This script uses the Microsoft Graph API with the OAuth 2.0 client-credentials flow.
No interactive sign-in is needed at run time — ideal for scheduled tasks and automation.

### 1. Register the application (one-time setup)

Run the included helper script. It creates the app registration, grants admin consent, and saves the credentials to a `.env.json` file:

```powershell
.\Register-TeamsRoomQualityApp.ps1
```

A browser sign-in popup will appear — sign in with an account that has **Application Administrator** (or **Global Administrator**) privileges.

The script:

1. Creates an Entra ID App Registration named **Teams Room Quality Reporter**.
2. Assigns the required **application** permissions:
   - `CallRecords.Read.All`
   - `User.Read.All`
3. Grants tenant-wide admin consent.
4. Creates a client secret (default: 12 months).
5. Writes `.env.json` in the current directory:

```json
{
  "TenantId":     "<your-tenant-id>",
  "ClientId":     "<app-client-id>",
  "ClientSecret": "<secret-value>"
}
```

> **⚠ Security:** The `.env.json` file contains a plain-text secret. Keep it out of source control (add it to `.gitignore`) and consider moving the secret to a vault for production use.

#### Optional registration parameters

| Parameter | Default | Description |
|---|---|---|
| `-AppDisplayName` | `Teams Room Quality Reporter` | Display name for the app |
| `-SecretExpirationMonths` | `12` | Secret validity (1–24 months) |
| `-OutputPath` | Current directory | Where to write `.env.json` |

#### Re-running the registration script

If a `.env.json` already exists with a `ClientId`, the script **re-uses** the existing app instead of creating a duplicate. A new client secret is generated and the file is updated.

### 2. Run the quality report

```powershell
# Simplest — reads credentials from .env.json next to the script
.\Get-TeamsRoomQuality-Graph.ps1

# Point to a different env file
.\Get-TeamsRoomQuality-Graph.ps1 -EnvFile "C:\Secrets\.env.json"

# Explicit credentials (all three are required together)
.\Get-TeamsRoomQuality-Graph.ps1 -TenantId "contoso.onmicrosoft.com" `
    -ClientId "12345678-..." -ClientSecret "mySecret"

# Custom period and output
.\Get-TeamsRoomQuality-Graph.ps1 -DaysBack 14 -OutputPath "C:\Reports"
```

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `-TenantId` | From `.env.json` | Azure AD tenant ID (mandatory if explicit) |
| `-ClientId` | From `.env.json` | App Registration client ID (mandatory if explicit) |
| `-ClientSecret` | From `.env.json` | Client secret value (mandatory if explicit) |
| `-EnvFile` | `.env.json` in script dir | Path to the credentials file |
| `-DaysBack` | `7` | Number of days to look back (1–30) |
| `-OutputPath` | Current directory | Folder for the CSV report |
| `-MinimumCallDurationSeconds` | `60` | Ignore calls shorter than this |
| `-QualityThresholds` | See script | Hashtable of quality thresholds |

> **Parameter sets:** If you pass any of `-TenantId`, `-ClientId`, or `-ClientSecret`, all three become mandatory. If you pass none of them, the script reads from `.env.json` (default behaviour).

---

## Quality Thresholds

Both scripts use the same default thresholds based on Microsoft's recommendations:

| Metric | Threshold | Notes |
|---|---|---|
| Audio Jitter | < 30 ms | |
| Audio Packet Loss | < 5 % | |
| Audio Round-Trip Time | < 500 ms | |
| Video Jitter | < 30 ms | |
| Video Packet Loss | < 5 % | |
| Video Frame Rate | ≥ 7 fps | Below this is flagged as poor |
| Screen Share Jitter | < 30 ms | |
| Screen Share Packet Loss | < 5 % | |

Override them with the `-QualityThresholds` parameter:

```powershell
.\Get-TeamsRoomQuality-Graph.ps1 -QualityThresholds @{
    AudioJitterMs          = 20
    AudioPacketLossPercent = 3
    AudioRoundTripMs       = 300
    VideoJitterMs          = 20
    VideoPacketLossPercent = 3
    VideoFrameRateLow      = 10
    ScreenShareJitterMs    = 20
    ScreenSharePacketLoss  = 3
}
```

---

## Quick-start summary

```text
# ── Interactive (CQD) ───────────────────────
.\Get-TeamsRoomQuality.ps1            # sign-in popup, done

# ── App-based (Graph) ───────────────────────
.\Register-TeamsRoomQualityApp.ps1    # one-time: creates app + .env.json
.\Get-TeamsRoomQuality-Graph.ps1      # reads .env.json, no popup
```
