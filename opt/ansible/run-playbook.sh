#!/bin/bash

# Ansible Playbook Runner with Enhanced Logging
# Usage: ./run-playbook.sh <playbook-path>

set -euo pipefail

# Configuration
PLAYBOOK_PATH="${1:-/opt/ansible/playbooks/main.yml}"
LOG_DIR="/var/log/ansible"
DATE_STAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="${LOG_DIR}/cron-${DATE_STAMP}.log"
SUMMARY_FILE="${LOG_DIR}/summary-${DATE_STAMP}.json"

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Function to send notifications (customize as needed)
send_notification() {
    local status="$1"
    local message="$2"

    # Option 1: Log to system journal
    logger -t ansible-cron "$status: $message"

    # Option 2: Send email (requires mail setup)
    # echo "$message" | mail -s "Ansible Job $status" admin@company.com

    # Option 3: Send to Slack (requires webhook)
    # curl -X POST -H 'Content-type: application/json' \
    #   --data "{\"text\":\"Ansible Job $status: $message\"}" \
    #   YOUR_SLACK_WEBHOOK_URL
}

# Run Ansible playbook with comprehensive logging
echo "Starting Ansible playbook execution at $(date)" | tee "$LOG_FILE"
echo "Playbook: $PLAYBOOK_PATH" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

if ansible-playbook "$PLAYBOOK_PATH" \
    --extra-vars "execution_timestamp=${DATE_STAMP}" \
    2>&1 | tee -a "$LOG_FILE"; then

    send_notification "SUCCESS" "Playbook completed successfully"
    echo "SUCCESS: Playbook execution completed" | tee -a "$LOG_FILE"
    exit 0
else
    send_notification "FAILED" "Playbook execution failed. Check logs at $LOG_FILE"
    echo "FAILED: Playbook execution failed" | tee -a "$LOG_FILE"
    exit 1
fi
