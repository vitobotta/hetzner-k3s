if systemctl is-active ssh.socket > /dev/null 2>&1
then
  # OpenSSH is using socket activation
  systemctl disable ssh
  systemctl daemon-reload
  systemctl restart ssh.socket
  systemctl stop ssh
else
  # OpenSSH is not using socket activation
  sed -i 's/^#*Port .*/Port {{ ssh_port }}/' /etc/ssh/sshd_config
fi
systemctl restart ssh
