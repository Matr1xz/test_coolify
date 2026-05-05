#!/bin/bash
# Setup Kong routes with authentication via Casbin

KONG_ADMIN="http://localhost:18001"
APP_URL="https://api.testcyberlabx.fun"

echo "=== Waiting for Kong to be ready ==="
until curl -s "$KONG_ADMIN/status" > /dev/null 2>&1; do
    echo "Waiting for Kong..."
    sleep 3
done
echo "Kong is ready!"

echo "=== Creating Lab Manager Service ==="
curl -s -X POST "$KONG_ADMIN/services" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"lab-manager-service\", \"url\": \"$APP_URL\"}"

echo ""
echo "=== Creating Lab Manager Route ==="
curl -s -X POST "$KONG_ADMIN/services/lab-manager-service/routes" \
    -H "Content-Type: application/json" \
    -d '{"name": "lab-manager-route", "paths": ["/lab"], "strip_path": true, "methods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"]}'

echo ""
echo "=== Enabling CORS Plugin ==="
curl -s -X POST "$KONG_ADMIN/plugins" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "cors",
        "service": {"name": "lab-manager-service"},
        "config": {
            "origins": ["*"],
            "methods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
            "headers": ["Authorization", "Content-Type", "Accept"],
            "credentials": true
        }
    }'

echo ""
echo "=== Done ==="
echo "Test: curl http://localhost:18000/lab/api/labs"