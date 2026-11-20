import base64
import csv
import getpass
import os
import urllib.parse
from datetime import datetime, timedelta, timezone
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
    return response


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
set_name = input("Set name (example MySet): ").strip()
file_name = input("Application file name (example cmd.exe, leave blank to skip): ").strip()
file_match = "EQ"
if file_name:
    answer = input("Application match (EQ, CONTAINS or STARTSWITH, default EQ): ").strip().upper()
    if answer:
        file_match = answer
    if file_match not in ("EQ", "CONTAINS", "STARTSWITH"):
        fail("Application match must be EQ, CONTAINS or STARTSWITH.")
user_filter = input("User name contains (example DOMAIN\\jsmith, leave blank to skip): ").strip()
computer = input("Computer name contains (at least 3 letters, example WS-001, leave blank to skip): ").strip()
if not (file_name or user_filter or computer):
    fail("Enter at least one of application, user or computer.")
if computer and len(computer) < 3:
    fail("The computer name needs at least 3 letters.")
event_type_text = input("Event types (comma separated, example ElevationRequest,Block, leave blank for all): ").strip()
valid_types = ["ElevationRequest", "Trust", "Installation", "Launch", "ManualRequest", "Block", "RestrictAccess", "DetectAccess", "Ransomware", "Access", "Skipped", "AttackAttempt", "AttackBlock", "SuspiciousActivityAttempt", "SuspiciousActivityBlock"]
event_types = []
for item in event_type_text.split(","):
    item = item.strip()
    if item:
        known = [t for t in valid_types if t.lower() == item.lower()]
        if not known:
            fail(f"Unknown event type '{item}'. Valid types: {', '.join(valid_types)}")
        event_types.append(known[0])


def parse_date(text):
    for pattern in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(text, pattern).replace(tzinfo=timezone.utc)
        except ValueError:
            continue
    return None


now = datetime.now(timezone.utc)
date_from_text = input("From date, UTC (example 2026-10-01 or 2026-10-01T00:00:00Z, default 30 days ago): ").strip()
date_to_text = input("To date, UTC (default now): ").strip()
date_from = now - timedelta(days=30)
date_to = now
if date_from_text:
    date_from = parse_date(date_from_text)
    if date_from is None:
        fail("The from date is not a valid date.")
if date_to_text:
    date_to = parse_date(date_to_text)
    if date_to is None:
        fail("The to date is not a valid date.")
if date_from > date_to:
    fail("The from date is after the to date.")
default_path = os.path.join(os.getcwd(), f"EPM-Events-{now.strftime('%Y%m%d-%H%M%S')}.csv")
out_path = input(f"Output CSV path (default {default_path}): ").strip() or default_path
for value in (file_name, user_filter, computer):
    if '"' in value:
        fail("Values cannot contain double quotes.")

sets = []
offset = 0
while True:
    response = epm_request("GET", f"{base_url}/API/Sets?offset={offset}&limit=100", headers)
    page = response.json().get("Sets") or []
    sets += page
    offset += 100
    if len(page) < 100:
        break
matches = [s for s in sets if s.get("Name", "").lower() == set_name.lower()]
if not matches:
    matches = [s for s in sets if set_name.lower() in s.get("Name", "").lower()]
if len(matches) != 1:
    print(f"Set '{set_name}' was not found, or more than one set matches. Available sets:")
    for s in sets:
        print(f"  {s.get('Name')}")
    sys.exit(1)
set_id = matches[0]["Id"]
print(f"Using set: {matches[0]['Name']}")

parts = []
if file_name:
    parts.append(f'fileName {file_match} "{file_name}"')
if user_filter:
    parts.append(f'user CONTAINS "{user_filter}"')
if computer:
    parts.append(f'computerName CONTAINS "{computer}"')
if event_types:
    parts.append(f"eventType IN {','.join(event_types)}")
parts.append(f"arrivalTime GE {date_from.strftime('%Y-%m-%dT%H:%M:%SZ')}")
parts.append(f"arrivalTime LE {date_to.strftime('%Y-%m-%dT%H:%M:%SZ')}")
filter_text = " AND ".join(parts)
print(f"Filter: {filter_text}")
body = {"filter": filter_text}
method = "POST"
events = []
seen = set()
cursor = "start"
page_number = 0
while True:
    uri = f"{base_url}/API/Sets/{set_id}/Events/Search?nextCursor={urllib.parse.quote(cursor, safe='')}&limit=1000"
    response = epm_request(method, uri, headers, body)
    data = response.json()
    page = data.get("events") or []
    page_number += 1
    events += page
    print(f"Page {page_number}: {len(page)} events, {len(events)} of {data.get('filteredCount')} so far")
    cursor = data.get("nextCursor") or ""
    if not page or not cursor or cursor in seen:
        break
    seen.add(cursor)
if not events:
    print("No events found.")
else:
    columns = ["arrivalTime", "firstEventDate", "lastEventDate", "eventType", "computerName", "userName", "fileName", "filePath", "fileDescription", "productName", "publisher", "hash", "policyName", "sourceType", "sourceName", "processCommandLine", "parentProcess", "justification", "userIsAdmin", "eventCount", "agentId", "eventId"]
    with open(out_path, "w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(events)
    print(f"Exported {len(events)} events to {out_path}")
