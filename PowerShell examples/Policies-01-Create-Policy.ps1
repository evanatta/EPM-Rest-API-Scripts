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
    if (-not $r.Text) { return $null }
    $r.Text | ConvertFrom-Json
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
$SetId = Read-Host 'Set ID'
$Name = Read-Host 'Name'
$Description = Read-Host 'Description'
$FileName = Read-Host 'File name (example notepad.exe)'
$uri = "$BaseUrl/API/Sets/$SetId/Policies/Server"
$method = "Post"
$body = @{ Name = $Name; PolicyType = 11; Action = 1; Description = $Description; IsActive = $false; IsAppliedToAllComputers = $true; Audit = $false; Applications = @(@{ applicationType = 3; displayName = $FileName; patterns = @{ FILE_NAME = @{ '@type' = 'FileName'; isEmpty = $false; compareAs = 0; caseSensitive = $false; content = $FileName } } }) } | ConvertTo-Json -Depth 10
$response = Invoke-EpmRequest -Uri $uri -Method $method -Headers $headers -Body $body
$response | ConvertTo-Json -Depth 20
