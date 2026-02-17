<#
.SYNOPSIS
    Retrieves Microsoft Teams Room call quality data using Microsoft Graph API
    with interactive admin sign-in.

.DESCRIPTION
    This script authenticates an admin user interactively via the Microsoft Graph
    PowerShell SDK, identifies Teams Room devices, pulls call records where rooms
    participated, and reports audio/video/screen-share quality metrics from the
    room's point of view.

    Authentication uses the well-known "Microsoft Graph PowerShell" public
    client app registration (14d82eec-204b-4c2f-b7e8-296a70dab67e) by default,
    so NO custom app registration or client secret is needed.

    Prerequisites:
      1. The signed-in user must have one of the following Entra ID admin roles:
         - Teams Administrator, Teams Communications Administrator, or Global Reader
         (required to read call records and directory data).
      2. The Microsoft.Graph.Authentication module (installed automatically if missing).

.PARAMETER TenantId
    Your Azure AD / Entra ID tenant ID. Optional – if omitted the login prompt
    will let you pick the tenant.

.PARAMETER ClientId
    Application (client) ID to use for interactive login.
    Defaults to the well-known Microsoft Graph PowerShell app
    (14d82eec-204b-4c2f-b7e8-296a70dab67e).

.PARAMETER UseDeviceCode
    Use the device-code flow instead of an interactive browser popup.
    Useful for remote / SSH sessions where no browser is available.

.PARAMETER DaysBack
    Number of days to look back for call records (default: 7, max: 30).

.PARAMETER OutputPath
    Path for the CSV report. Defaults to the current directory.

.PARAMETER MinimumCallDurationSeconds
    Ignore calls shorter than this value (filters out test/accidental joins). Default: 60.

.PARAMETER QualityThresholds
    Hashtable of quality thresholds. Metrics exceeding these are flagged as "Poor".

.EXAMPLE
    # Interactive browser sign-in (simplest)
    .\Get-TeamsRoomQuality.ps1

.EXAMPLE
    # Specify tenant + device-code flow for headless sessions
    .\Get-TeamsRoomQuality.ps1 -TenantId "abc-123" -UseDeviceCode

.EXAMPLE
    .\Get-TeamsRoomQuality.ps1 -TenantId "abc-123" -DaysBack 14 -OutputPath "C:\Reports"
#>

