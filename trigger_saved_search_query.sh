#!/bin/bash

# ===========================================================
# trigger_saved_search_query.sh
# Version: 1.1
# Date: 2025-06-28
#
# Description:
# - This script triggers specific Splunk saved searches defined in the ALERTS array.
# - Saved searches (Alerts, Reports configured on Splunk Web UI) are triggered individually.
# - The script can be triggered as an action in Splunk alerts or run manually.
#
# Usage:
# - Set the required environment variables (SPLUNK_TOKEN, etc.) on the system where this script runs.
# - Modify the ALERTS array below to include the exact names of saved searches you want to trigger.
# - Set this script (trigger_saved_search_query.sh) as a triggered action in an Alert, or run it manually on the command line.
#
# WARNING:
# - Do not cause any infinite loops by triggering this script from an alert that it itself triggers.
#
# Key Features:
# - Triggers predefined saved searches from the ALERTS array
# - Triggers all searches simultaneously via Splunk REST API
# - Tracks search execution status with unique Search IDs (SIDs)
# - Comprehensive error handling and logging
# - Configurable via environment variables
# - URL-safe encoding for search names with special characters
# - Uses secure token-based authentication
#
# Requirements:
#
# - Splunk Enterprise with REST API enabled (default port 8089)
# - Valid Splunk authentication token with the following capabilities:
#   * dispatch_search
#   * rest_search_list
#   * schedule_search
#   * list_saved_search
# - Network access to Splunk management interface (default: https://localhost:8089)
# - Bash shell environment (Linux/Unix)
#
#
# Environment Variables (or set in script):
#
# SPLUNK_TOKEN                  - Splunk authentication token (Bearer token)
# SPLUNK_MANAGEMENT_ENDPOINT    - Splunk REST API URL (default: https://localhost:8089)
# OWNER                         - Owner of the saved searches
# APP                           - Splunk app context (default: search)
# ENABLE_LOGGING                - Enable file logging (default: true)
# SPLUNK_HOME                   - Splunk installation path (default: /opt/splunk)
#
# Output:
# - Console output with timestamps and status messages
# - Optional log file: $SPLUNK_HOME/var/log/splunk/$SCRIPT_NAME.log
# - Search IDs (SIDs) for monitoring search progress in Splunk
#
# Exit Codes:
# 0 - Success (all searches triggered or no matching searches found)
# 1 - Configuration validation failed or critical error
#
# Security Notes:
# - Store authentication tokens securely (consider using environment files)
# - Restrict script permissions to authorized users only
# - Use HTTPS for Splunk management endpoint
# - Regularly rotate Splunk authentication tokens
# - Authentication tokens should have minimal required permissions
#
# ===========================================================

# ===== USER DEFINED PARAMETERS (environment or set here) ===
SCRIPT_NAME="trigger_saved_search_query.sh" # Name of this script (for logging and safety checks)

SPLUNK_HOME="${SPLUNK_HOME:-/opt/splunk}" # Splunk installation directory (default: /opt/splunk)
SPLUNK_TOKEN="${SPLUNK_TOKEN:-changeme}" # Splunk authentication token (Bearer token)

SPLUNK_MANAGEMENT_ENDPOINT="${SPLUNK_MANAGEMENT_ENDPOINT:-https://localhost:8089}" # Splunk REST API endpoint (default: https://localhost:8089)
OWNER="${OWNER:-changeme}" # Owner of the saved searches
APP="${APP:-search}" # Splunk app context (default: search)

# List of alert names to trigger (must match saved search names exactly)
ALERTS=(
  "Saved Alert 1 CHANGEME"
  "Saved Alert 2 CHANGEME"
)

# ===========================================================

# ====== OPTIONAL PARAMETERS ================================
LOG_FILE_NAME="${SCRIPT_NAME%.*}.log"  # Log file name based on script name
ENABLE_LOGGING="${ENABLE_LOGGING:-true}" # Set to false to disable file logging
LOG_DIR="${SPLUNK_HOME}/var/log/splunk" # Log directory (default: $SPLUNK_HOME/var/log/splunk)
LOG_FILE="${LOG_DIR}/${LOG_FILE_NAME}"
# ===========================================================

# WARNING: DO NOT MODIFY BELOW THIS LINE UNLESS YOU KNOW WHAT YOU ARE DOING

