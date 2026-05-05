# Setup Keycloak realm, client, and users (PowerShell version)
# Run this after Keycloak is fully started

$KEYCLOAK_URL = "http://localhost:8080"
$ADMIN_USER = "admin"
$ADMIN_PASS = "admin123"

Write-Host "=== Waiting for Keycloak to be ready ===" -ForegroundColor Yellow
do {
    try {
        $response = Invoke-WebRequest -Uri "$KEYCLOAK_URL/health/ready" -UseBasicParsing -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200) { break }
    } catch {}
    Write-Host "Waiting for Keycloak..."
    Start-Sleep -Seconds 5
} while ($true)
Write-Host "Keycloak is ready!" -ForegroundColor Green

Write-Host "`n=== Getting admin access token ===" -ForegroundColor Yellow
$tokenBody = @{
    username = $ADMIN_USER
    password = $ADMIN_PASS
    grant_type = "password"
    client_id = "admin-cli"
}
$tokenResponse = Invoke-RestMethod -Uri "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" `
    -Method POST -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
$TOKEN = $tokenResponse.access_token

if (-not $TOKEN) {
    Write-Host "Failed to get admin token!" -ForegroundColor Red
    exit 1
}
Write-Host "Got admin token" -ForegroundColor Green

$headers = @{
    "Authorization" = "Bearer $TOKEN"
    "Content-Type" = "application/json"
}

Write-Host "`n=== Creating cyberlabx realm ===" -ForegroundColor Yellow
$realmData = @{
    realm = "cyberlabx"
    enabled = $true
    registrationAllowed = $false
    loginWithEmailAllowed = $true
    duplicateEmailsAllowed = $false
    resetPasswordAllowed = $true
    editUsernameAllowed = $false
    bruteForceProtected = $true
} | ConvertTo-Json

try {
    Invoke-RestMethod -Uri "$KEYCLOAK_URL/admin/realms" -Method POST -Headers $headers -Body $realmData
    Write-Host "Realm created" -ForegroundColor Green
} catch {
    Write-Host "Realm may already exist, continuing..." -ForegroundColor Yellow
}

Write-Host "`n=== Creating roles ===" -ForegroundColor Yellow
# Create admin role
$adminRole = @{ name = "admin"; description = "Administrator role - full access" } | ConvertTo-Json
try {
    Invoke-RestMethod -Uri "$KEYCLOAK_URL/admin/realms/cyberlabx/roles" -Method POST -Headers $headers -Body $adminRole
} catch {}

# Create user role
$userRole = @{ name = "user"; description = "Regular user role - limited access" } | ConvertTo-Json
try {
    Invoke-RestMethod -Uri "$KEYCLOAK_URL/admin/realms/cyberlabx/roles" -Method POST -Headers $headers -Body $userRole
} catch {}
Write-Host "Roles created" -ForegroundColor Green

Write-Host "`n=== Creating cyberlabx-web client ===" -ForegroundColor Yellow
$clientData = @{
    clientId = "cyberlabx-web"
    name = "CyberLabX Web Application"
    enabled = $true
    publicClient = $true
    standardFlowEnabled = $true
    implicitFlowEnabled = $false
    directAccessGrantsEnabled = $true
    serviceAccountsEnabled = $false
    redirectUris = @("http://localhost:3000/*", "http://localhost:8080/*")
    webOrigins = @("http://localhost:3000", "http://localhost:8080", "*")
    protocol = "openid-connect"
    fullScopeAllowed = $true
    defaultClientScopes = @("openid", "profile", "email", "roles")
} | ConvertTo-Json

try {
    Invoke-RestMethod -Uri "$KEYCLOAK_URL/admin/realms/cyberlabx/clients" -Method POST -Headers $headers -Body $clientData
    Write-Host "Client created" -ForegroundColor Green
} catch {
    Write-Host "Client may already exist, continuing..." -ForegroundColor Yellow
}

Write-Host "`n=== Creating test users ===" -ForegroundColor Yellow

# Create admin user
$adminUserData = @{
    username = "admin_user"
    email = "admin@cyberlabx.local"
    enabled = $true
    emailVerified = $true
    firstName = "Admin"
    lastName = "User"
    credentials = @(@{
        type = "password"
        value = "admin123"
        temporary = $false
    })
} | ConvertTo-Json -Depth 3

try {
    Invoke-RestMethod -Uri "$KEYCLOAK_URL/admin/realms/cyberlabx/users" -Method POST -Headers $headers -Body $adminUserData
} catch {}

# Get admin user ID and assign role
$adminUsers = Invoke-RestMethod -Uri "$KEYCLOAK_URL/admin/realms/cyberlabx/users?username=admin_user" -Headers $headers
if ($adminUsers.Count -gt 0) {
    $adminUserId = $adminUsers[0].id
    $adminRoleInfo = Invoke-RestMethod -Uri "$KEYCLOAK_URL/admin/realms/cyberlabx/roles/admin" -Headers $headers
    $roleMapping = @(@{ id = $adminRoleInfo.id; name = "admin" }) | ConvertTo-Json
    try {
        Invoke-RestMethod -Uri "$KEYCLOAK_URL/admin/realms/cyberlabx/users/$adminUserId/role-mappings/realm" `
            -Method POST -Headers $headers -Body $roleMapping
    } catch {}
}

# Create regular user
$regularUserData = @{
    username = "test_user"
    email = "user@cyberlabx.local"
    enabled = $true
    emailVerified = $true
    firstName = "Test"
    lastName = "User"
    credentials = @(@{
        type = "password"
        value = "user123"
        temporary = $false
    })
} | ConvertTo-Json -Depth 3

try {
    Invoke-RestMethod -Uri "$KEYCLOAK_URL/admin/realms/cyberlabx/users" -Method POST -Headers $headers -Body $regularUserData
} catch {}

# Get regular user ID and assign role
$regularUsers = Invoke-RestMethod -Uri "$KEYCLOAK_URL/admin/realms/cyberlabx/users?username=test_user" -Headers $headers
if ($regularUsers.Count -gt 0) {
    $userId = $regularUsers[0].id
    $userRoleInfo = Invoke-RestMethod -Uri "$KEYCLOAK_URL/admin/realms/cyberlabx/roles/user" -Headers $headers
    $roleMapping = @(@{ id = $userRoleInfo.id; name = "user" }) | ConvertTo-Json
    try {
        Invoke-RestMethod -Uri "$KEYCLOAK_URL/admin/realms/cyberlabx/users/$userId/role-mappings/realm" `
            -Method POST -Headers $headers -Body $roleMapping
    } catch {}
}

Write-Host "Users created" -ForegroundColor Green

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "Keycloak Setup Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Realm: cyberlabx"
Write-Host "Client: cyberlabx-web"
Write-Host ""
Write-Host "Test Users:" -ForegroundColor Yellow
Write-Host "  Admin: admin_user / admin123" -ForegroundColor Green
Write-Host "  User:  test_user / user123" -ForegroundColor Green
Write-Host ""
Write-Host "Keycloak Admin Console: $KEYCLOAK_URL/admin" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
