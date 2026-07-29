#!/usr/bin/env bash
# ============================================================
# nwctl installer - Installs files, shared state, and shell completions
# Usage: sudo bash install.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DESTDIR="${DESTDIR:-}"
INSTALL_ROOT="${DESTDIR}${NWCTL_INSTALL_ROOT:-/opt/nwctl}"
STATE_DIR="${DESTDIR}${NWCTL_STATE_DIR:-/var/lib/nwctl}"
NWCTL_BIN="${INSTALL_ROOT}/nwctl"
INSTALL_PATH="${DESTDIR}/usr/local/bin/nwctl"
BASH_COMPLETION_DIR="${DESTDIR}${BASH_COMPLETION_DIR:-/usr/share/bash-completion/completions}"
ZSH_COMPLETION_DIR="${DESTDIR}${ZSH_COMPLETION_DIR:-/usr/local/share/zsh/site-functions}"

if [ "$(id -u)" -ne 0 ] && [ -z "${DESTDIR}" ]; then
    echo "Please run with sudo: sudo bash $0"
    exit 1
fi

if [ ! -f "${SCRIPT_DIR}/nwctl" ]; then
    echo "Error: nwctl not found at ${SCRIPT_DIR}/nwctl"
    exit 1
fi

install -d -m 0755 "${INSTALL_ROOT}" "${INSTALL_ROOT}/completions" "$(dirname "${INSTALL_PATH}")"
for file in nwctl env.sh check-env.sh fix-display.sh planning-sim.sh \
            rosbag-replay.sh dev-shell.sh test-manual.sh; do
    install -m 0755 "${SCRIPT_DIR}/${file}" "${INSTALL_ROOT}/${file}"
done
install -m 0644 "${SCRIPT_DIR}/completions/nwctl.bash" "${INSTALL_ROOT}/completions/nwctl.bash"
install -m 0644 "${SCRIPT_DIR}/completions/_nwctl" "${INSTALL_ROOT}/completions/_nwctl"

# Registry mutations are root-only. The docker group may write isolated build
# artifacts, but cannot accidentally reassign a vehicle/production DOMAIN_ID.
STATE_OWNER=root
STATE_GROUP=docker
REGISTRY_OWNER=root
REGISTRY_GROUP=root
if [ "$(id -u)" -ne 0 ]; then
    STATE_OWNER="$(id -u)"
    STATE_GROUP="$(id -g)"
    REGISTRY_OWNER="${STATE_OWNER}"
    REGISTRY_GROUP="${STATE_GROUP}"
else
    getent group "${STATE_GROUP}" >/dev/null || STATE_GROUP="${SUDO_GID:-$(id -g)}"
fi
install -d -m 0755 -o "${REGISTRY_OWNER}" -g "${REGISTRY_GROUP}" "${STATE_DIR}"
install -d -m 2775 -o "${STATE_OWNER}" -g "${STATE_GROUP}" "${STATE_DIR}/workspaces"
touch "${STATE_DIR}/users.conf"
chown "${REGISTRY_OWNER}:${REGISTRY_GROUP}" "${STATE_DIR}/users.conf"
chmod 0644 "${STATE_DIR}/users.conf"
touch "${STATE_DIR}/users.conf.lock"
chown "${REGISTRY_OWNER}:${REGISTRY_GROUP}" "${STATE_DIR}/users.conf.lock"
chmod 0600 "${STATE_DIR}/users.conf.lock"

# Preserve registrations from a source-tree installation on first install.
if [ ! -s "${STATE_DIR}/users.conf" ] && [ -s "${SCRIPT_DIR}/users.conf" ]; then
    cp "${SCRIPT_DIR}/users.conf" "${STATE_DIR}/users.conf"
    chown "${REGISTRY_OWNER}:${REGISTRY_GROUP}" "${STATE_DIR}/users.conf"
    chmod 0644 "${STATE_DIR}/users.conf"
fi

ln -sfn "${NWCTL_BIN}" "${INSTALL_PATH}"

install -d -m 0755 "${BASH_COMPLETION_DIR}" "${ZSH_COMPLETION_DIR}"
ln -sfn "${INSTALL_ROOT}/completions/nwctl.bash" "${BASH_COMPLETION_DIR}/nwctl"
ln -sfn "${INSTALL_ROOT}/completions/_nwctl" "${ZSH_COMPLETION_DIR}/_nwctl"

echo "nwctl installed successfully!"
echo ""
echo "  Command:    ${INSTALL_PATH} -> ${NWCTL_BIN}"
echo "  State:      ${STATE_DIR}"
echo "  Completion: Bash and Zsh (start a new shell to activate)"
echo ""
echo "  You can now use 'nwctl' from anywhere:"
echo "    nwctl --help"
echo "    sudo nwctl register <username> --src <path>"
echo "    nwctl <username> planning-sim"
echo ""
