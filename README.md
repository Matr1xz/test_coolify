# CyberLabX - Kong + Keycloak + Casbin Lab Management

Hệ thống quản lý Lab với API Gateway (Kong), Authentication (Keycloak), và Authorization (Casbin).

## 📐 Architecture

```
┌─────────────┐      ┌─────────────┐      ┌──────────────┐      ┌─────────────┐
│   Browser   │─────▶│    Kong     │─────▶│ Casbin AuthZ │─────▶│   app.py    │
│   (Web UI)  │      │  Gateway    │      │   Service    │      │  (Coolify)  │
└─────────────┘      └──────┬──────┘      └──────┬───────┘      └─────────────┘
                            │                     │
                            │                     │ Validate JWT
                            ▼                     ▼
                     ┌─────────────┐      ┌──────────────┐
                     │  Keycloak   │◀─────│  Get Public  │
                     │   (Auth)    │      │     Key      │
                     └─────────────┘      └──────────────┘
```

## 🔐 Role-Based Access Control

| Role    | Access                                      |
|---------|---------------------------------------------|
| `admin` | Full access - create, start, stop, delete labs |
| `user`  | View only - can see active labs but cannot create/manage |

## 🚀 Quick Start

### 1. Start all services

```bash
cd coolify
docker-compose up -d --build
```

### 2. Wait for services to be ready (~2-3 minutes)

```bash
# Check all containers are running
docker-compose ps
```

### 3. Configure Keycloak

```powershell
# PowerShell
.\scripts\setup-keycloak.ps1
```

### 4. Configure Kong

```powershell
.\scripts\setup-kong.ps1
```

## 🔗 Service URLs

| Service           | URL                          |
|-------------------|------------------------------|
| Web UI            | http://localhost:3000        |
| Kong Proxy        | http://localhost:18000       |
| Kong Admin API    | http://localhost:18001       |
| Keycloak Console  | http://localhost:8080/admin  |
| Casbin AuthZ API  | http://localhost:8082        |

## 👤 Test Users

| Username     | Password   | Role  |
|--------------|------------|-------|
| `admin_user` | `admin123` | admin |
| `test_user`  | `user123`  | user  |

## 📝 API Endpoints (via Kong)

### Admin Only
```
POST /lab/api/start-lab     - Create new lab
POST /lab/api/stop-lab/{id} - Stop a lab
```

### User + Admin
```
GET /lab/api/labs           - List lab templates
GET /lab/api/active-labs    - List active labs
```

## 🧪 Testing with cURL

### Get token from Keycloak

```powershell
# Admin token
$body = @{
    username = "admin_user"
    password = "admin123"
    grant_type = "password"
    client_id = "cyberlabx-web"
}
$response = Invoke-RestMethod -Uri "http://localhost:8080/realms/cyberlabx/protocol/openid-connect/token" `
    -Method POST -Body $body -ContentType "application/x-www-form-urlencoded"
$TOKEN = $response.access_token
```

### Call API via Kong

```powershell
# With admin token
Invoke-RestMethod -Uri "http://localhost:18000/lab/api/labs" `
    -Headers @{ Authorization = "Bearer $TOKEN" }

# Create lab (admin only)
Invoke-RestMethod -Uri "http://localhost:18000/lab/api/start-lab" `
    -Method POST `
    -Headers @{ Authorization = "Bearer $TOKEN"; "Content-Type" = "application/json" } `
    -Body '{"template": "sqli_basic"}'
```

## 📁 Project Structure

```
coolify/
├── docker-compose.yml      # All services
├── app.py                  # Lab manager Flask app
├── kong/
│   └── Dockerfile          # Custom Kong with lua-resty-http
├── casbin-service/
│   ├── main.py             # FastAPI authorization service
│   ├── model.conf          # Casbin RBAC model
│   └── policy.csv          # Access policies
├── web-ui/
│   └── html/
│       └── index.html      # Login + Dashboard UI
└── scripts/
    ├── setup-keycloak.ps1  # Configure Keycloak
    └── setup-kong.ps1      # Configure Kong routes
```

## 🔧 Modify Policies

Edit `casbin-service/policy.csv` then reload:

```powershell
Invoke-RestMethod -Uri "http://localhost:8082/policies/reload" -Method POST
```

## 🛑 Cleanup

```bash
docker-compose down -v
```

Ứng dụng sẽ chạy tại: http://localhost:5000

## API Endpoints

### Lab Templates
- `GET /api/labs` - Lấy danh sách lab templates

### Active Labs
- `GET /api/active-labs` - Lấy tất cả lab đang chạy
- `GET /api/lab-status/<lab_id>` - Lấy trạng thái của 1 lab

### Lab Management
- `POST /api/start-lab` - Khởi tạo lab mới
  ```json
  {
    "template": "sqli_basic",
    "duration_minutes": 60,
    "git_repository": "...",  // chỉ cần nếu template=custom
    "git_branch": "main"
  }
  ```

- `POST /api/stop-lab/<lab_id>` - Dừng lab
- `POST /api/extend-lab/<lab_id>` - Gia hạn thời gian
  ```json
  {
    "additional_minutes": 30
  }
  ```

## Cấu trúc thư mục

```
coolify/
├── app.py              # Flask backend
├── requirements.txt    # Python dependencies
├── .env.example        # Environment variables template
├── README.md           # Documentation
└── templates/
    └── index.html      # Frontend UI
```

## Thêm Lab Template mới

Chỉnh sửa `LAB_TEMPLATES` trong `app.py`:

```python
LAB_TEMPLATES = {
    "new_lab": {
        "name": "New Lab Name",
        "git_repository": "https://github.com/user/repo.git",
        "git_branch": "main",
        "build_pack": "nixpacks",
        "ports_exposes": "80",
        "description": "Description here"
    }
}
```

## Cơ chế Auto-stop

- Mỗi lab khi được tạo sẽ có một timer chạy ngầm
- Khi hết thời gian, lab sẽ tự động:
  1. Dừng application
  2. Xóa application để giải phóng tài nguyên
- Timer được quản lý bằng Python threading
- Khi gia hạn, expire time sẽ được cập nhật

## Lưu ý

- Labs không persist khi restart server (chỉ lưu trong memory)
- Để production, nên sử dụng database để lưu trạng thái lab
- Đảm bảo Coolify server đã cấu hình wildcard DNS cho domain
