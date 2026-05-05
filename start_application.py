import requests

# ===== CONFIG =====
BASE_URL = "https://coolify.testcyberlabx.fun/api/v1/applications"
TOKEN = "1|Cyf7qRMOhtzUzZ8E79MLFmUbnm2YztuVB2scLUoD4a00e7b0"

APP_UUID = "kr4rbj1pgz7c5aeurl1ezql3"   # <-- sửa ở đây

# Query params
params = {
    "force": True,           # True = rebuild lại
    "instant_deploy": True   # True = chạy luôn, không queue
}

headers = {
    "Authorization": f"Bearer {TOKEN}",
    "Content-Type": "application/json"
}

# ===== REQUEST =====
url = f"{BASE_URL}/{APP_UUID}/start"

response = requests.post(url, headers=headers, params=params)

# ===== OUTPUT =====
print("Status:", response.status_code)
print("Response:", response.text)