#!/bin/bash
#
#           PreRequisite
#
#   * Install Wget
#   * Install CloudWatch Agent

# Download and install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
sudo rpm -U ./amazon-cloudwatch-agent.rpm
