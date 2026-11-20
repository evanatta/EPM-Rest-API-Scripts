function Stop-Epm {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Red
    exit 1
}
function Get-EpmBaseUrl {
    param([string]$Prompt)
    $value = (Read-Host $Prompt).Trim()
    if ($value -notmatch '^[a-z][a-z0-9+.-]*://') { $value = "https://$value" }
    $parsed = $null
    if (-not [Uri]::TryCreate($value, [UriKind]::Absolute, [ref]$parsed)) { Stop-Epm 'That is not a valid URL. Enter the EPM API URL for your region, for example https://api-na.epm.cyberark.cloud' }
    $hostName = $parsed.Host.ToLowerInvariant()
    if ($parsed.Scheme -ne 'https') { Stop-Epm 'The EPM base URL must start with https://' }
    if ($hostName -notmatch '^api-[a-z0-9-]+\.epm\.cyberark\.cloud$' -and $hostName -notmatch '^[a-z]+[0-9]+\.epm\.cyberark\.com$' -and $hostName -notmatch '^([a-z0-9-]+\.)+epm\.cyberarkgov\.cloud$') {
        if ($hostName.EndsWith('.cyberark.cloud')) { Stop-Epm 'That looks like an Identity URL. Enter the EPM API URL for your region, for example https://api-na.epm.cyberark.cloud' }
        Stop-Epm 'That is not an EPM API address. Enter the EPM API URL for your region, for example https://api-na.epm.cyberark.cloud'
    }
    "https://$hostName"
}
function Send-EpmRequest {
    param([string]$Uri, [string]$Method, $Headers, [string]$Body, [string]$ContentType)
    $params = @{ Uri = $Uri; Method = $Method; Headers = $Headers; UseBasicParsing = $true }
    if ($Body) { $params.Body = $Body; $params.ContentType = $ContentType }
    $result = @{ Code = 0; Type = ''; Text = ''; Retry = ''; Headers = $null }
    try {
        $r = Invoke-WebRequest @params
        $result.Code = [int]$r.StatusCode
        $result.Type = [string]$r.Headers['Content-Type']
        $content = $r.Content
        if ($content -is [byte[]]) { $content = [System.Text.Encoding]::UTF8.GetString($content) }
        $result.Text = [string]$content
        $result.Headers = $r.Headers
    } catch {
        $resp = $_.Exception.Response
        if ($null -eq $resp) { Stop-Epm "Could not reach the server: $($_.Exception.Message)" }
        $result.Code = [int]$resp.StatusCode
        try { $result.Type = [string]$resp.Headers['Content-Type'] } catch {}
        if (-not $result.Type) { try { $result.Type = [string]$resp.Content.Headers.ContentType } catch {} }
        try { $result.Retry = [string]$resp.Headers['Retry-After'] } catch {}
        if (-not $result.Retry) { try { $result.Retry = [string]$resp.Headers.RetryAfter.Delta.TotalSeconds } catch {} }
        $result.Text = [string]$_.ErrorDetails.Message
        if (-not $result.Text) { try { $result.Text = (New-Object System.IO.StreamReader($resp.GetResponseStream())).ReadToEnd() } catch {} }
    }
    $result
}
function Invoke-EpmRequest {
    param([string]$Uri, [string]$Method, $Headers, [string]$Body)
    for ($try = 1; $try -le 5; $try++) {
        $r = Send-EpmRequest -Uri $Uri -Method $Method -Headers $Headers -Body $Body -ContentType 'application/json'
        if (($r.Code -eq 429 -or ($r.Code -eq 403 -and $r.Retry)) -and $try -lt 5) {
            $wait = 30
            if ($r.Retry -match '^\d+$') { $wait = [Math]::Min([int]$r.Retry + 1, 120) }
            Write-Host "Throttled, waiting $wait seconds (try $try of 5)"
            Start-Sleep -Seconds $wait
        } else {
            break
        }
    }
    if ($r.Text -and $r.Type -notmatch 'json' -and $r.Text.TrimStart() -notmatch '^[\[{]') { Stop-Epm "The URL returned a web page, not the EPM API. Check the EPM base URL. (HTTP $($r.Code))" }
    if ($r.Code -ge 400) {
        $detail = ''
        if ($r.Text) {
            try { $detail = ((@($r.Text | ConvertFrom-Json) | ForEach-Object { ("$($_.ErrorCode) $($_.ErrorMessage)").Trim() } | Where-Object { $_ }) -join '; ') } catch {}
        }
        $message = "HTTP $($r.Code)"
        if ($detail) { $message += ": $detail" }
        if ($r.Code -eq 401 -or $r.Code -eq 403) { $message += '. Check the credentials and that the web app has permission to this EPM set.' }
        if ($r.Code -eq 429) { $message += '. The service is throttling requests, try again in a minute.' }
        Stop-Epm $message
    }
    $script:EpmHeaders = $r.Headers
    if (-not $r.Text) { return [pscustomobject]@{ status = $r.Code } }
    try {
        if ($PSVersionTable.PSVersion.Major -ge 7) { $data = ConvertFrom-Json -InputObject $r.Text -NoEnumerate } else { $data = ConvertFrom-Json -InputObject $r.Text }
    } catch {
        Stop-Epm "The response was not valid JSON. (HTTP $($r.Code))"
    }
    return ,$data
}
function Invoke-IdentityToken {
    param([string]$Uri, $Headers)
    $r = Send-EpmRequest -Uri $Uri -Method Post -Headers $Headers -Body 'grant_type=client_credentials' -ContentType 'application/x-www-form-urlencoded'
    $data = $null
    if ($r.Text -and $r.Type -match 'json') { try { $data = $r.Text | ConvertFrom-Json } catch {} }
    if ($r.Code -ge 400 -or -not $data -or -not $data.access_token) {
        $message = "Identity sign-in failed (HTTP $($r.Code))."
        if ($data) {
            $detail = ("$($data.error) $($data.error_description) $($data.Message)").Trim()
            if ($detail) { $message += " $detail" } else { $message += ' The response did not contain an access_token.' }
        } else {
            $message += ' The response was not an Identity token. Check the tenant ID and web app ID.'
        }
        Stop-Epm $message
    }
    $data
}
$TenantId = Read-Host 'Tenant ID'
$WebAppId = Read-Host 'Web App ID'
$Username = Read-Host 'Username'
$SecurePassword = Read-Host 'Password' -AsSecureString
$Password = [System.Net.NetworkCredential]::new('', $SecurePassword).Password
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${Username}:${Password}"))
$tokenUri = "https://$TenantId.id.cyberark.cloud/oauth2/token/$WebAppId"
$tokenHeaders = @{ Authorization = "Basic $b64" }
$tokenResponse = Invoke-IdentityToken -Uri $tokenUri -Headers $tokenHeaders
$token = $tokenResponse.access_token
$BaseUrl = Get-EpmBaseUrl 'EPM base URL (example https://api-na.epm.cyberark.cloud)'
$headers = @{ Authorization = "Bearer $token" }
$SetName = (Read-Host 'Set name (example MySet)').Trim()
$FileName = (Read-Host 'Application file name (example cmd.exe, leave blank to skip)').Trim()
$FileMatch = 'EQ'
if ($FileName) {
    $answer = (Read-Host 'Application match (EQ, CONTAINS or STARTSWITH, default EQ)').Trim().ToUpperInvariant()
    if ($answer) { $FileMatch = $answer }
    if ($FileMatch -notin @('EQ', 'CONTAINS', 'STARTSWITH')) { Stop-Epm 'Application match must be EQ, CONTAINS or STARTSWITH.' }
}
$UserFilter = (Read-Host 'User name contains (example DOMAIN\jsmith, leave blank to skip)').Trim()
$Computer = (Read-Host 'Computer name contains (at least 3 letters, example WS-001, leave blank to skip)').Trim()
if (-not $FileName -and -not $UserFilter -and -not $Computer) { Stop-Epm 'Enter at least one of application, user or computer.' }
if ($Computer -and $Computer.Length -lt 3) { Stop-Epm 'The computer name needs at least 3 letters.' }
$EventTypeText = (Read-Host 'Event types (comma separated, example ElevationRequest,Block, leave blank for all)').Trim()
$ValidTypes = @('ElevationRequest', 'Trust', 'Installation', 'Launch', 'ManualRequest', 'Block', 'RestrictAccess', 'DetectAccess', 'Ransomware', 'Access', 'Skipped', 'AttackAttempt', 'AttackBlock', 'SuspiciousActivityAttempt', 'SuspiciousActivityBlock')
$EventTypes = @()
foreach ($item in ($EventTypeText -split ',')) {
    $item = $item.Trim()
    if ($item) {
        $known = $ValidTypes | Where-Object { $_ -ieq $item }
        if (-not $known) { Stop-Epm "Unknown event type '$item'. Valid types: $($ValidTypes -join ', ')" }
        $EventTypes += $known
    }
}
$now = [DateTimeOffset]::UtcNow
$DateFromText = (Read-Host 'From date, UTC (example 2026-10-01 or 2026-10-01T00:00:00Z, default 30 days ago)').Trim()
$DateToText = (Read-Host 'To date, UTC (default now)').Trim()
$DateFrom = $now.AddDays(-30)
$DateTo = $now
if ($DateFromText -and -not [DateTimeOffset]::TryParse($DateFromText, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$DateFrom)) { Stop-Epm 'The from date is not a valid date.' }
if ($DateToText -and -not [DateTimeOffset]::TryParse($DateToText, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$DateTo)) { Stop-Epm 'The to date is not a valid date.' }
if ($DateFrom -gt $DateTo) { Stop-Epm 'The from date is after the to date.' }
$DefaultPath = Join-Path (Get-Location).Path ("EPM-Events-{0}.csv" -f $now.ToString('yyyyMMdd-HHmmss'))
$OutPath = (Read-Host "Output CSV path (default $DefaultPath)").Trim()
if (-not $OutPath) { $OutPath = $DefaultPath }
foreach ($value in @($FileName, $UserFilter, $Computer)) {
    if ($value.Contains('"')) { Stop-Epm 'Values cannot contain double quotes.' }
}
$sets = [System.Collections.Generic.List[object]]::new()
$offset = 0
do {
    $response = Invoke-EpmRequest -Uri "$BaseUrl/API/Sets?offset=$offset&limit=100" -Method Get -Headers $headers
    $page = @($response.Sets | Where-Object { $null -ne $_ })
    $sets.AddRange([object[]]$page)
    $offset += 100
} while ($page.Count -eq 100)
$matchSets = @($sets | Where-Object { $_.Name -ieq $SetName })
if ($matchSets.Count -eq 0) { $matchSets = @($sets | Where-Object { $_.Name -like "*$SetName*" }) }
if ($matchSets.Count -ne 1) {
    Write-Host "Set '$SetName' was not found, or more than one set matches. Available sets:"
    $sets | ForEach-Object { "  $($_.Name)" }
    exit 1
}
$SetId = $matchSets[0].Id
$parts = @()
if ($FileName) { $parts += "fileName $FileMatch `"$FileName`"" }
if ($UserFilter) { $parts += "user CONTAINS `"$UserFilter`"" }
if ($Computer) { $parts += "computerName CONTAINS `"$Computer`"" }
if ($EventTypes.Count -gt 0) { $parts += "eventType IN $($EventTypes -join ',')" }
$parts += "arrivalTime GE $($DateFrom.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
$parts += "arrivalTime LE $($DateTo.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
$Filter = $parts -join ' AND '
$body = @{ filter = $Filter } | ConvertTo-Json
$method = "Post"
$events = [System.Collections.Generic.List[object]]::new()
$seen = @{}
$cursor = 'start'
$pageNumber = 0
while ($true) {
    $uri = "$BaseUrl/API/Sets/$SetId/Events/Search?nextCursor=$([Uri]::EscapeDataString($cursor))&limit=1000"
    $response = Invoke-EpmRequest -Uri $uri -Method $method -Headers $headers -Body $body
    $page = @($response.events | Where-Object { $null -ne $_ })
    $pageNumber++
    if ($page.Count -gt 0) { $events.AddRange([object[]]$page) }
    Write-Host "Page ${pageNumber}: $($page.Count) events, $($events.Count) of $($response.filteredCount) so far"
    $cursor = [string]$response.nextCursor
    if ($page.Count -eq 0 -or -not $cursor -or $seen.ContainsKey($cursor)) { break }
    $seen[$cursor] = $true
}
$summary = [ordered]@{ set = $matchSets[0].Name; filter = $Filter; pages = $pageNumber; totalEvents = $events.Count; csvPath = $null }
if ($events.Count -gt 0) {
    $columns = 'arrivalTime', 'firstEventDate', 'lastEventDate', 'eventType', 'computerName', 'userName', 'fileName', 'filePath', 'fileDescription', 'productName', 'publisher', 'hash', 'policyName', 'sourceType', 'sourceName', 'processCommandLine', 'parentProcess', 'justification', 'userIsAdmin', 'eventCount', 'agentId', 'eventId'
    $events | Select-Object $columns | Export-Csv -Path $OutPath -NoTypeInformation -Encoding UTF8
    $summary.csvPath = $OutPath
}
ConvertTo-Json -InputObject $summary -Depth 20
