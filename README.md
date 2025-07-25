# Ansible Logging Setup Guide for EC2

This guide provides step-by-step instructions for setting up comprehensive Ansible logging on an EC2 instance with automated parsing and monitoring capabilities.

## Prerequisites

- EC2 instance with Ansible installed
- Root or sudo access
- Basic familiarity with cron jobs and shell scripting

## Step 1: Configure Ansible Logging

### 1.1 Create Log Directory Structure

```bash
sudo mkdir -p /var/log/ansible
sudo chown $USER:$USER /var/log/ansible
sudo chmod 755 /var/log/ansible
```

### 1.2 Configure ansible.cfg

Create or update your `ansible.cfg` file (typically in `/etc/ansible/ansible.cfg` or in your project directory):

```ini
[defaults]
# Enable logging to file
log_path = /var/log/ansible/ansible.log

# Use JSON callback for structured output
stdout_callback = json

# Enable additional callback plugins for performance insights
callback_whitelist = profile_tasks, timer

# Reduce noise in logs
display_skipped_hosts = False
display_ok_hosts = False

# Host key checking (adjust based on your security requirements)
host_key_checking = False

[ssh_connection]
# Reduce SSH timeout issues
ssh_args = -o ControlMaster=auto -o ControlPersist=60s
```

## Step 2: Create Enhanced Cron Job

### 2.1 Create Ansible Runner Script

Create `/opt/ansible/run-playbook.sh`:

```bash
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
```

Make the script executable:

```bash
sudo chmod +x /opt/ansible/run-playbook.sh
```

### 2.2 Set Up Cron Job

Add to crontab (`crontab -e`):

```bash
# Run Ansible playbook daily at 2 AM
0 2 * * * /opt/ansible/run-playbook.sh /path/to/your/playbook.yml

# Optional: Run log cleanup weekly
0 3 * * 0 find /var/log/ansible -name "*.log" -mtime +30 -delete
```

## Step 3: Create Log Parsing Tools

### 3.1 Simple Log Parser Script

Create `/opt/ansible/parse-logs.sh`:

```bash
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
```

Make it executable:

```bash
sudo chmod +x /opt/ansible/parse-logs.sh
```

### 3.2 Advanced Python Log Analyzer

Create `/opt/ansible/log-analyzer.py`:

```python
#!/usr/bin/env python3

import json
import sys
import os
from datetime import datetime
from collections import defaultdict

class AnsibleLogAnalyzer:
    def __init__(self, log_file):
        self.log_file = log_file
        self.stats = {
            'total_tasks': 0,
            'changed_tasks': 0,
            'failed_tasks': 0,
            'skipped_tasks': 0,
            'ok_tasks': 0,
            'execution_time': 0,
            'hosts': set(),
            'failed_details': []
        }
    
    def parse_log(self):
        """Parse Ansible JSON log file"""
        if not os.path.exists(self.log_file):
            print(f"Error: Log file {self.log_file} not found")
            return False
        
        try:
            with open(self.log_file, 'r') as f:
                for line in f:
                    try:
                        log_entry = json.loads(line.strip())
                        self._process_entry(log_entry)
                    except json.JSONDecodeError:
                        # Skip non-JSON lines
                        continue
        except Exception as e:
            print(f"Error reading log file: {e}")
            return False
        
        return True
    
    def _process_entry(self, entry):
        """Process individual log entry"""
        if 'event_data' not in entry:
            return
        
        event_data = entry['event_data']
        
        # Track hosts
        if 'remote_addr' in event_data:
            self.stats['hosts'].add(event_data['remote_addr'])
        
        # Process task results
        if entry.get('event') == 'runner_on_ok':
            self.stats['total_tasks'] += 1
            self.stats['ok_tasks'] += 1
            if event_data.get('changed', False):
                self.stats['changed_tasks'] += 1
        
        elif entry.get('event') == 'runner_on_failed':
            self.stats['total_tasks'] += 1
            self.stats['failed_tasks'] += 1
            self.stats['failed_details'].append({
                'task': event_data.get('task', 'Unknown'),
                'host': event_data.get('remote_addr', 'Unknown'),
                'error': event_data.get('msg', 'No error message')
            })
        
        elif entry.get('event') == 'runner_on_skipped':
            self.stats['skipped_tasks'] += 1
    
    def generate_report(self):
        """Generate summary report"""
        print("ANSIBLE EXECUTION REPORT")
        print("=" * 50)
        print(f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"Log file: {self.log_file}")
        print()
        
        print("EXECUTION STATISTICS:")
        print("-" * 30)
        print(f"Total tasks: {self.stats['total_tasks']}")
        print(f"Successful tasks: {self.stats['ok_tasks']}")
        print(f"Changed tasks: {self.stats['changed_tasks']}")
        print(f"Failed tasks: {self.stats['failed_tasks']}")
        print(f"Skipped tasks: {self.stats['skipped_tasks']}")
        print(f"Managed hosts: {len(self.stats['hosts'])}")
        print()
        
        if self.stats['failed_tasks'] > 0:
            print("FAILED TASKS DETAILS:")
            print("-" * 30)
            for failure in self.stats['failed_details']:
                print(f"Task: {failure['task']}")
                print(f"Host: {failure['host']}")
                print(f"Error: {failure['error']}")
                print()
        
        # Calculate success rate
        if self.stats['total_tasks'] > 0:
            success_rate = ((self.stats['ok_tasks'] / self.stats['total_tasks']) * 100)
            print(f"Success rate: {success_rate:.1f}%")
        
        return self.stats['failed_tasks'] == 0

def main():
    if len(sys.argv) < 2:
        log_file = "/var/log/ansible/ansible.log"
    else:
        log_file = sys.argv[1]
    
    analyzer = AnsibleLogAnalyzer(log_file)
    
    if analyzer.parse_log():
        success = analyzer.generate_report()
        sys.exit(0 if success else 1)
    else:
        sys.exit(1)

if __name__ == "__main__":
    main()
```

