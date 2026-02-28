#!/bin/bash
#
# Disable SSH password authentication on cluster nodes
# Date: 2026-02-28
# Bug fix: https://github.com/vitobotta/hetzner-k3s/issues/736
#
# This script disables password-based SSH authentication and enforces
# key-based authentication only. Run this on each node in your cluster.
#
# Usage: sudo bash 2026-02-28-disable-ssh-password-auth.sh
#        VERBOSE=1 sudo bash 2026-02-28-disable-ssh-password-auth.sh  # Enable verbose output
#

# Enable verbose output if VERBOSE or DEBUG is set
if [[ -n "${VERBOSE:-}" || -n "${DEBUG:-}" ]]; then
  set -euo pipefail -x
else
  set -euo pipefail
fi

readonly SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_SERVICE="ssh"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
    log "ERROR: This script must be run as root (use sudo)"
    exit 1
  fi
}

backup_sshd_config() {
  local backup_file="${SSHD_CONFIG}.backup.$(date +%Y%m%d%H%M%S)"
  log "Backing up sshd_config to ${backup_file}"
  cp "${SSHD_CONFIG}" "${backup_file}"
}

update_sshd_config() {
  log "Updating sshd_config..."

  # Set PasswordAuthentication to no
  if grep -qE '^#*PasswordAuthentication' "${SSHD_CONFIG}"; then
    sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' "${SSHD_CONFIG}"
    log "  - Set PasswordAuthentication no"
  else
    echo "PasswordAuthentication no" >> "${SSHD_CONFIG}"
    log "  - Added PasswordAuthentication no"
  fi

  # Set KbdInteractiveAuthentication to no (OpenSSH 6.2+)
  if grep -qE '^#*KbdInteractiveAuthentication' "${SSHD_CONFIG}"; then
    sed -i 's/^#*KbdInteractiveAuthentication .*/KbdInteractiveAuthentication no/' "${SSHD_CONFIG}"
    log "  - Set KbdInteractiveAuthentication no"
  else
    echo "KbdInteractiveAuthentication no" >> "${SSHD_CONFIG}"
    log "  - Added KbdInteractiveAuthentication no"
  fi

  # Set ChallengeResponseAuthentication to no (legacy/compatibility)
  if grep -qE '^#*ChallengeResponseAuthentication' "${SSHD_CONFIG}"; then
    sed -i 's/^#*ChallengeResponseAuthentication .*/ChallengeResponseAuthentication no/' "${SSHD_CONFIG}"
    log "  - Set ChallengeResponseAuthentication no"
  else
    echo "ChallengeResponseAuthentication no" >> "${SSHD_CONFIG}"
    log "  - Added ChallengeResponseAuthentication no"
  fi

  # Set PermitRootLogin to prohibit-password (root can only use keys)
  if grep -qE '^#*PermitRootLogin' "${SSHD_CONFIG}"; then
    sed -i 's/^#*PermitRootLogin .*/PermitRootLogin prohibit-password/' "${SSHD_CONFIG}"
    log "  - Set PermitRootLogin prohibit-password"
  else
    echo "PermitRootLogin prohibit-password" >> "${SSHD_CONFIG}"
    log "  - Added PermitRootLogin prohibit-password"
  fi
}

detect_ssh_service() {
  # Detect the correct SSH service name (ssh vs sshd)
  if systemctl list-unit-files | grep -q "^ssh\.service"; then
    SSHD_SERVICE="ssh"
  elif systemctl list-unit-files | grep -q "^sshd\.service"; then
    SSHD_SERVICE="sshd"
  fi
  log "Detected SSH service: ${SSHD_SERVICE}"
}

validate_sshd_config() {
  log "Validating sshd configuration..."
  if ! sshd -t; then
    log "ERROR: sshd configuration test failed!"
    log "Restoring backup..."
    cp "${SSHD_CONFIG}.backup."* "${SSHD_CONFIG}"
    exit 1
  fi
  log "  - Configuration valid"
}

restart_ssh_service() {
  log "Restarting SSH service..."
  systemctl restart "${SSHD_SERVICE}"
  log "  - SSH service restarted"
}

verify_ssh_session() {
  log "Verifying SSH configuration..."
  
  # Get current SSH daemon settings
  local password_auth
  local kbd_auth
  local root_login
  
  password_auth=$(sshd -T 2>/dev/null | grep -i "^passwordauthentication" | awk '{print $2}' || echo "unknown")
  kbd_auth=$(sshd -T 2>/dev/null | grep -i "^kbdinteractiveauthentication" | awk '{print $2}' || echo "unknown")
  root_login=$(sshd -T 2>/dev/null | grep -i "^permitrootlogin" | awk '{print $2}' || echo "unknown")
  
  log "  - PasswordAuthentication: ${password_auth}"
  log "  - KbdInteractiveAuthentication: ${kbd_auth}"
  log "  - PermitRootLogin: ${root_login}"
  
  if [[ "${password_auth}" != "no" ]]; then
    log "WARNING: PasswordAuthentication is not set to 'no'"
  fi
}

main() {
  log "=== SSH Password Authentication Disable Script ==="
  log ""
  
  check_root
  backup_sshd_config
  detect_ssh_service
  update_sshd_config
  validate_sshd_config
  restart_ssh_service
  verify_ssh_session
  
  log ""
  log "=== Complete ==="
  log "Password authentication has been disabled."
  log "Only SSH key-based authentication is now allowed."
  log ""
  log "IMPORTANT: Keep your current SSH session open until you verify"
  log "that you can connect with your SSH key in a new terminal."
}

main "$@"
