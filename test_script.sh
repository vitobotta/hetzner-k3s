#!/bin/bash
echo "Hello from node $(hostname)"
echo "Current date: $(date)"
echo "Uptime: $(uptime)"
echo "Disk usage:"
df -h /
echo "Memory usage:"
free -h