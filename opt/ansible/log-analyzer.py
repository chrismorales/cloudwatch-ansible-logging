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
