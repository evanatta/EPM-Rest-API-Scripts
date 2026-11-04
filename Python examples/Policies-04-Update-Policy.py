import base64
import getpass
import json
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
policy_id = input("Policy ID: ")
name = input("Name: ")
description = input("Description: ")
file_name = input("File name (example notepad.exe): ")
uri = f"{base_url}/API/Sets/{set_id}/Policies/Server/{policy_id}"
method = "PUT"
body = {"Id": policy_id, "Name": name, "PolicyType": 11, "Action": 1, "Description": description, "IsActive": False, "IsAppliedToAllComputers": True, "Audit": False, "Applications": [{"applicationType": 3, "displayName": file_name, "patterns": {"FILE_NAME": {"@type": "FileName", "isEmpty": False, "compareAs": 0, "caseSensitive": False, "content": file_name}}}]}
response = requests.request(method, uri, headers=headers, json=body)
response.raise_for_status()
if response.content:
    print(json.dumps(response.json(), indent=2))
else:
    print(response.status_code)
