<#
.SYNOPSIS
    Retrieves Microsoft Teams Room call quality data from the CQD REST API
    with interactive sign-in (popup window).

.DESCRIPTION
    This script authenticates via the OAuth 2.0 implicit flow using CQD's
    own first-party web application, then queries the Call Quality Dashboard
    (CQD) REST API for media streams involving Teams Room endpoints.

    A small sign-in popup window appears; after you authenticate it closes
    automatically and the script continues.  No app registration, client
    secret, or extra PowerShell module is required.

    CQD provides per-stream quality data (Good / Poor) based on Microsoft's
    thresholds, plus detailed metrics such as jitter, packet loss, and
    round-trip time.

    Prerequisites
    ─────────────
    • The signed-in user must hold one of these Entra ID roles:
        – Teams Administrator
        – Teams Communications Administrator
        – Global Reader
    • No app registration, client secret, or extra module is required.

.PARAMETER DaysBack
    Number of days to look back (default: 7, max: 30).

.PARAMETER OutputPath
    Folder for the CSV reports.  Defaults to the current directory.

.PARAMETER MinimumCallDurationSeconds
    Minimum call duration filter (default 60).  CQD supports a built-in
    60-second threshold; values below 60 are effectively ignored.

.PARAMETER QualityThresholds
    Hashtable of quality thresholds for an additional classification layer
    on top of CQD's built-in Good / Poor rating.

.EXAMPLE
    .\Get-TeamsRoomQuality.ps1

.EXAMPLE
    .\Get-TeamsRoomQuality.ps1 -DaysBack 14 -OutputPath "C:\Reports"
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 30)]
    [int]$DaysBack = 7,

    [string]$OutputPath = (Get-Location).Path,

    [int]$MinimumCallDurationSeconds = 60,

    [hashtable]$QualityThresholds = @{
        AudioJitterMs          = 30
        AudioPacketLossPercent = 5
        AudioRoundTripMs       = 500
        VideoJitterMs          = 30
        VideoPacketLossPercent = 5
        VideoFrameRateLow      = 7
        ScreenShareJitterMs    = 30
        ScreenSharePacketLoss  = 5
    }
)

##Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

#region ── Helper Functions ──────────────────────────────────────────────────────

function Write-Step  { param([string]$Message) Write-Information "▶  $Message" }
function Write-Detail { param([string]$Message) Write-Information "   $Message" }

# ─── Token Cache ────────────────────────────────────────────────────────────

$script:TokenCachePath = Join-Path $env:LOCALAPPDATA 'CQDPowerShell_TokenCache.json'

function Get-CachedCqdToken {
    <# Return the cached token if it exists and is still valid (5-min margin). #>
    if (-not (Test-Path $script:TokenCachePath)) { return $null }

    try {
        $cache = Get-Content $script:TokenCachePath -Raw | ConvertFrom-Json
        $expiry = [DateTimeOffset]::FromUnixTimeSeconds([long]$cache.ExpiresOn)
        $margin = [TimeSpan]::FromMinutes(5)

        if ($expiry -gt ([DateTimeOffset]::UtcNow + $margin)) {
            Write-Detail "Using cached token (expires $($expiry.LocalDateTime.ToString('HH:mm:ss')))." 
            return $cache
        }
        Write-Detail "Cached token expired – will re-authenticate."
    }
    catch {
        Write-Detail "Token cache unreadable – will re-authenticate."
    }
    return $null
}

function Save-CqdTokenCache {
    <# Persist token + metadata to a local JSON file. #>
    param(
        [string]$AccessToken,
        [long]$ExpiresOn,
        [string]$DataServiceUrl
    )
    $obj = [ordered]@{
        AccessToken    = $AccessToken
        ExpiresOn      = $ExpiresOn
        DataServiceUrl = $DataServiceUrl
    }
    $obj | ConvertTo-Json | Set-Content $script:TokenCachePath -Encoding UTF8 -Force
    Write-Detail "Token cached to $script:TokenCachePath"
}

# ─── Authentication ─────────────────────────────────────────────────────────

