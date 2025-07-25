# Check Ansible configuration
ansible-config dump

# Test log parsing
echo '{"event": "runner_on_ok", "event_data": {"task": "test"}}' | /opt/ansible/log-analyzer.py /dev/stdin

# Monitor disk usage
du -h /var/log/ansible/

# Check cron job status
grep CRON /var/log/messages | tail -10
