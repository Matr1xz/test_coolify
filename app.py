"""
Coolify Lab Manager - Web Application
Quản lý khởi tạo lab từ GitHub repo thông qua Coolify API
"""

import os
import uuid
import threading
import time
from datetime import datetime, timedelta
from flask import Flask, render_template, jsonify, request
import requests

app = Flask(__name__)

# ===== CONFIG =====
COOLIFY_BASE_URL = os.getenv("COOLIFY_BASE_URL", "https://coolify.testcyberlabx.fun/api/v1")
COOLIFY_TOKEN = os.getenv("COOLIFY_TOKEN", "1|Cyf7qRMOhtzUzZ8E79MLFmUbnm2YztuVB2scLUoD4a00e7b0")
PROJECT_UUID = os.getenv("PROJECT_UUID", "fgqkeowgygmvru4zzkbpp0v2")
SERVER_UUID = os.getenv("SERVER_UUID", "p8bdzfyyjaigztjuwal2b3h4")
ENVIRONMENT_UUID = os.getenv("ENVIRONMENT_UUID", "i47hd0gx6lu0xcmdmmahnafa")
ENVIRONMENT_NAME = os.getenv("ENVIRONMENT_NAME", "production")
BASE_DOMAIN = os.getenv("BASE_DOMAIN", "testcyberlabx.fun")

# Default lab duration in minutes
DEFAULT_LAB_DURATION = int(os.getenv("DEFAULT_LAB_DURATION", "60"))

# Store active labs: {lab_id: {app_uuid, deployment_uuid, subdomain, expires_at, timer}}
active_labs = {}

# Available lab templates
LAB_TEMPLATES = {
    "sqli_basic": {
        "name": "SQL Injection Lab - Basic",
        "git_repository": "https://github.com/Matr1xz/test_sqli.git",
        "git_branch": "main",
        "build_pack": "dockerfile",
        "ports_exposes": "5000",
        "description": "Learn basic SQL injection techniques"
    },
    "xss_basic": {
        "name": "XSS Lab - Basic",
        "git_repository": "https://github.com/Matr1xz/test_sqli.git",  # Thay bằng repo XSS thực tế
        "git_branch": "main",
        "build_pack": "nixpacks",
        "ports_exposes": "5000",
        "description": "Learn Cross-Site Scripting vulnerabilities"
    },
    "custom": {
        "name": "Custom Lab",
        "git_repository": "",
        "git_branch": "main",
        "build_pack": "nixpacks",
        "ports_exposes": "5000",
        "description": "Deploy from custom GitHub repository"
    }
}


def get_headers():
    """Return authorization headers for Coolify API"""
    return {
        "Authorization": f"Bearer {COOLIFY_TOKEN}",
        "Content-Type": "application/json"
    }


def generate_subdomain():
    """Generate unique subdomain for lab"""
    unique_id = str(uuid.uuid4())[:8]
    return f"lab-{unique_id}"


def create_application(git_repo: str, git_branch: str, subdomain: str, 
                       build_pack: str = "nixpacks", ports: str = "80"):
    """
    Create a new application in Coolify from GitHub repo
    Returns: (success, app_uuid or error_message)
    """
    url = f"{COOLIFY_BASE_URL}/applications/public"
    
    payload = {
        "project_uuid": PROJECT_UUID,
        "server_uuid": SERVER_UUID,
        "environment_name": ENVIRONMENT_NAME,
        "environment_uuid": ENVIRONMENT_UUID,
        "git_repository": git_repo,
        "git_branch": git_branch,
        "build_pack": build_pack,
        "ports_exposes": ports,
        "domains": f"https://{subdomain}.{BASE_DOMAIN}",
        "name": subdomain
    }
    
    try:
        response = requests.post(url, json=payload, headers=get_headers(), timeout=30)
        
        if response.status_code in [200, 201]:
            data = response.json()
            return True, data.get("uuid")
        else:
            return False, f"API Error: {response.status_code} - {response.text}"
    except requests.RequestException as e:
        return False, f"Request failed: {str(e)}"


def start_application(app_uuid: str, force: bool = True, instant_deploy: bool = True):
    """
    Start/deploy an application
    Returns: (success, deployment_uuid or error_message)
    """
    url = f"{COOLIFY_BASE_URL}/applications/{app_uuid}/start"
    
    params = {
        "force": force,
        "instant_deploy": instant_deploy
    }
    
    try:
        response = requests.post(url, headers=get_headers(), params=params, timeout=30)
        
        if response.status_code in [200, 201]:
            data = response.json()
            return True, data.get("deployment_uuid", app_uuid)
        else:
            return False, f"API Error: {response.status_code} - {response.text}"
    except requests.RequestException as e:
        return False, f"Request failed: {str(e)}"


