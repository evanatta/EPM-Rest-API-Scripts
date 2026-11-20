import base64
import getpass
import json
import requests
import re
import sys
import time
from urllib.parse import urlparse

EXAMPLE_URL = "https://api-na.epm.cyberark.cloud"
EPM_HOSTS = (
    re.compile(r"^api-[a-z0-9-]+\.epm\.cyberark\.cloud$"),
    re.compile(r"^[a-z]+[0-9]+\.epm\.cyberark\.com$"),
    re.compile(r"^([a-z0-9-]+\.)+epm\.cyberarkgov\.cloud$"),
)


def fail(message):
    print(message)
    sys.exit(1)


def read_base_url(prompt):
    value = input(prompt).strip()
    if "://" not in value:
        value = "https://" + value
    parsed = urlparse(value)
    host = (parsed.hostname or "").lower()
    if parsed.scheme.lower() != "https":
        fail("The EPM base URL must start with https://")
    if not any(pattern.match(host) for pattern in EPM_HOSTS):
        if host.endswith(".cyberark.cloud"):
            fail(f"That looks like an Identity URL. Enter the EPM API URL for your region, for example {EXAMPLE_URL}")
        fail(f"That is not an EPM API address. Enter the EPM API URL for your region, for example {EXAMPLE_URL}")
    return f"https://{host}"


def is_json(response):
    return "json" in response.headers.get("Content-Type", "").lower()


def error_detail(response):
    try:
        data = response.json()
    except ValueError:
        return ""
    parts = []
    for item in data if isinstance(data, list) else [data]:
        if isinstance(item, dict):
            text = f"{item.get('ErrorCode', '')} {item.get('ErrorMessage', '')}".strip()
            if text:
                parts.append(text)
    return "; ".join(parts)


def get_token(uri, headers):
    try:
        response = requests.post(uri, headers=headers, data={"grant_type": "client_credentials"}, timeout=60)
    except requests.exceptions.RequestException as error:
        fail(f"Could not reach the Identity service ({error.__class__.__name__}). Check the tenant ID.")
    data = None
    if response.text and is_json(response):
        try:
            data = response.json()
        except ValueError:
            data = None
    if not response.ok or not isinstance(data, dict) or not data.get("access_token"):
        message = f"Identity sign-in failed (HTTP {response.status_code})."
        if isinstance(data, dict):
            detail = " ".join(str(data.get(key, "")) for key in ("error", "error_description", "Message")).strip()
            message += " " + detail if detail else " The response did not contain an access_token."
        else:
            message += " The response was not an Identity token. Check the tenant ID and web app ID."
        fail(message)
    return data["access_token"]


def epm_request(method, uri, headers, body=None):
    for attempt in range(1, 6):
        try:
            response = requests.request(method, uri, headers=headers, json=body, timeout=120)
        except requests.exceptions.RequestException as error:
            fail(f"Could not reach the server ({error.__class__.__name__}). Check the EPM base URL and your network connection.")
        retry_after = response.headers.get("Retry-After", "")
        if (response.status_code == 429 or (response.status_code == 403 and retry_after)) and attempt < 5:
            wait = min(int(retry_after) + 1, 120) if retry_after.isdigit() else 30
            print(f"Throttled, waiting {wait} seconds (try {attempt} of 5)")
            time.sleep(wait)
            continue
        break
    if response.content and not is_json(response) and not response.text.lstrip().startswith(("{", "[")):
        fail(f"The URL returned a web page, not the EPM API. Check the EPM base URL. (HTTP {response.status_code})")
    if not response.ok:
        message = f"HTTP {response.status_code}"
        detail = error_detail(response)
        if detail:
            message += f": {detail}"
        if response.status_code in (401, 403):
            message += ". Check the credentials and that the web app has permission to this EPM set."
        if response.status_code == 429:
            message += ". The service is throttling requests, try again in a minute."
        fail(message)
    if response.content:
        try:
            response.json()
        except ValueError:
            fail(f"The response was not valid JSON. (HTTP {response.status_code})")
    return response


def response_data(response):
    if response.content:
        return response.json()
    return {"status": response.status_code}


def print_json(data):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    print(json.dumps(data, indent=2, ensure_ascii=False))


tenant_id = input("Tenant ID: ")
web_app_id = input("Web App ID: ")
username = input("Username: ")
password = getpass.getpass("Password: ")
b64 = base64.b64encode(f"{username}:{password}".encode("utf-8")).decode("ascii")
token_uri = f"https://{tenant_id}.id.cyberark.cloud/oauth2/token/{web_app_id}"
token_headers = {"Authorization": f"Basic {b64}"}
token = get_token(token_uri, token_headers)

base_url = read_base_url("EPM base URL (example https://api-na.epm.cyberark.cloud): ")
headers = {"Authorization": f"Bearer {token}"}
set_id = input("Set ID: ")
endpoint_id = input("Endpoint ID: ")
uri = f"{base_url}/API/Sets/{set_id}/Endpoints/{endpoint_id}/search"
method = "POST"
body = {"filter": "inventoryType IN OsInfo,Hardware,Network,DomainInfo,TimeAndDate"}
response = epm_request(method, uri, headers, body)
print_json(response_data(response))