[CmdletBinding()]
param(
    [string]$TenantId,

    # Well-known Microsoft Graph PowerShell public client app ID (no secret needed)
    [string]$ClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e',

    [switch]$UseDeviceCode,

    [ValidateRange(1, 30)]
    [int]$DaysBack = 7,

    [string]$OutputPath = (Get-Location).Path,

    [int]$MinimumCallDurationSeconds = 60,

    [hashtable]$QualityThresholds = @{
        AudioJitterMs          = 30      # ms  – Microsoft recommended < 30 ms
        AudioPacketLossPercent = 5       # %   – Microsoft recommended < 5%
        AudioRoundTripMs       = 500     # ms  – Microsoft recommended < 500 ms
        VideoJitterMs          = 30
        VideoPacketLossPercent = 5
        VideoFrameRateLow      = 7       # fps – below this is poor
        ScreenShareJitterMs    = 30
        ScreenSharePacketLoss  = 5
    }
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

#region ── Helper Functions ──────────────────────────────────────────────────────

function Write-Step {
    param([string]$Message)
    Write-Information "▶  $Message"
}

function Write-Detail {
    param([string]$Message)
    Write-Information "   $Message"
}

function Ensure-MgGraphModule {
    <# Install Microsoft.Graph.Authentication if it is not already available. #>
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        Write-Detail "Installing Microsoft.Graph.Authentication module…"
        Install-Module -Name Microsoft.Graph.Authentication -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
}

function Connect-InteractiveGraph {
    <# Sign in interactively (browser popup or device-code) and return an access token. #>
    [CmdletBinding()]
    param(
        [string]$TenantId,
        [string]$ClientId,
        [switch]$UseDeviceCode
    )

    # Scopes required for reading call records and directory info (delegated)
    $scopes = @(
        'CallRecords.Read.All'
        'User.Read.All'
        'Directory.Read.All'
    )

    $connectParams = @{
        Scopes   = $scopes
        ClientId = $ClientId
        NoWelcome = $true
    }

    if ($TenantId) {
        $connectParams['TenantId'] = $TenantId
    }

    if ($UseDeviceCode) {
        $connectParams['UseDeviceCode'] = $true
    }

    Connect-MgGraph @connectParams

    # Retrieve the bearer token from the current MgGraph context
    $token = (Get-MgContext).AuthType  # just for validation
    if (-not (Get-MgContext)) {
        throw "Microsoft Graph authentication failed. Please try again."
    }
}

function Invoke-GraphRequest {
    <# Generic paged Graph API caller using the MgGraph SDK session (no manual token). #>
    [CmdletBinding()]
    param(
        [string]$Uri,
        [hashtable]$Headers,          # kept for signature compat – ignored
        [switch]$SingleObject
    )

    $allResults = [System.Collections.Generic.List[object]]::new()

    do {
        try {
            $response = Invoke-MgGraphRequest -Uri $Uri -Method GET -OutputType PSObject
        }
        catch {
            $statusCode = $null
            if ($_.Exception.Response) {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }
            if ($statusCode -eq 429) {
                # Throttled – respect Retry-After header
                $retryAfter = 30
                try {
                    if ($_.Exception.Response.Headers['Retry-After']) {
                        $retryAfter = [int]$_.Exception.Response.Headers['Retry-After']
                    }
                } catch { }
                Write-Warning "Throttled by Graph API. Waiting $retryAfter seconds..."
                Start-Sleep -Seconds $retryAfter
                continue
            }
            throw
        }

        if ($SingleObject) { return $response }

        if ($response.value) {
            $allResults.AddRange($response.value)
        }
        $Uri = $response.'@odata.nextLink'
    } while ($Uri)

    return $allResults
}

function Get-UserAgentCategory {
    <# Classify a userAgent string into a device category. #>
    param([string]$UserAgent)
    if ([string]::IsNullOrWhiteSpace($UserAgent)) { return 'Unknown' }
    switch -Regex ($UserAgent) {
        'SkypeRoom|Teams Room|MTR|RoomOS|CollabOS|Poly.*Room|Cisco.*Room|Neat|Crestron|Logitech.*Rally|Yealink.*MeetingBar|Surface Hub' { return 'TeamsRoom' }
        'Teams.*Android|Teams.*iOS'       { return 'Mobile' }
        'Teams.*Windows|Teams.*Mac'       { return 'Desktop' }
        'Teams.*Web|Electron'             { return 'Web' }
        default                           { return 'Other' }
    }
}

function Classify-Quality {
    <# Return Poor / Acceptable based on thresholds. #>
    param(
        [string]$Modality,
        [pscustomobject]$Metrics,
        [hashtable]$Thresholds
    )

    $reasons = [System.Collections.Generic.List[string]]::new()

    switch ($Modality) {
        'audio' {
            if ($null -ne $Metrics.Jitter -and $Metrics.Jitter -gt $Thresholds.AudioJitterMs) {
                $reasons.Add("Jitter $($Metrics.Jitter)ms > $($Thresholds.AudioJitterMs)ms")
            }
            if ($null -ne $Metrics.PacketLoss -and $Metrics.PacketLoss -gt $Thresholds.AudioPacketLossPercent) {
                $reasons.Add("PktLoss $($Metrics.PacketLoss)% > $($Thresholds.AudioPacketLossPercent)%")
            }
            if ($null -ne $Metrics.RoundTrip -and $Metrics.RoundTrip -gt $Thresholds.AudioRoundTripMs) {
                $reasons.Add("RTT $($Metrics.RoundTrip)ms > $($Thresholds.AudioRoundTripMs)ms")
            }
        }
        'video' {
            if ($null -ne $Metrics.Jitter -and $Metrics.Jitter -gt $Thresholds.VideoJitterMs) {
                $reasons.Add("Jitter $($Metrics.Jitter)ms > $($Thresholds.VideoJitterMs)ms")
            }
            if ($null -ne $Metrics.PacketLoss -and $Metrics.PacketLoss -gt $Thresholds.VideoPacketLossPercent) {
                $reasons.Add("PktLoss $($Metrics.PacketLoss)% > $($Thresholds.VideoPacketLossPercent)%")
            }
            if ($null -ne $Metrics.FrameRate -and $Metrics.FrameRate -lt $Thresholds.VideoFrameRateLow) {
                $reasons.Add("FPS $($Metrics.FrameRate) < $($Thresholds.VideoFrameRateLow)")
            }
        }
        'screenSharing' {
            if ($null -ne $Metrics.Jitter -and $Metrics.Jitter -gt $Thresholds.ScreenShareJitterMs) {
                $reasons.Add("Jitter $($Metrics.Jitter)ms > $($Thresholds.ScreenShareJitterMs)ms")
            }
            if ($null -ne $Metrics.PacketLoss -and $Metrics.PacketLoss -gt $Thresholds.ScreenSharePacketLoss) {
                $reasons.Add("PktLoss $($Metrics.PacketLoss)% > $($Thresholds.ScreenSharePacketLoss)%")
            }
        }
    }

    if ($reasons.Count -gt 0) {
        return [PSCustomObject]@{ Rating = 'Poor'; Reasons = ($reasons -join '; ') }
    }
    return [PSCustomObject]@{ Rating = 'Good'; Reasons = '' }
}

#endregion

#region ── Main Script ───────────────────────────────────────────────────────────

$scriptStart = Get-Date
Write-Step "Teams Room Call Quality Report"
Write-Detail "Period    : last $DaysBack day(s)"
Write-Detail "Threshold : calls ≥ $MinimumCallDurationSeconds seconds"
Write-Information ''

# ── 1. Authenticate (interactive admin sign-in) ─────────────────────────────
Write-Step "Ensuring Microsoft.Graph.Authentication module is available…"
Ensure-MgGraphModule

Write-Step "Authenticating to Microsoft Graph (interactive sign-in)…"
Connect-InteractiveGraph -TenantId $TenantId -ClientId $ClientId -UseDeviceCode:$UseDeviceCode

$ctx = Get-MgContext
Write-Detail "Signed in as $($ctx.Account) ($($ctx.TenantId))"

# Build REST headers using the SDK's token so we can call the Graph REST API directly
# (the SDK doesn't expose call-records cmdlets in all versions)
$tokenResponse = Invoke-MgGraphRequest -Uri 'https://graph.microsoft.com/v1.0/me' -Method GET -OutputType HttpResponseMessage
# Simpler approach: use Invoke-MgGraphRequest everywhere instead of Invoke-RestMethod
# We'll create a thin wrapper so existing Invoke-GraphRequest still works.
$headers = @{}   # placeholder – we switch to Invoke-MgGraphRequest below
Write-Detail "Token acquired – using delegated permissions."

# ── 2. Discover Teams Room accounts ─────────────────────────────────────────
Write-Step "Discovering Teams Room resource accounts…"

# Teams Room accounts are typically created as room-type mailboxes or have
# specific licenses (MTR Basic / MTR Pro). We query users filtered by
# the Teams Rooms license service plan IDs.
#   MTR Pro  : 4cde982a-ede4-4409-9ae6-b003b28fc240 (servicePlanId)
#   MTR Basic: a]b84acb3-7b9e-4a5e-8f0e-4b317fa9d519 (servicePlanId)
# Fallback: we also flag accounts whose displayName contains "Room" or
# whose userAgent in call records matches room patterns.

$roomAccountIds  = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$roomDisplayNames = @{}

# Approach A – find room-type accounts via directory
$filterDate = (Get-Date).AddDays(-$DaysBack).ToString('yyyy-MM-ddTHH:mm:ssZ')

# Get all users and filter for room resource accounts (roomMailbox type)
$usersUri = "https://graph.microsoft.com/v1.0/users?`$select=id,displayName,userPrincipalName,assignedLicenses,mail&`$top=999"
$allUsers = Invoke-GraphRequest -Uri $usersUri -Headers $headers

# Heuristic: look for common Teams Room naming patterns + license GUIDs
$roomLicenseSkus = @(
    '4cde982a-ede4-4409-9ae6-b003b28fc240'  # MTR Pro
    '6af4b3d6-14bb-4a2a-960c-6c902aad34f3'  # MTR Basic
    'c25e2b36-e161-4946-bef2-69239729f690'  # Common Room System
)

foreach ($user in $allUsers) {
    $isRoom = $false

    # Check license-based identification
    if ($user.assignedLicenses) {
        foreach ($lic in $user.assignedLicenses) {
            if ($roomLicenseSkus -contains $lic.skuId) {
                $isRoom = $true
                break
            }
        }
    }

    # Check naming convention fallback
    if (-not $isRoom) {
        $upn = $user.userPrincipalName
        $dn  = $user.displayName
        if ($upn -match 'room|conf|mtr|meetingroom|boardroom|huddle' -or
            $dn  -match 'room|conf room|meeting room|board room|huddle') {
            $isRoom = $true
        }
    }

    if ($isRoom) {
        [void]$roomAccountIds.Add($user.id)
        $roomDisplayNames[$user.id] = "$($user.displayName) ($($user.userPrincipalName))"
    }
}

Write-Detail "Found $($roomAccountIds.Count) candidate room account(s) in directory."

if ($roomAccountIds.Count -eq 0) {
    Write-Warning @"
No Teams Room accounts detected by license or naming convention.
The script will still scan call records and identify rooms by their userAgent string.
"@
}

# ── 3. Pull Call Records ────────────────────────────────────────────────────
Write-Step "Fetching call records from the last $DaysBack day(s)…"

$startDate = (Get-Date).AddDays(-$DaysBack).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$callsUri  = "https://graph.microsoft.com/v1.0/communications/callRecords?" +
             "`$filter=startDateTime ge $startDate&" +
             "`$orderby=startDateTime desc&" +
             "`$top=100"

$callRecords = Invoke-GraphRequest -Uri $callsUri -Headers $headers
Write-Detail "Retrieved $($callRecords.Count) call record(s)."

# ── 4. Process each call record – find room sessions ────────────────────────
Write-Step "Analysing sessions for Teams Room participants…"

$report = [System.Collections.Generic.List[PSCustomObject]]::new()
$callsWithRooms  = 0
$totalSessions   = 0

foreach ($call in $callRecords) {
    # Skip very short calls
    if ($call.startDateTime -and $call.endDateTime) {
        $duration = ([datetime]$call.endDateTime - [datetime]$call.startDateTime).TotalSeconds
        if ($duration -lt $MinimumCallDurationSeconds) { continue }
    }

    # Get detailed sessions with segments (contains quality metrics)
    $sessionsUri = "https://graph.microsoft.com/v1.0/communications/callRecords/$($call.id)/sessions?" +
                   "`$expand=segments"
    $sessions = Invoke-GraphRequest -Uri $sessionsUri -Headers $headers

    $roomFoundInCall = $false

    foreach ($session in $sessions) {
        $totalSessions++

        foreach ($segment in $session.segments) {
            # Determine if caller or callee is a room
            $callerAgent    = $segment.caller.userAgent.headerValue
            $calleeAgent    = $segment.callee.userAgent.headerValue
            $callerCategory = Get-UserAgentCategory $callerAgent
            $calleeCategory = Get-UserAgentCategory $calleeAgent

            $callerIsRoom = ($callerCategory -eq 'TeamsRoom') -or
                            ($roomAccountIds.Contains($segment.caller.identity.user.id ?? ''))
            $calleeIsRoom = ($calleeCategory -eq 'TeamsRoom') -or
                            ($roomAccountIds.Contains($segment.callee.identity.user.id ?? ''))

            if (-not ($callerIsRoom -or $calleeIsRoom)) { continue }

            $roomFoundInCall = $true

            # Pick the room-side endpoint
            $roomSide = if ($callerIsRoom) { 'caller' } else { 'callee' }
            $roomEndpoint = $segment.$roomSide
            $roomId   = $roomEndpoint.identity.user.id
            $roomName = if ($roomDisplayNames.ContainsKey($roomId)) {
                            $roomDisplayNames[$roomId]
                        } else {
                            $roomEndpoint.identity.user.displayName ?? 'Unknown Room'
                        }
            $roomUA   = $roomEndpoint.userAgent.headerValue

            # ── Extract quality metrics per modality (audio / video / screenSharing)
            $media = $segment.media
            if (-not $media) { continue }

            foreach ($stream in $media) {
                $modality = $stream.label   # audio, video, appSharing / screenSharing

                # Normalise modality label
                $modalityNorm = switch -Regex ($modality) {
                    'audio'          { 'audio' }
                    'video|mainVideo'{ 'video' }
                    'appSharing|screenSharing|vbss' { 'screenSharing' }
                    default          { $modality }
                }

                # Outbound (from room) metrics  ← the room's sending quality
                $outJitter    = $stream.callerNetwork.jitter?.average ??
                                $stream.callerNetwork.jitter ??
                                $null
                $outPktLoss   = $stream.callerNetwork.packetLossRate ??
                                $stream.callerNetwork.packetLossRateMax ??
                                $null
                $outRoundTrip = $stream.callerNetwork.roundTripTime?.average ??
                                $stream.callerNetwork.roundTripTime ??
                                $null

                # Inbound (to room) metrics  ← what the room receives
                $inJitter     = $stream.calleeNetwork.jitter?.average ??
                                $stream.calleeNetwork.jitter ??
                                $null
                $inPktLoss    = $stream.calleeNetwork.packetLossRate ??
                                $stream.calleeNetwork.packetLossRateMax ??
                                $null
                $inRoundTrip  = $stream.calleeNetwork.roundTripTime?.average ??
                                $stream.calleeNetwork.roundTripTime ??
                                $null

                # When the room is the caller, outbound = room-send, inbound = room-receive
                # When the room is the callee, swap
                if ($roomSide -eq 'callee') {
                    $sendJitter    = $inJitter
                    $sendPktLoss   = $inPktLoss
                    $sendRTT       = $inRoundTrip
                    $recvJitter    = $outJitter
                    $recvPktLoss   = $outPktLoss
                    $recvRTT       = $outRoundTrip
                } else {
                    $sendJitter    = $outJitter
                    $sendPktLoss   = $outPktLoss
                    $sendRTT       = $outRoundTrip
                    $recvJitter    = $inJitter
                    $recvPktLoss   = $inPktLoss
                    $recvRTT       = $inRoundTrip
                }

                # Frame-rate (video / screenshare)
                $avgFrameRate = $stream.averageVideoFrameRate ?? $null

                # Overall quality classification
                $metrics = [PSCustomObject]@{
                    Jitter     = [math]::Round(([double]($sendJitter ?? $recvJitter ?? 0)), 2)
                    PacketLoss = [math]::Round(([double]($sendPktLoss ?? $recvPktLoss ?? 0)) * 100, 2)
                    RoundTrip  = [math]::Round(([double]($sendRTT ?? $recvRTT ?? 0)), 2)
                    FrameRate  = $avgFrameRate
                }
                $quality = Classify-Quality -Modality $modalityNorm -Metrics $metrics -Thresholds $QualityThresholds

                $row = [PSCustomObject]@{
                    CallId                = $call.id
                    CallType              = $call.type ?? 'unknown'
                    StartTime             = $call.startDateTime
                    EndTime               = $call.endDateTime
                    DurationMinutes       = [math]::Round(
                                                (([datetime]($call.endDateTime) -
                                                  [datetime]($call.startDateTime)).TotalMinutes), 1)
                    RoomName              = $roomName
                    RoomUserId            = $roomId
                    RoomUserAgent         = $roomUA
                    Modality              = $modalityNorm
                    SendJitterMs          = [math]::Round(([double]($sendJitter  ?? 0)), 2)
                    SendPacketLossPct     = [math]::Round(([double]($sendPktLoss ?? 0)) * 100, 2)
                    SendRoundTripMs       = [math]::Round(([double]($sendRTT     ?? 0)), 2)
                    RecvJitterMs          = [math]::Round(([double]($recvJitter  ?? 0)), 2)
                    RecvPacketLossPct     = [math]::Round(([double]($recvPktLoss ?? 0)) * 100, 2)
                    RecvRoundTripMs       = [math]::Round(([double]($recvRTT     ?? 0)), 2)
                    AvgFrameRate          = $avgFrameRate
                    QualityRating         = $quality.Rating
                    QualityIssues         = $quality.Reasons
                    RemoteParticipant     = if ($roomSide -eq 'caller') {
                                                $segment.callee.identity.user.displayName ?? 'n/a'
                                            } else {
                                                $segment.caller.identity.user.displayName ?? 'n/a'
                                            }
                    NetworkType           = $roomEndpoint.networkConnectionType ?? 'n/a'
                    WifiBand              = $roomEndpoint.wifiBand ?? 'n/a'
                    Subnet                = $roomEndpoint.ipAddress ?? 'n/a'
                }
                $report.Add($row)
            }
        }
    }

    if ($roomFoundInCall) { $callsWithRooms++ }
}

Write-Detail "Processed $totalSessions session(s) across $($callRecords.Count) call(s)."
Write-Detail "Calls involving a Teams Room: $callsWithRooms"
Write-Detail "Total quality data rows: $($report.Count)"
Write-Information ''

# ── 5. Generate Reports ─────────────────────────────────────────────────────
Write-Step "Generating reports…"

if ($report.Count -eq 0) {
    Write-Warning "No Teams Room call data found in the selected period."
    return
}

# 5a. Detailed CSV
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$csvPath   = Join-Path $OutputPath "TeamsRoomQuality_Detail_$timestamp.csv"
$report | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
Write-Detail "Detail CSV  → $csvPath"

# 5b. Summary by Room
$summaryByRoom = $report | Group-Object RoomName | ForEach-Object {
    $grp = $_.Group
    $audio = $grp | Where-Object Modality -eq 'audio'
    $poor  = $grp | Where-Object QualityRating -eq 'Poor'
    [PSCustomObject]@{
        RoomName           = $_.Name
        TotalCalls         = ($grp | Select-Object -Unique CallId).Count
        TotalStreams        = $grp.Count
        PoorStreams         = $poor.Count
        PoorPct            = [math]::Round(($poor.Count / [math]::Max($grp.Count,1)) * 100, 1)
        AvgAudioJitterMs   = [math]::Round(($audio | Measure-Object SendJitterMs  -Average).Average, 2)
        AvgAudioPktLossPct = [math]::Round(($audio | Measure-Object SendPacketLossPct -Average).Average, 2)
        AvgAudioRTTMs      = [math]::Round(($audio | Measure-Object SendRoundTripMs   -Average).Average, 2)
        MostCommonIssue    = if ($poor.Count -gt 0) {
                                ($poor.QualityIssues | Group-Object | Sort-Object Count -Descending |
                                 Select-Object -First 1).Name
                             } else { 'None' }
    }
}

$summaryCsv = Join-Path $OutputPath "TeamsRoomQuality_Summary_$timestamp.csv"
$summaryByRoom | Export-Csv -Path $summaryCsv -NoTypeInformation -Encoding UTF8
Write-Detail "Summary CSV → $summaryCsv"

# 5c. Console summary
Write-Information ''
Write-Step "═══ Room Quality Summary ═══"
Write-Information ''
$summaryByRoom | Format-Table -AutoSize -Property RoomName,TotalCalls,TotalStreams,PoorStreams,
                                                   @{N='Poor%';E={$_.PoorPct}},
                                                   AvgAudioJitterMs,AvgAudioPktLossPct,AvgAudioRTTMs,
                                                   MostCommonIssue |
    Out-String | ForEach-Object { Write-Information $_ }

# 5d. Overall health score
$totalStreams = $report.Count
$poorStreams  = ($report | Where-Object QualityRating -eq 'Poor').Count
$goodPct     = [math]::Round((($totalStreams - $poorStreams) / [math]::Max($totalStreams,1)) * 100, 1)

$healthEmoji = switch ($true) {
    ($goodPct -ge 95) { '🟢' }
    ($goodPct -ge 80) { '🟡' }
    default           { '🔴' }
}

Write-Information ''
Write-Step "Overall Room Health: $healthEmoji $goodPct% streams rated Good ($($totalStreams - $poorStreams) / $totalStreams)"

# 5e. Top offenders
if ($poorStreams -gt 0) {
    Write-Information ''
    Write-Step "Top rooms with quality issues:"
    $summaryByRoom | Where-Object PoorPct -gt 0 |
        Sort-Object PoorPct -Descending |
        Select-Object -First 10 |
        Format-Table -AutoSize RoomName, PoorStreams, @{N='Poor%';E={$_.PoorPct}}, MostCommonIssue |
        Out-String | ForEach-Object { Write-Information $_ }
}

$elapsed = (Get-Date) - $scriptStart
Write-Information ''
Write-Step "Done in $([math]::Round($elapsed.TotalSeconds, 1)) seconds."

# Clean up Graph session
try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch { }

#endregion
