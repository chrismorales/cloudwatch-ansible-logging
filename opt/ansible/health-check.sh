#!/bin/bash

# Check if last Ansible run was successful
LATEST_LOG=$(ls -t /var/log/ansible/cron-*.log 2>/dev/null | head -1)

if [[ -z "$LATEST_LOG" ]]; then
    echo "WARNING: No cron execution logs found"
    exit 1
fi

# Check if the latest run was successful
if grep -q "SUCCESS: Playbook execution completed" "$LATEST_LOG"; then
    echo "OK: Latest Ansible execution successful"
    exit 0
else
    echo "CRITICAL: Latest Ansible execution failed"
    exit 2
fi
