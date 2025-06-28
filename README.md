# trigger_saved_search_query.sh

---

## Description

- This script triggers specific Splunk saved searches defined in the `ALERTS` array.
- Saved searches (alerts or reports configured on the Splunk Web UI) are triggered individually.
- The script can be triggered as an action in Splunk alerts or run manually via a bash shell

---

## Usage

1. Set the required environment variables (`SPLUNK_TOKEN`, etc.) on the system where this script runs.
2. Modify the `ALERTS` array in the script to include the **exact names** of saved searches you want to trigger.
3. Run the script:
   - As a **triggered action** in a Splunk alert
   - Or manually via the command line

> ⚠️ **WARNING:** Do **not** create infinite loops by triggering this script from an alert that it itself triggers.

---

## Key Features

- Triggers predefined saved searches from the `ALERTS` array
- Triggers all searches **simultaneously** via Splunk REST API
- Tracks execution status with unique **Search IDs (SIDs)**
- Comprehensive **error handling** and **logging**
- Fully **configurable** via environment variables
- URL-safe encoding for search names with special characters
- Uses **secure token-based authentication**

---

## Requirements

- **Splunk Enterprise** with REST API enabled (default port: `8089`)
- A **valid Splunk authentication token** with the following capabilities:
  - `dispatch_search`
  - `rest_search_list`
  - `schedule_search`
  - `list_saved_search`
- Network access to the Splunk management interface (default: `https://localhost:8089`)
- Bash shell environment (Linux/Unix)

---

## 🔧 Environment Variables

| Variable                      | Description                                                    |
|------------------------------|----------------------------------------------------------------|
| `SPLUNK_TOKEN`               | Splunk authentication token (Bearer token)                     |
| `SPLUNK_MANAGEMENT_ENDPOINT` | Splunk REST API URL (default: `https://localhost:8089`)        |
| `OWNER`                      | Owner of the saved searches                                    |
| `APP`                        | Splunk app context (default: `search`)                         |
| `ENABLE_LOGGING`             | Enable file logging (default: `true`)                          |
| `SPLUNK_HOME`                | Splunk installation path (default: `/opt/splunk`)              |

---

## Output

- Console output with **timestamps** and **status messages**
- Optional log file:  
  `$SPLUNK_HOME/var/log/splunk/trigger_saved_search_query.sh.log`
- Search IDs (SIDs) for monitoring search progress in Splunk

---

## Exit Codes

| Code | Meaning                                           |
|------|---------------------------------------------------|
| `0`  | Success (all searches triggered or no matches)   |
| `1`  | Configuration validation failed or critical error|

---

## Security Notes

- Store authentication tokens **securely** (e.g., environment files)
- Restrict script permissions to **authorized users only**
- Use **HTTPS** for the Splunk management endpoint
- Regularly **rotate** Splunk authentication tokens
- Ensure tokens have **minimal required permissions**

---