def stop_application(app_uuid: str):
    """
    Stop an application
    Returns: (success, message)
    """
    url = f"{COOLIFY_BASE_URL}/applications/{app_uuid}/stop"
    
    try:
        response = requests.post(url, headers=get_headers(), timeout=30)
        
        if response.status_code in [200, 201]:
            return True, "Application stopped successfully"
        else:
            return False, f"API Error: {response.status_code} - {response.text}"
    except requests.RequestException as e:
        return False, f"Request failed: {str(e)}"


def cancel_deployment(deployment_uuid: str):
    """
    Cancel a deployment by UUID
    Returns: (success, message)
    """
    url = f"{COOLIFY_BASE_URL}/deployments/{deployment_uuid}"
    
    try:
        response = requests.delete(url, headers=get_headers(), timeout=30)
        
        if response.status_code in [200, 201]:
            data = response.json()
            return True, data.get("message", "Deployment cancelled")
        else:
            return False, f"API Error: {response.status_code} - {response.text}"
    except requests.RequestException as e:
        return False, f"Request failed: {str(e)}"


def delete_application(app_uuid: str):
    """
    Delete an application completely
    Returns: (success, message)
    """
    url = f"{COOLIFY_BASE_URL}/applications/{app_uuid}"
    
    params = {
        "delete_configurations": True,
        "delete_volumes": True
    }
    
    try:
        response = requests.delete(url, headers=get_headers(), params=params, timeout=30)
        
        if response.status_code in [200, 201]:
            return True, "Application deleted successfully"
        else:
            return False, f"API Error: {response.status_code} - {response.text}"
    except requests.RequestException as e:
        return False, f"Request failed: {str(e)}"


def auto_stop_lab(lab_id: str):
    """Background task to auto-stop lab when time expires"""
    if lab_id in active_labs:
        lab = active_labs[lab_id]
        wait_seconds = (lab["expires_at"] - datetime.now()).total_seconds()
        
        if wait_seconds > 0:
            time.sleep(wait_seconds)
        
        # Check if lab still exists (not manually stopped)
        if lab_id in active_labs:
            app_uuid = lab["app_uuid"]
            
            # Stop the application
            stop_application(app_uuid)
            
            # Delete the application to free resources
            delete_application(app_uuid)
            
            # Remove from active labs
            del active_labs[lab_id]
            print(f"[AUTO-STOP] Lab {lab_id} has been automatically stopped and cleaned up")


# ===== ROUTES =====

# @app.route("/")
# def index():
#     """Main page"""
#     return render_template("index.html", labs=LAB_TEMPLATES)


@app.route("/api/labs", methods=["GET"])
def get_lab_templates():
    """Get available lab templates"""
    return jsonify(LAB_TEMPLATES)


@app.route("/api/active-labs", methods=["GET"])
def get_active_labs():
    """Get all active labs"""
    labs_info = {}
    for lab_id, lab in active_labs.items():
        remaining = (lab["expires_at"] - datetime.now()).total_seconds()
        labs_info[lab_id] = {
            "subdomain": lab["subdomain"],
            "url": f"https://{lab['subdomain']}.{BASE_DOMAIN}",
            "app_uuid": lab["app_uuid"],
            "deployment_uuid": lab.get("deployment_uuid"),
            "expires_at": lab["expires_at"].isoformat(),
            "remaining_seconds": max(0, int(remaining)),
            "created_at": lab.get("created_at", "").isoformat() if lab.get("created_at") else None
        }
    return jsonify(labs_info)