function Get-CqdAccessToken {
    <#
    .SYNOPSIS  Obtain a bearer token for the CQD API via implicit-flow sign-in.
    .NOTES
        The CQD resource only accepts tokens from its own first-party web app
        (c61d67cf-295a-462c-972f-33af37008751).  That app uses the OAuth 2.0
        implicit flow with redirect_uri = https://cqd.teams.microsoft.com/spd/.

        We replicate what the MSTeamsCQD module does, except we change
        prompt=none → prompt=select_account so the user gets a real login page
        instead of a silent failure.

        A small WinForms WebBrowser popup is used to capture the token from the
        redirect URL fragment.  This works in both Windows PowerShell 5.1 and
        PowerShell 7 on Windows.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Resource,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$RedirectUri
    )

    Add-Type -AssemblyName System.Web
    Add-Type -AssemblyName System.Windows.Forms

    $nonce   = [guid]::NewGuid().GUID
    $authUrl = "https://login.microsoftonline.com/common/oauth2/authorize?" +
        "response_type=token" +
        "&client_id=$ClientId" +
        "&redirect_uri=$([System.Web.HttpUtility]::UrlEncode($RedirectUri))" +
        "&resource=$([System.Web.HttpUtility]::UrlEncode($Resource))" +
        "&prompt=select_account" +
        "&nonce=$nonce"

    # ── Build a WinForms dialog with an embedded WebBrowser ─────────────────
    $form = New-Object System.Windows.Forms.Form -Property @{
        Width  = 480; Height = 680
        Text   = 'Sign in – CQD Call Quality'
        StartPosition = 'CenterScreen'
    }
    $web = New-Object System.Windows.Forms.WebBrowser -Property @{
        Width  = 460; Height = 640
        Dock   = 'Fill'
    }

    $web.ScriptErrorsSuppressed = $true

    # Use a Global variable so the event handlers can reliably communicate back.
    $Global:_CqdAuthUri = $null

    # ── The WinForms WebBrowser (IE engine) does NOT expose URL fragments
    #    (#access_token=…) through its Navigating/Navigated/DocumentCompleted
    #    event args.  The fragment is only accessible via JavaScript inside
    #    the loaded document.
    #
    #    Strategy: use a 500 ms Timer to poll document.location.hash.  As
    #    soon as the implicit-flow redirect lands on the CQD SPA page, the
    #    hash contains the token.  We grab it and close the form.

    $timer = New-Object System.Windows.Forms.Timer -Property @{ Interval = 500 }
    $timer.Add_Tick({
        try {
            $hash = $web.Document.InvokeScript('eval', @('document.location.hash'))
            if ($hash -and ($hash -match 'access_token=' -or $hash -match 'error=')) {
                $Global:_CqdAuthUri = $hash
                $timer.Stop()
                $form.Close()
            }
        }
        catch {
            # Document not ready yet – keep polling
        }
    })

    $form.Controls.Add($web)
    $form.Add_Shown({
        $form.Activate()
        $timer.Start()
    })

    Write-Detail "Opening sign-in window…"
    Write-Information ''
    Write-Information '   ┌─────────────────────────────────────────────────────┐'
    Write-Information '   │  Sign in with your Teams Admin account in the       │'
    Write-Information '   │  popup window.  It will close automatically.        │'
    Write-Information '   └─────────────────────────────────────────────────────┘'
    Write-Information ''

    $web.Navigate($authUrl)
    [void]$form.ShowDialog()

    $timer.Stop()
    $timer.Dispose()

    # The captured value is the hash fragment string (e.g. "#access_token=…")
    $hashFragment = $Global:_CqdAuthUri

    # Fallback: try reading from DOM one last time
    if (-not $hashFragment -or $hashFragment -notmatch 'access_token=|error=') {
        try {
            $hashFragment = $web.Document.InvokeScript('eval', @('document.location.hash'))
        } catch {}
    }

    if (-not $hashFragment) { $hashFragment = '' }

    $web.Dispose()
    $form.Dispose()
    Remove-Variable -Name '_CqdAuthUri' -Scope Global -ErrorAction SilentlyContinue

    # ── Parse the token from the hash fragment ──────────────────────────────
    # Strip the leading '#' if present
    $fragString = $hashFragment -replace '^#', ''

    if ($fragString -match 'error=') {
        $fragParts = [System.Web.HttpUtility]::ParseQueryString($fragString)
        $errDesc   = $fragParts['error_description']
        throw "Azure AD sign-in error: $($fragParts['error'])`n$errDesc"
    }

    if ($fragString -match 'access_token=') {
        $parts     = [System.Web.HttpUtility]::ParseQueryString($fragString)
        $token     = $parts['access_token']
        $expiresIn = $parts['expires_in']   # seconds from now

        if ($token) {
            $expiresOn = [DateTimeOffset]::UtcNow.AddSeconds([int]$expiresIn).ToUnixTimeSeconds()
            Write-Detail "✓ Token acquired (valid for $expiresIn s)."
            return [PSCustomObject]@{ AccessToken = $token; ExpiresOn = $expiresOn }
        }
    }

    throw "Sign-in was cancelled or no token was returned."
}

