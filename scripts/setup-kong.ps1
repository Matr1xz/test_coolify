# Setup Kong routes with authentication via Casbin
# Run this after Kong is fully started

$KONG_ADMIN = "http://localhost:18001"
$APP_URL = "https://api.testcyberlabx.fun"  # Your app.py URL

Write-Host "=== Waiting for Kong to be ready ===" -ForegroundColor Yellow
do {
    try {
        $response = Invoke-WebRequest -Uri "$KONG_ADMIN/status" -UseBasicParsing -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200) { break }
    } catch {}
    Write-Host "Waiting for Kong..."
    Start-Sleep -Seconds 3
} while ($true)
Write-Host "Kong is ready!" -ForegroundColor Green

Write-Host "`n=== Creating Lab Manager Service ===" -ForegroundColor Yellow
$serviceData = @{
    name = "lab-manager-service"
    url = $APP_URL
} | ConvertTo-Json

try {
    Invoke-RestMethod -Uri "$KONG_ADMIN/services" -Method POST -Body $serviceData -ContentType "application/json"
    Write-Host "Service created" -ForegroundColor Green
} catch {
    Write-Host "Service may already exist, continuing..." -ForegroundColor Yellow
}

Write-Host "`n=== Creating Lab Manager Route ===" -ForegroundColor Yellow
$routeData = @{
    name = "lab-manager-route"
    paths = @("/lab")
    strip_path = $true
    methods = @("GET", "POST", "PUT", "DELETE", "OPTIONS")
} | ConvertTo-Json

try {
    Invoke-RestMethod -Uri "$KONG_ADMIN/services/lab-manager-service/routes" -Method POST -Body $routeData -ContentType "application/json"
    Write-Host "Route created" -ForegroundColor Green
} catch {
    Write-Host "Route may already exist, continuing..." -ForegroundColor Yellow
}

Write-Host "`n=== Enabling CORS Plugin ===" -ForegroundColor Yellow
$corsData = @{
    name = "cors"
    service = @{ name = "lab-manager-service" }
    config = @{
        origins = @("*")
        methods = @("GET", "POST", "PUT", "DELETE", "OPTIONS")
        headers = @("Authorization", "Content-Type", "Accept")
        exposed_headers = @("X-User", "X-Role")
        credentials = $true
        max_age = 3600
    }
} | ConvertTo-Json -Depth 3

try {
    Invoke-RestMethod -Uri "$KONG_ADMIN/plugins" -Method POST -Body $corsData -ContentType "application/json"
    Write-Host "CORS plugin enabled" -ForegroundColor Green
} catch {
    Write-Host "CORS plugin setup failed or already exists" -ForegroundColor Yellow
}

Write-Host "`n=== Enabling Pre-Function Plugin for Casbin Auth ===" -ForegroundColor Yellow

$preFunctionLua = @'
local http = require "resty.http"
local cjson = require "cjson.safe"

-- Skip OPTIONS requests (CORS preflight)
if kong.request.get_method() == "OPTIONS" then
    return
end

-- Get authorization header
local auth_header = kong.request.get_header("Authorization")

-- Prepare request to Casbin service
local httpc = http.new()
httpc:set_timeout(5000)

local res, err = httpc:request_uri("http://casbin-authz:8082/authorize", {
    method = "POST",
    body = cjson.encode({
        path = kong.request.get_path(),
        method = kong.request.get_method()
    }),
    headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = auth_header or ""
    }
})

if not res then
    kong.log.err("Failed to call Casbin: ", err)
    return kong.response.exit(503, { message = "Authorization service unavailable" })
end

local body = cjson.decode(res.body)

if not body or not body.allowed then
    local msg = body and body.message or "Access denied"
    return kong.response.exit(403, { 
        message = msg,
        role = body and body.role or "unknown"
    })
end

-- Add user info to headers for downstream service
if body.user then
    kong.service.request.set_header("X-User", body.user)
end
if body.role then
    kong.service.request.set_header("X-Role", body.role)
end
'@

$preFunctionData = @{
    name = "pre-function"
    service = @{ name = "lab-manager-service" }
    config = @{
        access = @($preFunctionLua)
    }
} | ConvertTo-Json -Depth 4

try {
    Invoke-RestMethod -Uri "$KONG_ADMIN/plugins" -Method POST -Body $preFunctionData -ContentType "application/json"
    Write-Host "Pre-function plugin enabled" -ForegroundColor Green
} catch {
    Write-Host "Pre-function plugin setup failed: $_" -ForegroundColor Red
    Write-Host "You may need to manually configure authorization" -ForegroundColor Yellow
}

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "Kong Setup Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Service: lab-manager-service -> $APP_URL"
Write-Host "Route: /lab/* -> lab-manager-service"
Write-Host ""
Write-Host "Authorization Flow:" -ForegroundColor Yellow
Write-Host "  1. Request hits Kong at /lab/*"
Write-Host "  2. Pre-function calls Casbin AuthZ service"
Write-Host "  3. Casbin validates JWT & checks role policy"
Write-Host "  4. If allowed, request forwards to app.py"
Write-Host "  5. If denied, returns 403 Forbidden"
Write-Host ""
Write-Host "Test endpoints:" -ForegroundColor Yellow
Write-Host "  GET  http://localhost:18000/lab/api/labs"
Write-Host "  POST http://localhost:18000/lab/api/start-lab"
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