@app.route("/api/start-lab", methods=["POST"])
def start_lab():
    """
    Start a new lab
    Body: {
        "template": "sqli_basic" | "xss_basic" | "custom",
        "git_repository": "..." (required if template is custom),
        "git_branch": "main" (optional),
        "duration_minutes": 60 (optional)
    }
    """
    data = request.get_json()
    
    template_id = data.get("template", "sqli_basic")
    duration = data.get("duration_minutes", DEFAULT_LAB_DURATION)
    
    # Get template
    if template_id not in LAB_TEMPLATES:
        return jsonify({"success": False, "error": "Invalid template"}), 400
    
    template = LAB_TEMPLATES[template_id].copy()
    
    # Handle custom template
    if template_id == "custom":
        git_repo = data.get("git_repository")
        if not git_repo:
            return jsonify({"success": False, "error": "git_repository is required for custom template"}), 400
        template["git_repository"] = git_repo
    
    git_branch = data.get("git_branch", template.get("git_branch", "main"))
    
    # Generate unique subdomain
    subdomain = generate_subdomain()
    
    # Step 1: Create application
    success, result = create_application(
        git_repo=template["git_repository"],
        git_branch=git_branch,
        subdomain=subdomain,
        build_pack=template.get("build_pack", "nixpacks"),
        ports=template.get("ports_exposes", "80")
    )
    
    if not success:
        return jsonify({"success": False, "error": result}), 500
    
    app_uuid = result
    
    # Step 2: Start the application
    success, deploy_result = start_application(app_uuid)
    
    if not success:
        # Cleanup: delete the created application
        delete_application(app_uuid)
        return jsonify({"success": False, "error": deploy_result}), 500
    
    # Generate lab ID
    lab_id = str(uuid.uuid4())
    expires_at = datetime.now() + timedelta(minutes=duration)
    
    # Store lab info
    active_labs[lab_id] = {
        "app_uuid": app_uuid,
        "deployment_uuid": deploy_result,
        "subdomain": subdomain,
        "expires_at": expires_at,
        "created_at": datetime.now(),
        "template": template_id
    }
    
    # Start auto-stop timer
    timer_thread = threading.Thread(target=auto_stop_lab, args=(lab_id,), daemon=True)
    timer_thread.start()
    active_labs[lab_id]["timer"] = timer_thread
    
    return jsonify({
        "success": True,
        "lab_id": lab_id,
        "app_uuid": app_uuid,
        "deployment_uuid": deploy_result,
        "subdomain": subdomain,
        "url": f"https://{subdomain}.{BASE_DOMAIN}",
        "expires_at": expires_at.isoformat(),
        "duration_minutes": duration,
        "message": f"Lab is being deployed. It may take 1-3 minutes to be ready."
    })


@app.route("/api/stop-lab/<lab_id>", methods=["POST"])
def stop_lab(lab_id: str):
    """
    Manually stop a lab
    """
    if lab_id not in active_labs:
        return jsonify({"success": False, "error": "Lab not found"}), 404
    
    lab = active_labs[lab_id]
    app_uuid = lab["app_uuid"]
    
    # Stop the application
    success, message = stop_application(app_uuid)
    
    if not success:
        return jsonify({"success": False, "error": message}), 500
    
    # Delete the application
    delete_success, delete_msg = delete_application(app_uuid)
    
    # Remove from active labs
    del active_labs[lab_id]
    
    return jsonify({
        "success": True,
        "message": "Lab stopped and cleaned up successfully",
        "lab_id": lab_id
    })


@app.route("/api/extend-lab/<lab_id>", methods=["POST"])
def extend_lab(lab_id: str):
    """
    Extend lab duration
    Body: {"additional_minutes": 30}
    """
    if lab_id not in active_labs:
        return jsonify({"success": False, "error": "Lab not found"}), 404
    
    data = request.get_json()
    additional_minutes = data.get("additional_minutes", 30)
    
    lab = active_labs[lab_id]
    lab["expires_at"] = lab["expires_at"] + timedelta(minutes=additional_minutes)
    
    # Note: The timer thread will continue running and check actual expire time
    
    return jsonify({
        "success": True,
        "lab_id": lab_id,
        "new_expires_at": lab["expires_at"].isoformat(),
        "message": f"Lab extended by {additional_minutes} minutes"
    })


@app.route("/api/lab-status/<lab_id>", methods=["GET"])
def get_lab_status(lab_id: str):
    """Get status of a specific lab"""
    if lab_id not in active_labs:
        return jsonify({"success": False, "error": "Lab not found"}), 404
    
    lab = active_labs[lab_id]
    remaining = (lab["expires_at"] - datetime.now()).total_seconds()
    
    return jsonify({
        "success": True,
        "lab_id": lab_id,
        "subdomain": lab["subdomain"],
        "url": f"https://{lab['subdomain']}.{BASE_DOMAIN}",
        "app_uuid": lab["app_uuid"],
        "deployment_uuid": lab.get("deployment_uuid"),
        "expires_at": lab["expires_at"].isoformat(),
        "remaining_seconds": max(0, int(remaining)),
        "created_at": lab.get("created_at").isoformat() if lab.get("created_at") else None,
        "template": lab.get("template")
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
