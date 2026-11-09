# EPM-Rest-API-Scripts

PowerShell and Python scripts for the Idira (CyberArk) Endpoint Privilege Manager REST APIs.

> **Note:** This project is provided as-is. It is not supported by Palo Alto Networks nor an official Idira solution.

## API documentation

[EPM developer documentation](https://docs.cyberark.com/epm/latest/en/content/landingpages/lpdeveloper.htm)

## Folders

- `PowerShell examples` has one script for each API.
- `Python examples` has the same scripts in Python.
- `Requested scripts` has scripts that people have asked for, in PowerShell and Python. `Delete-Duplicate-Endpoints` finds endpoints with the same name in a set, keeps the one seen most recently and deletes the rest. It lists what it would remove first and only deletes if you type DELETE.

## How to use

You need an Identity service user and its web app ID, and the tenant ID.

PowerShell:

1. Open a PowerShell window in the `PowerShell examples` folder.
2. Run a script, for example `.\00-Get-Token.ps1`.
3. Type in the values it asks for.

Python:

1. Open a terminal in the `Python examples` folder and run `pip install -r requirements.txt` once.
2. Run a script, for example `python 01-Get-Sets.py`.
3. Type in the values it asks for.

Every script signs in first, then asks for the EPM URL, the set ID and anything else the call needs. Nothing is saved.

Some scripts delete or change things. Read the name of the script before you run it.

## Support

This project is neither developed nor supported by Palo Alto Networks; any official support channels offered by the vendor are not appropriate for seeking help with the implementation or function of this project.

Help should be sought by opening an issue in this repository.
