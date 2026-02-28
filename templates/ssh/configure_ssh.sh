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

# Disable password authentication
sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*KbdInteractiveAuthentication .*/KbdInteractiveAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*ChallengeResponseAuthentication .*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

systemctl restart ssh
