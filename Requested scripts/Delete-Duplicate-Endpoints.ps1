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
$endpoints = @()
$offset = 0
do {
    $uri = "$BaseUrl/API/Sets/$SetId/Endpoints/search?offset=$offset&limit=1000"
    $method = "Post"
    $body = @{ filter = '' } | ConvertTo-Json
    $response = Invoke-RestMethod -Uri $uri -Method $method -Headers $headers -Body $body -ContentType 'application/json'
    $page = @($response.endpoints)
    $endpoints += $page
    $offset += 1000
} while ($page.Count -eq 1000)
foreach ($e in $endpoints) {
    $seen = @($e.lastConnected, $e.lastDisconnected | Where-Object { $_ } | ForEach-Object { [datetime]$_ })
    $lastSeen = if ($seen.Count) { ($seen | Measure-Object -Maximum).Maximum } else { [datetime]::MinValue }
    $e | Add-Member -NotePropertyName lastSeen -NotePropertyValue $lastSeen -Force
}
$remove = @()
foreach ($group in ($endpoints | Group-Object { $_.name.ToLower() } | Where-Object { $_.Count -gt 1 })) {
    $ordered = @($group.Group | Sort-Object lastSeen -Descending)
    "KEEP    $($ordered[0].name)  $($ordered[0].id)  last seen $($ordered[0].lastSeen)"
    foreach ($old in $ordered[1..($ordered.Count - 1)]) {
        "REMOVE  $($old.name)  $($old.id)  last seen $($old.lastSeen)"
        $remove += $old
    }
}
"Endpoints checked: $($endpoints.Count)  Duplicates to remove: $($remove.Count)"
if ($remove.Count -gt 0 -and (Read-Host 'Type DELETE to remove the older duplicates') -ceq 'DELETE') {
    foreach ($old in $remove) {
        $uri = "$BaseUrl/API/Sets/$SetId/Endpoints/delete"
        $method = "Post"
        $body = @{ filter = "id EQ `"$($old.id)`""; force = $false; returnIds = $true; includeAll = $false } | ConvertTo-Json
        $response = Invoke-RestMethod -Uri $uri -Method $method -Headers $headers -Body $body -ContentType 'application/json'
        "$($old.name) $($old.id)"
        $response | ConvertTo-Json -Depth 20
    }
}
