#!/bin/bash

# Ansible Log Parser
# Extracts key information from Ansible JSON logs

LOG_FILE="${1:-/var/log/ansible/ansible.log}"
OUTPUT_FORMAT="${2:-summary}" # options: summary, detailed, failed-only

if [[ ! -f "$LOG_FILE" ]]; then
    echo "Error: Log file $LOG_FILE not found"
    exit 1
fi

echo "Ansible Log Analysis - $(date)"
echo "Log file: $LOG_FILE"
echo "========================================"

case $OUTPUT_FORMAT in
    "summary")
        echo "EXECUTION SUMMARY:"
        echo "------------------"
        # Extract basic execution info
        grep -E "PLAY RECAP|TASK \[|fatal:" "$LOG_FILE" | tail -20
        ;;

    "detailed")
        echo "DETAILED TASK BREAKDOWN:"
        echo "------------------------"
        # Parse JSON logs for detailed task info
        if command -v jq >/dev/null 2>&1; then
            jq -r '
                select(.event_data.task_action != "setup") |
                "\(.event_data.task): \(.event_data.remote_addr // "localhost"): \(.event_data.task_action) - \(
                    if .event_data.changed then "CHANGED"
                    elif .event_data.failed then "FAILED"
                    else "OK" end
                )"
            ' "$LOG_FILE" 2>/dev/null || echo "No JSON data found or jq not installed"
        else
            echo "Install jq for detailed JSON parsing: sudo yum install jq -y"
        fi
        ;;

    "failed-only")
        echo "FAILED TASKS ONLY:"
        echo "------------------"
        grep -A 5 -B 5 "fatal:\|failed:" "$LOG_FILE" | head -50
        ;;
esac

echo ""
echo "Log file size: $(du -h "$LOG_FILE" | cut -f1)"
echo "Last modified: $(stat -c %y "$LOG_FILE")"
