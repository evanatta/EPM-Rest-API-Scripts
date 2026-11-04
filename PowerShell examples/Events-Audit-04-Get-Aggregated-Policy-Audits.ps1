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
$DateFrom = Read-Host 'From date (example 2026-10-01T00:00:00Z)'
$uri = "$BaseUrl/API/Sets/$SetId/policyaudits/aggregations/search?limit=100"
$method = "Post"
$body = @{ filter = "arrivalTime GE $DateFrom" } | ConvertTo-Json
$response = Invoke-RestMethod -Uri $uri -Method $method -Headers $headers -Body $body -ContentType 'application/json'
$response | ConvertTo-Json -Depth 20
