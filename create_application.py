import requests

# ===== CONFIG =====
API_URL = "https://coolify.testcyberlabx.fun/api/v1/applications/public"

TOKEN = "1|Cyf7qRMOhtzUzZ8E79MLFmUbnm2YztuVB2scLUoD4a00e7b0"

payload = {
    "project_uuid": "fgqkeowgygmvru4zzkbpp0v2",
    "server_uuid": "p8bdzfyyjaigztjuwal2b3h4",
    "environment_name": "production",
    "environment_uuid": "i47hd0gx6lu0xcmdmmahnafa",

    "git_repository": "https://github.com/Matr1xz/test_sqli.git",
    "git_branch": "main",

    "build_pack": "nixpacks",
    "ports_exposes": "80",
    "domain": "test-app-from-api.coolify.io",
    "name": "test-app-from-api"
}

headers = {
    "Authorization": f"Bearer {TOKEN}",
    "Content-Type": "application/json"
}

# ===== REQUEST =====
response = requests.post(API_URL, json=payload, headers=headers)

# ===== OUTPUT =====
print("Status:", response.status_code)
print("Response:", response.text)