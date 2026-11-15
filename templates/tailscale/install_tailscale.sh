#!/bin/sh
# Installs Tailscale from Tailscale's signed package repository.
#
# The upstream `curl https://tailscale.com/install.sh | sh` installer is not
# used here because it runs whatever the remote script decides on first boot.
# This installs the distribution package from Tailscale's signed repository
# instead, optionally pinned to TAILSCALE_VERSION, and fails loudly if the
# distribution is not supported so the operator does not have to diagnose a
# silent five minute SSH timeout later.
set -eu

TAILSCALE_VERSION="{{ tailscale_version }}"

log() { echo "tailscale-install: $*" | tee -a /var/log/hetzner-k3s.log; }
fail() { log "ERROR: $*"; exit 1; }

[ -f /etc/os-release ] || fail "cannot detect the distribution: /etc/os-release is missing"
. /etc/os-release

install_deb() {
  codename="${VERSION_CODENAME:-}"
  [ -n "$codename" ] || fail "cannot determine the ${ID} release codename"

  curl -fsSL "https://pkgs.tailscale.com/stable/${ID}/${codename}.noarmor.gpg" \
    -o /usr/share/keyrings/tailscale-archive-keyring.gpg ||
    fail "could not download the Tailscale signing key for ${ID} ${codename}"
  curl -fsSL "https://pkgs.tailscale.com/stable/${ID}/${codename}.tailscale-keyring.list" \
    -o /etc/apt/sources.list.d/tailscale.list ||
    fail "could not download the Tailscale apt repository for ${ID} ${codename}"

  apt-get update -qq || fail "apt-get update failed"

  if [ -n "$TAILSCALE_VERSION" ]; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y "tailscale=${TAILSCALE_VERSION}" ||
      fail "tailscale ${TAILSCALE_VERSION} is not available for ${ID} ${codename}"
  else
    DEBIAN_FRONTEND=noninteractive apt-get install -y tailscale ||
      fail "apt-get install tailscale failed"
  fi

  systemctl enable --now tailscaled
}

install_rpm() {
  major="${VERSION_ID%%.*}"
  case "$ID" in
    centos) family="centos" ;;
    rhel|rocky|almalinux) family="rhel" ;;
    fedora) family="fedora" ;;
    *) fail "unsupported distribution for the Tailscale package repository: ${ID}" ;;
  esac

  command -v dnf >/dev/null 2>&1 || fail "dnf is not available on ${ID}"
  dnf install -y 'dnf-command(config-manager)' >/dev/null 2>&1 || true
  dnf config-manager --add-repo "https://pkgs.tailscale.com/stable/${family}/${major}/tailscale.repo" ||
    fail "could not add the Tailscale repository for ${family} ${major}"

  if [ -n "$TAILSCALE_VERSION" ]; then
    dnf install -y "tailscale-${TAILSCALE_VERSION}" ||
      fail "tailscale ${TAILSCALE_VERSION} is not available for ${family} ${major}"
  else
    dnf install -y tailscale || fail "dnf install tailscale failed"
  fi

  systemctl enable --now tailscaled
}

if command -v apt-get >/dev/null 2>&1; then
  install_deb
elif command -v dnf >/dev/null 2>&1; then
  install_rpm
else
  fail "no supported package manager found. Tailscale auto-install supports Debian/Ubuntu and RHEL-family images; use a snapshot with Tailscale preinstalled instead"
fi

command -v tailscale >/dev/null 2>&1 || fail "the package installed but the tailscale binary is missing"
log "installed $(tailscale version | head -n 1)"