function Connect-CqdService {
    <#
    .SYNOPSIS  Authenticate and discover the CQD DataService endpoint.
    .OUTPUTS   PSCustomObject with .WebSession and .DataServiceUrl
    #>
    [CmdletBinding()]
    param()

    # 1. Check for a valid cached token
    $cached = Get-CachedCqdToken
    if ($cached) {
        $webSession = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
        $webSession.Headers['Authorization'] = "Bearer $($cached.AccessToken)"
        return [PSCustomObject]@{
            WebSession     = $webSession
            DataServiceUrl = $cached.DataServiceUrl
        }
    }

    # 2. Fetch CQD client configuration (public, no auth needed)
    $configUrl = 'https://cqd.teams.microsoft.com/repository/clientconfiguration'
    $config    = Invoke-RestMethod -Uri $configUrl -Method Get `
                     -SessionVariable webSession -UserAgent 'CQDPowerShell V2.0'

    $resource  = $config.AuthLoginResource        # https://cqd.teams.cloud.microsoft
    $repoUrl   = $config.RepositoryApiBaseUrl      # https://cqd.teams.cloud.microsoft/repository/
    $clientId  = $config.AuthWebAppClientId         # c61d67cf-295a-462c-972f-33af37008751

    Write-Detail "CQD resource : $resource"
    Write-Detail "Repository   : $repoUrl"

    # 3. Get a bearer token via implicit-flow popup
    $authResult = Get-CqdAccessToken -Resource $resource -ClientId $clientId `
                      -RedirectUri 'https://cqd.teams.microsoft.com/spd/'

    # 4. Build an authenticated WebSession
    $webSession.Headers['Authorization'] = "Bearer $($authResult.AccessToken)"

    # 5. Check tenant provisioning
    $provUri    = '{0}tenant/provision' -f $repoUrl
    $provStatus = Invoke-RestMethod -Uri $provUri -WebSession $webSession `
                      -Method Get -UserAgent 'CQDPowerShell V2.0'

    if ($provStatus.Status -ne 'Provisioned') {
        throw ("CQD is not provisioned for tenant {0} (status: {1}).`n" +
               "Open https://cqd.teams.microsoft.com in a browser first to provision.") `
              -f $provStatus.TenantId, $provStatus.Status
    }
    Write-Detail "Tenant $($provStatus.TenantId) is provisioned."

    # 6. Discover the tenant-specific DataService URL
    $dsUri          = '{0}tenant/dataservice' -f $repoUrl
    $dataServiceUrl = Invoke-RestMethod -Uri $dsUri -WebSession $webSession `
                          -Method Get -UserAgent 'CQDPowerShell V2.0'

    # 7. Cache the token + DataService URL for subsequent runs
    Save-CqdTokenCache -AccessToken $authResult.AccessToken `
                       -ExpiresOn $authResult.ExpiresOn `
                       -DataServiceUrl $dataServiceUrl

    return [PSCustomObject]@{
        WebSession     = $webSession
        DataServiceUrl = $dataServiceUrl
    }
}

