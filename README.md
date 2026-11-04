# EPM-Rest-API-Scripts

PowerShell and Python scripts for the Idira (CyberArk) Endpoint Privilege Manager REST APIs.

## API documentation

[EPM developer documentation](https://docs.cyberark.com/epm/latest/en/content/landingpages/lpdeveloper.htm)

## Folders

- `PowerShell examples` has one script for each API.
- `Python examples` has the same scripts in Python.

## How to use

You need an Identity service user and its web app ID, and the tenant ID.

PowerShell:

1. Open a PowerShell window.
2. Run a script, for example `.\00-Get-Token.ps1`.
3. Type in the values it asks for.

Python:

1. Run `pip install -r requirements.txt` once.
2. Run a script, for example `python 01-Get-Sets.py`.
3. Type in the values it asks for.

Every script signs in first, then asks for the EPM URL, the set ID and anything else the call needs. Nothing is saved.

Some scripts delete or change things. Read the name of the script before you run it.
