$TenantId = Read-Host 'Tenant ID'
$WebAppId = Read-Host 'Web App ID'
$Username = Read-Host 'Username'
$SecurePassword = Read-Host 'Password' -AsSecureString
$Password = [System.Net.NetworkCredential]::new('', $SecurePassword).Password
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${Username}:${Password}"))
$tokenUri = "https://$TenantId.id.cyberark.cloud/oauth2/token/$WebAppId"
$tokenHeaders = @{ Authorization = "Basic $b64" }
$tokenResponse = Invoke-RestMethod -Uri $tokenUri -Method Post -Headers $tokenHeaders -ContentType 'application/x-www-form-urlencoded' -Body 'grant_type=client_credentials'
$token = $tokenResponse.access_token
$BaseUrl = (Read-Host 'EPM base URL (example https://api-na.epm.cyberark.cloud)').TrimEnd('/')
$headers = @{ Authorization = "Bearer $token" }
$SetId = Read-Host 'Set ID'
$endpoints = [System.Collections.Generic.List[object]]::new()
$offset = 0
do {
    $uri = "$BaseUrl/API/Sets/$SetId/Endpoints/search?offset=$offset&limit=1000"
    $method = "Post"
    $body = @{ filter = '' } | ConvertTo-Json
    $response = Invoke-RestMethod -Uri $uri -Method $method -Headers $headers -Body $body -ContentType 'application/json'
    $page = @($response.endpoints)
    $endpoints.AddRange([object[]]$page)
    $offset += 1000
} while ($page.Count -eq 1000)
foreach ($e in $endpoints) {
    $seen = @($e.lastConnected, $e.lastDisconnected | Where-Object { $_ } | ForEach-Object { [datetime]$_ })
    $lastSeen = if ($seen.Count) { ($seen | Measure-Object -Maximum).Maximum } else { [datetime]::MinValue }
    $e | Add-Member -NotePropertyName lastSeen -NotePropertyValue $lastSeen -Force
}
$remove = [System.Collections.Generic.List[object]]::new()
foreach ($group in ($endpoints | Where-Object { $_.name } | Group-Object { $_.name.ToLower() } | Where-Object { $_.Count -gt 1 })) {
    $ordered = @($group.Group | Sort-Object @{ Expression = { $_.lastSeen }; Descending = $true }, @{ Expression = { [string]$_.installTime }; Descending = $true })
    "KEEP    $($ordered[0].name)  $($ordered[0].id)  last seen $($ordered[0].lastSeen)"
    foreach ($old in $ordered[1..($ordered.Count - 1)]) {
        "REMOVE  $($old.name)  $($old.id)  last seen $($old.lastSeen)"
        $remove.Add($old)
    }
}
"Endpoints checked: $($endpoints.Count)  Duplicates to remove: $($remove.Count)"
if ($remove.Count -gt 0 -and (Read-Host 'Type DELETE to remove the older duplicates') -ceq 'DELETE') {
    $deleted = 0
    $failed = 0
    $batchSize = 10
    for ($i = 0; $i -lt $remove.Count; $i += $batchSize) {
        $batch = @($remove[$i..([Math]::Min($i + $batchSize, $remove.Count) - 1)])
        $uri = "$BaseUrl/API/Sets/$SetId/Endpoints/delete"
        $method = "Post"
        $body = @{ filter = (($batch | ForEach-Object { "id EQ `"$($_.id)`"" }) -join ' OR '); force = $false; returnIds = $true; includeAll = $false } | ConvertTo-Json
        $done = $false
        for ($try = 1; $try -le 5 -and -not $done; $try++) {
            try {
                $response = Invoke-RestMethod -Uri $uri -Method $method -Headers $headers -Body $body -ContentType 'application/json'
                $deleted += @($response.appliedIds).Count
                "Batch $([int]($i / $batchSize) + 1): deleted $(@($response.appliedIds).Count) of $($batch.Count)"
                $done = $true
            } catch {
                $code = [int]$_.Exception.Response.StatusCode
                if (($code -eq 403 -or $code -eq 429) -and $try -lt 5) {
                    "Throttled, waiting 30 seconds (try $try of 5)"
                    Start-Sleep -Seconds 30
                } else {
                    "Batch $([int]($i / $batchSize) + 1) failed: $($_.Exception.Message)"
                    $failed += $batch.Count
                    $done = $true
                }
            }
        }
        if ($i + $batchSize -lt $remove.Count) { Start-Sleep -Seconds 6 }
    }
    "Deleted: $deleted  Failed: $failed"
}
