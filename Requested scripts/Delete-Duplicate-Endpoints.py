import base64
import getpass
import json
import time
from datetime import datetime, timezone
import requests

tenant_id = input("Tenant ID: ")
web_app_id = input("Web App ID: ")
username = input("Username: ")
password = getpass.getpass("Password: ")
b64 = base64.b64encode(f"{username}:{password}".encode("utf-8")).decode("ascii")
token_uri = f"https://{tenant_id}.id.cyberark.cloud/oauth2/token/{web_app_id}"
token_headers = {"Authorization": f"Basic {b64}"}
token_response = requests.post(token_uri, headers=token_headers, data={"grant_type": "client_credentials"})
token_response.raise_for_status()
token = token_response.json()["access_token"]

base_url = input("EPM base URL (example https://api-na.epm.cyberark.cloud): ").rstrip("/")
headers = {"Authorization": f"Bearer {token}"}
set_id = input("Set ID: ")
endpoints = []
offset = 0
while True:
    uri = f"{base_url}/API/Sets/{set_id}/Endpoints/search?offset={offset}&limit=1000"
    method = "POST"
    body = {"filter": ""}
    response = requests.request(method, uri, headers=headers, json=body)
    response.raise_for_status()
    page = response.json().get("endpoints") or []
    endpoints += page
    offset += 1000
    if len(page) < 1000:
        break

def last_seen(endpoint):
    times = [datetime.fromisoformat(endpoint[k].replace("Z", "+00:00")) for k in ("lastConnected", "lastDisconnected") if endpoint.get(k)]
    return max(times) if times else datetime.min.replace(tzinfo=timezone.utc)

groups = {}
for endpoint in endpoints:
    if endpoint.get("name"):
        groups.setdefault(endpoint["name"].lower(), []).append(endpoint)
remove = []
for group in groups.values():
    if len(group) < 2:
        continue
    ordered = sorted(group, key=lambda e: (last_seen(e), e.get("installTime") or ""), reverse=True)
    print(f"KEEP    {ordered[0]['name']}  {ordered[0]['id']}  last seen {last_seen(ordered[0])}")
    for old in ordered[1:]:
        print(f"REMOVE  {old['name']}  {old['id']}  last seen {last_seen(old)}")
        remove.append(old)
print(f"Endpoints checked: {len(endpoints)}  Duplicates to remove: {len(remove)}")
if remove and input("Type DELETE to remove the older duplicates: ") == "DELETE":
    deleted = 0
    failed = 0
    batch_size = 10
    for i in range(0, len(remove), batch_size):
        batch = remove[i:i + batch_size]
        uri = f"{base_url}/API/Sets/{set_id}/Endpoints/delete"
        method = "POST"
        body = {"filter": " OR ".join(f'id EQ "{e["id"]}"' for e in batch), "force": False, "returnIds": True, "includeAll": False}
        for attempt in range(1, 6):
            response = requests.request(method, uri, headers=headers, json=body)
            if response.status_code in (403, 429) and attempt < 5:
                print(f"Throttled, waiting 30 seconds (try {attempt} of 5)")
                time.sleep(30)
                continue
            break
        if response.ok:
            applied = response.json().get("appliedIds") or []
            deleted += len(applied)
            print(f"Batch {i // batch_size + 1}: deleted {len(applied)} of {len(batch)}")
        else:
            failed += len(batch)
            print(f"Batch {i // batch_size + 1} failed: {response.status_code} {response.text}")
        if i + batch_size < len(remove):
            time.sleep(6)
    print(f"Deleted: {deleted}  Failed: {failed}")