# Validation function
validate_parameters() {
    local errors=0

    # Check SPLUNK_TOKEN
    if [[ -z "$SPLUNK_TOKEN" ]]; then
        echo "ERROR: SPLUNK_TOKEN cannot be empty" >&2
        errors=$((errors + 1))
    elif [[ ${#SPLUNK_TOKEN} -lt 32 ]]; then
        echo "WARNING: SPLUNK_TOKEN appears to be shorter than expected (< 32 characters)" >&2
    fi

    # Check SPLUNK_MANAGEMENT_ENDPOINT format
    if [[ ! "$SPLUNK_MANAGEMENT_ENDPOINT" =~ ^https?://[a-zA-Z0-9.-]+:[0-9]+$ ]]; then
        echo "ERROR: SPLUNK_MANAGEMENT_ENDPOINT must be in format http(s)://hostname:port" >&2
        echo "Current value: $SPLUNK_MANAGEMENT_ENDPOINT" >&2
        errors=$((errors + 1))
    fi

    # Check OWNER
    if [[ -z "$OWNER" || "$OWNER" =~ [[:space:]] ]]; then
        echo "ERROR: OWNER cannot be empty or contain spaces" >&2
        errors=$((errors + 1))
    fi

    # Check APP
    if [[ -z "$APP" || "$APP" =~ [[:space:]] ]]; then
        echo "ERROR: APP cannot be empty or contain spaces" >&2
        errors=$((errors + 1))
    fi

    # Check LOG_DIR exists or can be created
    if [[ ! -d "$LOG_DIR" ]]; then
        if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
            echo "WARNING: Cannot create log directory $LOG_DIR. Using current directory." >&2
            LOG_DIR="."
            LOG_FILE="$LOG_DIR/$LOG_FILE_NAME"
        fi
    fi

    # Check LOG_FILE is writable (after potential LOG_FILE update above)
    if ! touch "$LOG_FILE" 2>/dev/null; then
        echo "ERROR: Cannot write to log file $LOG_FILE" >&2
        errors=$((errors + 1))
    fi

    if [[ $errors -gt 0 ]]; then
        echo "Total validation errors: $errors" >&2
        return 1
    fi
    return $errors;
  }

# Run validation
echo "Validating configuration parameters..."
if ! validate_parameters; then
    echo "Configuration validation failed. Exiting."
    exit 1
fi

echo "Configuration validation passed."

log_message() {
    local message="$(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo "$message"

    # Only write to file if logging is enabled
    if [[ "$ENABLE_LOGGING" == "true" ]]; then
        echo "$message" >> "$LOG_FILE"
    fi
}

# Function to check if a saved search has trigger actions that could cause infinite loops
check_alert_actions() {
    local alert_name="$1"
    local encoded_alert=$(url_encode "$alert_name")

    log_message "Checking trigger actions for alert: $alert_name"

    # Get saved search configuration
    local response=$(curl -s -k -H "Authorization: Bearer $SPLUNK_TOKEN" \
        "$SPLUNK_MANAGEMENT_ENDPOINT/servicesNS/$OWNER/$APP/saved/searches/$encoded_alert" \
        --retry 2 \
        --fail-with-body)

    local curl_exit_code=$?

    # If first attempt fails, try with wildcard namespace
    if [ $curl_exit_code -ne 0 ]; then
        log_message "Retrying with wildcard namespace for configuration check..."
        response=$(curl -s -k -H "Authorization: Bearer $SPLUNK_TOKEN" \
            "$SPLUNK_MANAGEMENT_ENDPOINT/servicesNS/-/-/saved/searches/$encoded_alert" \
            --retry 2 \
            --fail-with-body)
        curl_exit_code=$?
    fi

    if [ $curl_exit_code -ne 0 ]; then
        log_message "WARNING: Could not retrieve configuration for alert: $alert_name. Proceeding with caution."
        return 0  # Allow triggering if we can't check (with warning)
    fi

    # Check for trigger actions that might execute this script
    local dangerous_patterns=(
        "$SCRIPT_NAME"
        "${SCRIPT_NAME%.*}"  # Script name without extension
        "bash.*$SCRIPT_NAME"
        "sh.*$SCRIPT_NAME"
        "/bin/bash.*$SCRIPT_NAME"
        "/bin/sh.*$SCRIPT_NAME"
    )

    for pattern in "${dangerous_patterns[@]}"; do
        if echo "$response" | grep -qi "$pattern"; then
            log_message "DANGER: Alert '$alert_name' contains trigger action that may execute this script!"
            log_message "DANGER: Pattern detected: $pattern"
            log_message "DANGER: Skipping this alert to prevent infinite loop"
            return 1  # Dangerous - skip this alert
        fi
    done

    # Check for webhook or script actions that might indirectly trigger this script
    if echo "$response" | grep -qi "action\.script\|action\.webhook\|action\.custom"; then
        log_message "WARNING: Alert '$alert_name' has script/webhook actions. Please verify they don't trigger this script."
    fi

    log_message "SAFE: Alert '$alert_name' appears safe to trigger"
    return 0  # Safe to trigger
}

log_message "Script started"

# Check if ALERTS array is not empty
if [ ${#ALERTS[@]} -eq 0 ]; then
    log_message "ERROR: No alerts defined in ALERTS array. Please configure alerts to trigger."
    exit 1
fi

log_message "Found ${#ALERTS[@]} alerts configured to trigger"

# Function to URL encode alert names
url_encode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * ) printf -v o '%%%02x' "'$c"
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

# Array to store triggered search IDs for status tracking
TRIGGERED_SIDS=()
TRIGGERED_ALERTS=()

log_message "Starting to trigger ${#ALERTS[@]} alerts"

# Track alerts that are skipped due to safety checks
SKIPPED_ALERTS=()

for ALERT in "${ALERTS[@]}"; do
    log_message "Processing alert: $ALERT"

    # Check if this alert is safe to trigger (prevent infinite loops)
    if ! check_alert_actions "$ALERT"; then
        log_message "SKIPPED: Alert '$ALERT' was skipped due to safety check"
        SKIPPED_ALERTS+=("$ALERT")
        log_message "-----------------------------"
        continue
    fi

    log_message "Triggering alert: $ALERT"

    ENCODED_ALERT=$(url_encode "$ALERT")

    RESPONSE=$(curl -s -k -H "Authorization: Bearer $SPLUNK_TOKEN" \
    "$SPLUNK_MANAGEMENT_ENDPOINT/servicesNS/$OWNER/$APP/saved/searches/$ENCODED_ALERT/dispatch" \
    -d trigger_actions=1 \
    --retry 3 \
    --fail-with-body)

    CURL_EXIT_CODE=$?

    if [ $CURL_EXIT_CODE -eq 0 ] && echo "$RESPONSE" | grep -q "<sid>"; then
    # Extract the search ID from the response
    SID=$(echo "$RESPONSE" | grep -o '<sid>[^<]*</sid>' | sed 's/<[^>]*>//g')
    log_message "SUCCESS: Successfully triggered: $ALERT (SID: $SID)"

    # Store SID for status tracking
    TRIGGERED_SIDS+=("$SID")
    TRIGGERED_ALERTS+=("$ALERT")

  elif [ $CURL_EXIT_CODE -eq 22 ]; then
    # Try alternative namespace
    log_message "Retrying with wildcard namespace..."
    RESPONSE=$(curl -s -k -H "Authorization: Bearer $SPLUNK_TOKEN" \
      "$SPLUNK_MANAGEMENT_ENDPOINT/servicesNS/-/-/saved/searches/$ENCODED_ALERT/dispatch" \
      -d trigger_actions=1 \
      --retry 3 \
      --fail-with-body)

    CURL_EXIT_CODE=$?

    if [ $CURL_EXIT_CODE -eq 0 ] && echo "$RESPONSE" | grep -q "<sid>"; then
      SID=$(echo "$RESPONSE" | grep -o '<sid>[^<]*</sid>' | sed 's/<[^>]*>//g')
      log_message "SUCCESS: Successfully triggered with wildcard namespace: $ALERT (SID: $SID)"
    else
      log_message "FAILED: Search not found or permission denied: $ALERT"
      log_message "Response: $(echo "$RESPONSE" | head -c 500)"
    fi
  else
    log_message "FAILED: Failed to trigger: $ALERT (Exit code: $CURL_EXIT_CODE)"
    log_message "Response: $(echo "$RESPONSE" | head -c 500)"
  fi

  log_message "-----------------------------"
done

# Add summary of skipped alerts at the end
if [ ${#SKIPPED_ALERTS[@]} -gt 0 ]; then
    log_message "SUMMARY: ${#SKIPPED_ALERTS[@]} alerts were skipped due to safety checks:"
    for skipped in "${SKIPPED_ALERTS[@]}"; do
        log_message "  - $skipped"
    done
    log_message "Please review these alerts' trigger actions to ensure they don't cause infinite loops."
fi

log_message "Script execution completed. Triggered: $((${#ALERTS[@]} - ${#SKIPPED_ALERTS[@]})) alerts, Skipped: ${#SKIPPED_ALERTS[@]} alerts"