# ─── CQD Query Execution ───────────────────────────────────────────────────

function Invoke-CqdQuery {
    <# Execute a query against the CQD DataService RunQuery endpoint. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DataServiceUrl,
        [Parameter(Mandatory)][Microsoft.PowerShell.Commands.WebRequestSession]$WebSession,
        [Parameter(Mandatory)][hashtable]$QueryBody
    )

    $uri  = "${DataServiceUrl}RunQuery"
    $body = $QueryBody | ConvertTo-Json -Depth 10 -Compress

    try {
        $response = Invoke-RestMethod -Uri $uri -Method POST `
                        -WebSession $WebSession -Body $body `
                        -ContentType 'application/json' -UserAgent 'CQDPowerShell V2.0'
    }
    catch {
        $status = $null
        try { $status = $_.Exception.Response.StatusCode.value__ } catch {}
        if ($status -eq 401 -or $status -eq 403) {
            throw "CQD API returned $status – ensure the signed-in account has a Teams Admin role."
        }
        throw
    }

    
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    write-host "$($response|out-string) " -ForegroundColor Green
    $global:r=$response
    
    if ($null -ne $response -and $null -ne $response.PSObject.Properties['Rows'] -and $response.Rows.Count -gt 0) {
        $columns = $response.Columns
        foreach ($row in $response.Rows) {
            $obj = [ordered]@{}
            for ($i = 0; $i -lt $columns.Count; $i++) {
                $obj[$columns[$i].ColumnName] = $row[$i]
            }
            $results.Add([PSCustomObject]$obj)
        }
    }
    else {
        Write-Warning "CQD query returned no rows."
    }
    return $results
}

# ─── Room Detection & Quality Classification ───────────────────────────────

function Test-IsRoomAgent {
    param([string]$Category)
    if ([string]::IsNullOrWhiteSpace($Category)) { return $false }
    return $Category -match 'MTR|Room|SurfaceHub|CollabBar|IP.?Phone|Conference.?Phone'
}

