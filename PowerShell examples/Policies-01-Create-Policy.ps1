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
$Name = Read-Host 'Name'
$Description = Read-Host 'Description'
$FileName = Read-Host 'File name (example notepad.exe)'
$uri = "$BaseUrl/API/Sets/$SetId/Policies/Server"
$method = "Post"
$body = @{ Name = $Name; PolicyType = 11; Action = 1; Description = $Description; IsActive = $false; IsAppliedToAllComputers = $true; Audit = $false; Applications = @(@{ applicationType = 3; displayName = $FileName; patterns = @{ FILE_NAME = @{ '@type' = 'FileName'; isEmpty = $false; compareAs = 0; caseSensitive = $false; content = $FileName } } }) } | ConvertTo-Json -Depth 10
$response = Invoke-RestMethod -Uri $uri -Method $method -Headers $headers -Body $body -ContentType 'application/json'
$response | ConvertTo-Json -Depth 20
