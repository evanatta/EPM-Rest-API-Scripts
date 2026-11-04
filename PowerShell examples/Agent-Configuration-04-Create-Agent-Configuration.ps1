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
$SourceConfigId = Read-Host 'Source agent configuration ID'
$Name = Read-Host 'New configuration name'
$EndpointId = Read-Host 'Endpoint ID'
$source = Invoke-RestMethod -Uri "$BaseUrl/API/Sets/$SetId/Policies/AgentConfiguration/$SourceConfigId" -Method Get -Headers $headers
$config = $source.Policy
$config.Id = '00000000-0000-0000-0000-000000000000'
$config.Name = $Name
$config.IsAppliedToAllComputers = $false
$config.Executors = @(@{ Id = $EndpointId; IsIncluded = $true; ExecutorType = 1 })
$uri = "$BaseUrl/API/Sets/$SetId/Policies/AgentConfiguration"
$method = "Post"
$body = $config | ConvertTo-Json -Depth 20
$response = Invoke-RestMethod -Uri $uri -Method $method -Headers $headers -Body $body -ContentType 'application/json'
$response | ConvertTo-Json -Depth 20
