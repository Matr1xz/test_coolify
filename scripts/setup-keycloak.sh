#!/bin/bash
# Setup Keycloak realm, client, and users
# Run this after Keycloak is fully started

KEYCLOAK_URL="http://localhost:8080"
ADMIN_USER="admin"
ADMIN_PASS="admin123"

echo "=== Waiting for Keycloak to be ready ==="
until curl -s "$KEYCLOAK_URL/health/ready" > /dev/null 2>&1; do
    echo "Waiting for Keycloak..."
    sleep 5
done
echo "Keycloak is ready!"

echo ""
echo "=== Getting admin access token ==="
TOKEN=$(curl -s -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=$ADMIN_USER" \
    -d "password=$ADMIN_PASS" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
    echo "Failed to get admin token!"
    exit 1
fi
echo "Got admin token"

echo ""
echo "=== Creating cyberlabx realm ==="
curl -s -X POST "$KEYCLOAK_URL/admin/realms" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "realm": "cyberlabx",
        "enabled": true,
        "registrationAllowed": false,
        "loginWithEmailAllowed": true,
        "duplicateEmailsAllowed": false,
        "resetPasswordAllowed": true,
        "editUsernameAllowed": false,
        "bruteForceProtected": true
    }'
echo "Realm created"

echo ""
echo "=== Creating roles ==="
# Create admin role
curl -s -X POST "$KEYCLOAK_URL/admin/realms/cyberlabx/roles" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"name": "admin", "description": "Administrator role - full access"}'

# Create user role  
curl -s -X POST "$KEYCLOAK_URL/admin/realms/cyberlabx/roles" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"name": "user", "description": "Regular user role - limited access"}'
echo "Roles created"

echo ""
echo "=== Creating cyberlabx-web client ==="
curl -s -X POST "$KEYCLOAK_URL/admin/realms/cyberlabx/clients" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "clientId": "cyberlabx-web",
        "name": "CyberLabX Web Application",
        "enabled": true,
        "publicClient": true,
        "standardFlowEnabled": true,
        "implicitFlowEnabled": false,
        "directAccessGrantsEnabled": true,
        "serviceAccountsEnabled": false,
        "redirectUris": ["http://localhost:3000/*", "http://localhost:8080/*"],
        "webOrigins": ["http://localhost:3000", "http://localhost:8080", "*"],
        "protocol": "openid-connect",
        "fullScopeAllowed": true,
        "defaultClientScopes": ["openid", "profile", "email", "roles"]
    }'
echo "Client created"

echo ""
echo "=== Creating test users ==="

# Create admin user
curl -s -X POST "$KEYCLOAK_URL/admin/realms/cyberlabx/users" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "username": "admin_user",
        "email": "admin@cyberlabx.local",
        "enabled": true,
        "emailVerified": true,
        "firstName": "Admin",
        "lastName": "User",
        "credentials": [{
            "type": "password",
            "value": "admin123",
            "temporary": false
        }]
    }'

# Get admin user ID and assign role
ADMIN_USER_ID=$(curl -s "$KEYCLOAK_URL/admin/realms/cyberlabx/users?username=admin_user" \
    -H "Authorization: Bearer $TOKEN" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)

ADMIN_ROLE_ID=$(curl -s "$KEYCLOAK_URL/admin/realms/cyberlabx/roles/admin" \
    -H "Authorization: Bearer $TOKEN" | grep -o '"id":"[^"]*' | cut -d'"' -f4)

if [ -n "$ADMIN_USER_ID" ] && [ -n "$ADMIN_ROLE_ID" ]; then
    curl -s -X POST "$KEYCLOAK_URL/admin/realms/cyberlabx/users/$ADMIN_USER_ID/role-mappings/realm" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "[{\"id\":\"$ADMIN_ROLE_ID\",\"name\":\"admin\"}]"
fi

# Create regular user
curl -s -X POST "$KEYCLOAK_URL/admin/realms/cyberlabx/users" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "username": "test_user",
        "email": "user@cyberlabx.local", 
        "enabled": true,
        "emailVerified": true,
        "firstName": "Test",
        "lastName": "User",
        "credentials": [{
            "type": "password",
            "value": "user123",
            "temporary": false
        }]
    }'

# Get regular user ID and assign role
USER_ID=$(curl -s "$KEYCLOAK_URL/admin/realms/cyberlabx/users?username=test_user" \
    -H "Authorization: Bearer $TOKEN" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)

USER_ROLE_ID=$(curl -s "$KEYCLOAK_URL/admin/realms/cyberlabx/roles/user" \
    -H "Authorization: Bearer $TOKEN" | grep -o '"id":"[^"]*' | cut -d'"' -f4)

if [ -n "$USER_ID" ] && [ -n "$USER_ROLE_ID" ]; then
    curl -s -X POST "$KEYCLOAK_URL/admin/realms/cyberlabx/users/$USER_ID/role-mappings/realm" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "[{\"id\":\"$USER_ROLE_ID\",\"name\":\"user\"}]"
fi

echo "Users created"

echo ""
echo "=========================================="
echo "Keycloak Setup Complete!"
echo "=========================================="
echo ""
echo "Realm: cyberlabx"
echo "Client: cyberlabx-web"
echo ""
echo "Test Users:"
echo "  Admin: admin_user / admin123"
echo "  User:  test_user / user123"
echo ""
echo "Keycloak Admin Console: $KEYCLOAK_URL/admin"
echo "=========================================="
