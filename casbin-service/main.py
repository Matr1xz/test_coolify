"""
Casbin Authorization Service
Validates JWT from Keycloak and enforces RBAC policies
"""

import os
import httpx
import casbin
from fastapi import FastAPI, HTTPException, Header, Request
from fastapi.middleware.cors import CORSMiddleware
from jose import jwt, JWTError
from pydantic import BaseModel
from typing import Optional
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Casbin AuthZ Service", version="1.0.0")

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Config
KEYCLOAK_URL = os.getenv("KEYCLOAK_URL", "http://keycloak:8080")
KEYCLOAK_REALM = os.getenv("KEYCLOAK_REALM", "cyberlabx")

# Initialize Casbin enforcer
enforcer = casbin.Enforcer("model.conf", "policy.csv")


class AuthRequest(BaseModel):
    path: str
    method: str


class AuthResponse(BaseModel):
    allowed: bool
    user: Optional[str] = None
    role: Optional[str] = None
    message: str


# Cache for Keycloak public key
_keycloak_public_key = None


async def get_keycloak_public_key():
    """Fetch Keycloak realm public key for JWT verification"""
    global _keycloak_public_key
    
    if _keycloak_public_key:
        return _keycloak_public_key
    
    try:
        async with httpx.AsyncClient() as client:
            # Get realm info
            response = await client.get(
                f"{KEYCLOAK_URL}/realms/{KEYCLOAK_REALM}",
                timeout=10.0
            )
            if response.status_code == 200:
                realm_info = response.json()
                public_key = realm_info.get("public_key")
                if public_key:
                    _keycloak_public_key = f"-----BEGIN PUBLIC KEY-----\n{public_key}\n-----END PUBLIC KEY-----"
                    return _keycloak_public_key
    except Exception as e:
        logger.error(f"Failed to fetch Keycloak public key: {e}")
    
    return None


def extract_roles_from_token(decoded_token: dict) -> list:
    """Extract roles from Keycloak JWT token"""
    roles = []
    
    # Realm roles
    realm_access = decoded_token.get("realm_access", {})
    roles.extend(realm_access.get("roles", []))
    
    # Client roles (resource_access)
    resource_access = decoded_token.get("resource_access", {})
    for client, access in resource_access.items():
        roles.extend(access.get("roles", []))
    
    return roles


def get_primary_role(roles: list) -> str:
    """Determine primary role (admin takes precedence)"""
    if "admin" in roles:
        return "admin"
    elif "user" in roles:
        return "user"
    return "anonymous"


@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "healthy", "service": "casbin-authz"}


@app.post("/authorize", response_model=AuthResponse)
async def authorize(
    auth_request: AuthRequest,
    authorization: Optional[str] = Header(None)
):
    """
    Main authorization endpoint
    Called by Kong to check if request is allowed
    """
    
    # No token = anonymous
    if not authorization:
        logger.info("No authorization header, treating as anonymous")
        role = "anonymous"
        username = "anonymous"
    else:
        # Extract and validate JWT
        try:
            token = authorization.replace("Bearer ", "")
            
            # Get public key
            public_key = await get_keycloak_public_key()
            
            if public_key:
                # Verify token
                decoded = jwt.decode(
                    token,
                    public_key,
                    algorithms=["RS256"],
                    audience="account",
                    options={"verify_aud": False}  # Keycloak audience can vary
                )
                
                username = decoded.get("preferred_username", "unknown")
                roles = extract_roles_from_token(decoded)
                role = get_primary_role(roles)
                
                logger.info(f"User: {username}, Roles: {roles}, Primary: {role}")
            else:
                # Can't verify, decode without verification (dev mode)
                logger.warning("No public key available, decoding without verification")
                decoded = jwt.decode(token, options={"verify_signature": False})
                username = decoded.get("preferred_username", "unknown")
                roles = extract_roles_from_token(decoded)
                role = get_primary_role(roles)
                
        except JWTError as e:
            logger.error(f"JWT Error: {e}")
            return AuthResponse(
                allowed=False,
                message=f"Invalid token: {str(e)}"
            )
    
    # Check Casbin policy
    path = auth_request.path
    method = auth_request.method.upper()
    
    # Normalize path for Casbin matching
    # e.g., /lab/api/start-lab -> /lab/*
    allowed = enforcer.enforce(role, path, method)
    
    logger.info(f"Casbin check: role={role}, path={path}, method={method}, allowed={allowed}")
    
    if allowed:
        return AuthResponse(
            allowed=True,
            user=username,
            role=role,
            message="Access granted"
        )
    else:
        return AuthResponse(
            allowed=False,
            user=username,
            role=role,
            message=f"Access denied for role '{role}' on {method} {path}"
        )


@app.get("/policies")
async def get_policies():
    """Get current Casbin policies (for debugging)"""
    policies = enforcer.get_policy()
    return {
        "policies": [
            {"role": p[0], "path": p[1], "method": p[2]}
            for p in policies
        ]
    }


@app.post("/policies/reload")
async def reload_policies():
    """Reload policies from file"""
    enforcer.load_policy()
    return {"message": "Policies reloaded"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8082)