Make it executable:

```bash
sudo chmod +x /opt/ansible/log-analyzer.py
```

## Step 4: Set Up Log Rotation

Create `/etc/logrotate.d/ansible`:

```bash
/var/log/ansible/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 $USER $USER
}
```

## Step 5: CloudWatch Integration (Optional)

### 5.1 Install CloudWatch Agent

```bash
# Download and install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
sudo rpm -U ./amazon-cloudwatch-agent.rpm
```

### 5.2 Configure CloudWatch Agent

Create `/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json`:

```json
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/ansible/ansible.log",
                        "log_group_name": "/aws/ec2/ansible",
                        "log_stream_name": "{instance_id}-ansible-main",
                        "timestamp_format": "%Y-%m-%d %H:%M:%S"
                    },
                    {
                        "file_path": "/var/log/ansible/cron-*.log",
                        "log_group_name": "/aws/ec2/ansible",
                        "log_stream_name": "{instance_id}-ansible-cron",
                        "timestamp_format": "%Y-%m-%d %H:%M:%S"
                    }
                ]
            }
        }
    }
}
```

### 5.3 Start CloudWatch Agent

```bash
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config -m ec2 -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
```

## Step 6: Usage Examples

### View Latest Execution Summary
```bash
/opt/ansible/parse-logs.sh /var/log/ansible/$(ls -t /var/log/ansible/cron-*.log | head -1) summary
```

### Analyze Specific Log File
```bash
/opt/ansible/log-analyzer.py /var/log/ansible/cron-20241125-020001.log
```

### Check Failed Tasks Only
```bash
/opt/ansible/parse-logs.sh /var/log/ansible/ansible.log failed-only
```

### Real-time Log Monitoring
```bash
tail -f /var/log/ansible/ansible.log | grep -E "(TASK|PLAY|fatal|failed)"
```

## Step 7: Monitoring and Alerting

### 7.1 Create Health Check Script

Create `/opt/ansible/health-check.sh`:

```bash
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
```

### 7.2 Add Health Check to Cron

```bash
# Check Ansible health every hour and log results
0 * * * * /opt/ansible/health-check.sh >> /var/log/ansible/health.log 2>&1
```

## Troubleshooting

### Common Issues

1. **Permission denied errors**: Ensure the user running Ansible has proper permissions to write to log directory
2. **JSON parsing fails**: Verify `stdout_callback = json` is set in ansible.cfg
3. **Logs not rotating**: Check logrotate configuration and ensure logrotate service is running
4. **CloudWatch agent not sending logs**: Verify IAM permissions for CloudWatch Logs

### Useful Commands

```bash
# Check Ansible configuration
ansible-config dump

# Test log parsing
echo '{"event": "runner_on_ok", "event_data": {"task": "test"}}' | /opt/ansible/log-analyzer.py /dev/stdin

# Monitor disk usage
du -h /var/log/ansible/

# Check cron job status
grep CRON /var/log/messages | tail -10
```

## Security Considerations

- Ensure log files have appropriate permissions (640 or 644)
- Consider encrypting sensitive data in logs
- Regularly rotate and archive old logs
- Restrict access to log directories
- Use IAM roles for CloudWatch access instead of access keys

## Next Steps

1. Customize notification methods in the runner script
2. Set up alerting based on failed execution patterns
3. Integrate with your existing monitoring infrastructure
4. Consider using Ansible AWX/Tower for more advanced logging and UI capabilities