function Classify-Quality {
    param(
        [string]$Modality,
        [double]$AvgJitter,
        [double]$AvgPacketLossRate,
        [double]$AvgRoundTrip,
        [hashtable]$Thresholds
    )
    $reasons    = [System.Collections.Generic.List[string]]::new()
    $pktLossPct = [math]::Round($AvgPacketLossRate * 100, 2)

    switch -Regex ($Modality) {
        'Audio' {
            if ($AvgJitter    -gt $Thresholds.AudioJitterMs)          { $reasons.Add("Jitter $([math]::Round($AvgJitter,1))ms > $($Thresholds.AudioJitterMs)ms") }
            if ($pktLossPct   -gt $Thresholds.AudioPacketLossPercent) { $reasons.Add("PktLoss ${pktLossPct}% > $($Thresholds.AudioPacketLossPercent)%") }
            if ($AvgRoundTrip -gt $Thresholds.AudioRoundTripMs)       { $reasons.Add("RTT $([math]::Round($AvgRoundTrip,1))ms > $($Thresholds.AudioRoundTripMs)ms") }
        }
        'Video' {
            if ($AvgJitter  -gt $Thresholds.VideoJitterMs)            { $reasons.Add("Jitter $([math]::Round($AvgJitter,1))ms > $($Thresholds.VideoJitterMs)ms") }
            if ($pktLossPct -gt $Thresholds.VideoPacketLossPercent)   { $reasons.Add("PktLoss ${pktLossPct}% > $($Thresholds.VideoPacketLossPercent)%") }
        }
        'AppSharing|VBSS' {
            if ($AvgJitter  -gt $Thresholds.ScreenShareJitterMs)      { $reasons.Add("Jitter $([math]::Round($AvgJitter,1))ms > $($Thresholds.ScreenShareJitterMs)ms") }
            if ($pktLossPct -gt $Thresholds.ScreenSharePacketLoss)    { $reasons.Add("PktLoss ${pktLossPct}% > $($Thresholds.ScreenSharePacketLoss)%") }
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
Write-Step "Teams Room Call Quality Report (CQD)"
Write-Detail "Period    : last $DaysBack day(s)"
Write-Detail "Threshold : calls ≥ $MinimumCallDurationSeconds seconds"
Write-Information ''

# ── 1. Authenticate to CQD ─────────────────────────────────────────────────
Write-Step "Connecting to CQD (browser sign-in)…"
$cqd            = Connect-CqdService
$webSession     = $cqd.WebSession
$dataServiceUrl = $cqd.DataServiceUrl

Write-Detail "DataService URL: $dataServiceUrl"

# ── 2. Build & execute CQD queries ─────────────────────────────────────────
Write-Step "Querying CQD for the last $DaysBack day(s)…"

$endDate   = (Get-Date).ToString('yyyy-MM-dd')
$startDate = (Get-Date).AddDays(-$DaysBack).ToString('yyyy-MM-dd')

$filters = @(
    @{ DataModelName = '[AllStreams].[Is Teams]'
       Caption = 'IsTeams'; Value = '[1]'; Operand = 0 }
)
if ($MinimumCallDurationSeconds -ge 60) {
    $filters += @{
        DataModelName = '[AllStreams].[Duration 60 seconds or more]'
        Caption = 'Duration60s'; Value = '[1]'; Operand = 0
    }
}

$measurements = @(
    @{ DataModelName = '[Measures].[Total Stream Count]' }
    @{ DataModelName = '[Measures].[Audio Poor Stream Count]' }
    @{ DataModelName = '[Measures].[Audio Good Stream Count]' }
    @{ DataModelName = '[Measures].[Audio Poor Percentage]' }
    @{ DataModelName = '[Measures].[Video Poor Stream Count]' }
    @{ DataModelName = '[Measures].[Video Good Stream Count]' }
    @{ DataModelName = '[Measures].[Video Poor Percentage]' }
    @{ DataModelName = '[Measures].[Avg Jitter]' }
    @{ DataModelName = '[Measures].[Avg Packet Loss Rate]' }
    @{ DataModelName = '[Measures].[Avg Round Trip]' }
)

Write-Detail "Querying Second-endpoint streams…"
$querySecond = @{
    Filters      = $filters
    Dimensions   = @(
        @{ DataModelName = '[AllStreams].[Second UPN]' }
        @{ DataModelName = '[AllStreams].[Second User Agent Category]' }
        @{ DataModelName = '[AllStreams].[Media Type]' }
        @{ DataModelName = '[AllStreams].[Second Network Connection Detail]' }
    )
    Measurements = $measurements
    StartDate    = $startDate
    EndDate      = $endDate
}
$secondRows = Invoke-CqdQuery -DataServiceUrl $dataServiceUrl -WebSession $webSession -QueryBody $querySecond

Write-Detail "Querying First-endpoint streams…"
$queryFirst = @{
    Filters      = $filters
    Dimensions   = @(
        @{ DataModelName = '[AllStreams].[First UPN]' }
        @{ DataModelName = '[AllStreams].[First User Agent Category]' }
        @{ DataModelName = '[AllStreams].[Media Type]' }
        @{ DataModelName = '[AllStreams].[First Network Connection Detail]' }
    )
    Measurements = $measurements
    StartDate    = $startDate
    EndDate      = $endDate
}
$firstRows = Invoke-CqdQuery -DataServiceUrl $dataServiceUrl -WebSession $webSession -QueryBody $queryFirst

Write-Detail "CQD returned $($secondRows.Count) Second-endpoint rows + $($firstRows.Count) First-endpoint rows."

# ── 3. Filter for Teams Room endpoints ──────────────────────────────────────
Write-Step "Identifying Teams Room endpoints…"

$allRoomRows = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($row in $secondRows) {
    $agentCat = $row.'Second User Agent Category'
    if (Test-IsRoomAgent $agentCat) {
        $allRoomRows.Add([PSCustomObject]@{
            RoomUPN           = $row.'Second UPN'
            UserAgentCategory = $agentCat
            MediaType         = $row.'Media Type'
            NetworkType       = $row.'Second Network Connection Detail'
            TotalStreams      = [int]($row.'Total Stream Count')
            AudioPoorStreams  = [int]($row.'Audio Poor Stream Count')
            AudioGoodStreams  = [int]($row.'Audio Good Stream Count')
            AudioPoorPct      = [double]($row.'Audio Poor Percentage')
            VideoPoorStreams  = [int]($row.'Video Poor Stream Count')
            VideoGoodStreams  = [int]($row.'Video Good Stream Count')
            VideoPoorPct      = [double]($row.'Video Poor Percentage')
            AvgJitterMs       = [math]::Round([double]($row.'Avg Jitter'), 2)
            AvgPacketLossRate = [math]::Round([double]($row.'Avg Packet Loss Rate'), 4)
            AvgRoundTripMs    = [math]::Round([double]($row.'Avg Round Trip'), 2)
            EndpointSide      = 'Second'
        })
    }
}

foreach ($row in $firstRows) {
    $agentCat = $row.'First User Agent Category'
    if (Test-IsRoomAgent $agentCat) {
        $allRoomRows.Add([PSCustomObject]@{
            RoomUPN           = $row.'First UPN'
            UserAgentCategory = $agentCat
            MediaType         = $row.'Media Type'
            NetworkType       = $row.'First Network Connection Detail'
            TotalStreams      = [int]($row.'Total Stream Count')
            AudioPoorStreams  = [int]($row.'Audio Poor Stream Count')
            AudioGoodStreams  = [int]($row.'Audio Good Stream Count')
            AudioPoorPct      = [double]($row.'Audio Poor Percentage')
            VideoPoorStreams  = [int]($row.'Video Poor Stream Count')
            VideoGoodStreams  = [int]($row.'Video Good Stream Count')
            VideoPoorPct      = [double]($row.'Video Poor Percentage')
            AvgJitterMs       = [math]::Round([double]($row.'Avg Jitter'), 2)
            AvgPacketLossRate = [math]::Round([double]($row.'Avg Packet Loss Rate'), 4)
            AvgRoundTripMs    = [math]::Round([double]($row.'Avg Round Trip'), 2)
            EndpointSide      = 'First'
        })
    }
}

Write-Detail "Found $($allRoomRows.Count) room-related aggregate row(s)."

if ($allRoomRows.Count -eq 0) {
    Write-Warning "No Teams Room streams found in CQD for the selected period."
    Write-Warning "Ensure room devices are active and their User Agent is recognized."
    $categories = @($secondRows | ForEach-Object { $_.'Second User Agent Category' } |
                    Sort-Object -Unique | Where-Object { $_ })
    if ($categories.Count -gt 0) {
        Write-Detail "Discovered User Agent Categories (use these to verify room detection):"
        $categories | ForEach-Object { Write-Detail "  • $_" }
    }
    return
}

# ── 4. Apply custom quality classification ──────────────────────────────────
Write-Step "Classifying stream quality…"

$report = foreach ($row in $allRoomRows) {
    $quality = Classify-Quality -Modality $row.MediaType `
                                -AvgJitter $row.AvgJitterMs `
                                -AvgPacketLossRate $row.AvgPacketLossRate `
                                -AvgRoundTrip $row.AvgRoundTripMs `
                                -Thresholds $QualityThresholds

    $row | Add-Member -NotePropertyName 'PacketLossPct'  -NotePropertyValue ([math]::Round($row.AvgPacketLossRate * 100, 2)) -PassThru |
           Add-Member -NotePropertyName 'CustomRating'   -NotePropertyValue $quality.Rating  -PassThru |
           Add-Member -NotePropertyName 'CustomIssues'   -NotePropertyValue $quality.Reasons -PassThru
}

# ── 5. Generate Reports ─────────────────────────────────────────────────────
Write-Step "Generating reports…"

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

# 5a. Detailed CSV
$csvPath = Join-Path $OutputPath "TeamsRoomQuality_CQD_Detail_$timestamp.csv"
$report | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
Write-Detail "Detail CSV  → $csvPath"

# 5b. Summary by Room
$summaryByRoom = $report | Group-Object RoomUPN | ForEach-Object {
    $grp          = $_.Group
    $audio        = $grp | Where-Object MediaType -eq 'Audio'
    $totalStreams  = ($grp | Measure-Object TotalStreams -Sum).Sum
    $poorAudio    = ($grp | Measure-Object AudioPoorStreams -Sum).Sum
    $poorVideo    = ($grp | Measure-Object VideoPoorStreams -Sum).Sum
    $totalPoor    = $poorAudio + $poorVideo

    [PSCustomObject]@{
        RoomUPN            = $_.Name
        DeviceType         = ($grp | Select-Object -First 1).UserAgentCategory
        NetworkType        = ($grp | Select-Object -First 1).NetworkType
        TotalStreams       = $totalStreams
        AudioPoorStreams   = $poorAudio
        VideoPoorStreams   = $poorVideo
        PoorPct            = if ($totalStreams -gt 0) {
                                 [math]::Round(($totalPoor / $totalStreams) * 100, 1)
                             } else { 0 }
        AvgAudioJitterMs   = [math]::Round(($audio | Measure-Object AvgJitterMs       -Average).Average, 2)
        AvgAudioPktLossPct = [math]::Round((($audio | Measure-Object AvgPacketLossRate -Average).Average) * 100, 2)
        AvgAudioRTTMs      = [math]::Round(($audio | Measure-Object AvgRoundTripMs     -Average).Average, 2)
        TopIssue           = ($grp | Where-Object CustomRating -eq 'Poor' |
                              ForEach-Object { $_.CustomIssues } |
                              Group-Object | Sort-Object Count -Descending |
                              Select-Object -First 1).Name
    }
}

$summaryCsv = Join-Path $OutputPath "TeamsRoomQuality_CQD_Summary_$timestamp.csv"
$summaryByRoom | Export-Csv -Path $summaryCsv -NoTypeInformation -Encoding UTF8
Write-Detail "Summary CSV → $summaryCsv"

# 5c. Console summary
Write-Information ''
Write-Step "═══ Room Quality Summary (CQD) ═══"
Write-Information ''
$summaryByRoom | Format-Table -AutoSize -Property RoomUPN, DeviceType, TotalStreams,
                                                   AudioPoorStreams, VideoPoorStreams,
                                                   @{N='Poor%';E={$_.PoorPct}},
                                                   AvgAudioJitterMs, AvgAudioPktLossPct,
                                                   AvgAudioRTTMs, TopIssue |
    Out-String | ForEach-Object { Write-Information $_ }

# 5d. Overall health score
$totalAllStreams = ($report | Measure-Object TotalStreams -Sum).Sum
$totalPoorAll   = ($report | Measure-Object AudioPoorStreams -Sum).Sum +
                  ($report | Measure-Object VideoPoorStreams -Sum).Sum
$goodPct = if ($totalAllStreams -gt 0) {
               [math]::Round((($totalAllStreams - $totalPoorAll) / $totalAllStreams) * 100, 1)
           } else { 100 }

$healthEmoji = switch ($true) {
    ($goodPct -ge 95) { '🟢' }
    ($goodPct -ge 80) { '🟡' }
    default           { '🔴' }
}

Write-Information ''
Write-Step "Overall Room Health: $healthEmoji $goodPct% streams rated Good ($($totalAllStreams - $totalPoorAll) / $totalAllStreams)"

# 5e. Top offenders
if ($totalPoorAll -gt 0) {
    Write-Information ''
    Write-Step "Top rooms with quality issues:"
    $summaryByRoom | Where-Object PoorPct -gt 0 |
        Sort-Object PoorPct -Descending |
        Select-Object -First 10 |
        Format-Table -AutoSize RoomUPN, AudioPoorStreams, VideoPoorStreams,
                               @{N='Poor%';E={$_.PoorPct}}, TopIssue |
        Out-String | ForEach-Object { Write-Information $_ }
}

$elapsed = (Get-Date) - $scriptStart
Write-Information ''
Write-Step "Done in $([math]::Round($elapsed.TotalSeconds, 1)) seconds."

#endregion
