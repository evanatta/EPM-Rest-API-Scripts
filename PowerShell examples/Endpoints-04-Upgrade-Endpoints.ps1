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
$EndpointId = Read-Host 'Endpoint ID'
$Platform = Read-Host 'Platform (Windows, MacOS, Linux)'
$Architecture = Read-Host 'Architecture (x64, arm64)'
$Version = Read-Host 'Agent version'
$uri = "$BaseUrl/API/Sets/$SetId/endpoints/upgrade"
$method = "Post"
$body = @{ filter = "id EQ `"$EndpointId`""; versions = @(@{ platform = $Platform; architecture = $Architecture; version = $Version }); returnIds = $true; includeAll = $false } | ConvertTo-Json -Depth 5
$response = Invoke-RestMethod -Uri $uri -Method $method -Headers $headers -Body $body -ContentType 'application/json'
$response | ConvertTo-Json -Depth 20
