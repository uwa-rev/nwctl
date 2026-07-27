#!/usr/bin/env bash
# ============================================================
# nwctl uninstaller - Removes the symlink from /usr/local/bin
# Usage: sudo bash uninstall.sh
# ============================================================
set -euo pipefail

DESTDIR="${DESTDIR:-}"
INSTALL_PATH="${DESTDIR}/usr/local/bin/nwctl"
INSTALL_ROOT="${DESTDIR}${NWCTL_INSTALL_ROOT:-/opt/nwctl}"
BASH_COMPLETION_PATH="${DESTDIR}${BASH_COMPLETION_DIR:-/usr/share/bash-completion/completions}/nwctl"
ZSH_COMPLETION_PATH="${DESTDIR}${ZSH_COMPLETION_DIR:-/usr/local/share/zsh/site-functions}/_nwctl"

if [ "$(id -u)" -ne 0 ] && [ -z "${DESTDIR}" ]; then
    echo "Please run with sudo: sudo bash $0"
    exit 1
fi

if [ -L "${INSTALL_PATH}" ] || [ -f "${INSTALL_PATH}" ]; then
    rm -f "${INSTALL_PATH}"
    rm -f "${BASH_COMPLETION_PATH}" "${ZSH_COMPLETION_PATH}"
    rm -rf "${INSTALL_ROOT}"
    echo "nwctl program and completions uninstalled"
    echo "Runtime data was preserved."
else
    echo "nwctl is not installed at ${INSTALL_PATH}"
fi
