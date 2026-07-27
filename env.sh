#!/usr/bin/env bash
# ============================================================
# Shared Configuration
#
# Paths default to $HOME-based locations. Override by setting
# environment variables before running nwctl, or edit this file.
# ============================================================

# Runtime profiles and Docker images. AUTOWARE_IMAGE remains an escape hatch
# for private registries or pinned release/digest deployments.
NWCTL_PROFILE="${NWCTL_PROFILE:-auto}"
AUTOWARE_CPU_IMAGE="${AUTOWARE_CPU_IMAGE:-ghcr.io/autowarefoundation/autoware:universe-devel-humble}"
AUTOWARE_NVIDIA_IMAGE="${AUTOWARE_NVIDIA_IMAGE:-ghcr.io/autowarefoundation/autoware:universe-devel-cuda}"
AUTOWARE_IMAGE="${AUTOWARE_IMAGE:-}"

# Container isolation settings. Host networking is the default because ROS 2
# discovery depends on it in the current deployment, but operators can override
# these without editing the script.
NWCTL_NETWORK_MODE="${NWCTL_NETWORK_MODE:-host}"
NWCTL_IPC_MODE="${NWCTL_IPC_MODE:-host}"
NWCTL_NVIDIA_RUNTIME="${NWCTL_NVIDIA_RUNTIME:-nvidia}"
# The Autoware image requires a 10 MB DDS socket receive buffer by default.
# Containers cannot reliably raise the host sysctl when using host networking,
# so accept the host's available buffer while retaining loopback discovery.
NWCTL_CYCLONEDDS_URI="${NWCTL_CYCLONEDDS_URI:-${CYCLONEDDS_URI:-<CycloneDDS><Domain Id=\"any\"><Discovery><ParticipantIndex>none</ParticipantIndex></Discovery><General><Interfaces><NetworkInterface name=\"lo\" multicast=\"true\"/></Interfaces><AllowMulticast>true</AllowMulticast><MaxMessageSize>65500B</MaxMessageSize></General><Internal><SocketReceiveBufferSize min=\"default\"/><Watermarks><WhcHigh>500kB</WhcHigh></Watermarks></Internal></Domain></CycloneDDS>}}"

# Resolve auto/cpu/nvidia into NWCTL_ACTIVE_PROFILE and AUTOWARE_IMAGE.
# An explicit AUTOWARE_IMAGE overrides only the image, not the runtime profile.
nwctl_resolve_profile() {
    local requested="${1:-${NWCTL_PROFILE}}"
    case "${requested}" in
        auto)
            if command -v docker >/dev/null 2>&1 &&
               docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"' &&
               command -v nvidia-smi >/dev/null 2>&1 &&
               nvidia-smi >/dev/null 2>&1; then
                NWCTL_ACTIVE_PROFILE=nvidia
            else
                NWCTL_ACTIVE_PROFILE=cpu
            fi
            ;;
        cpu|nvidia)
            NWCTL_ACTIVE_PROFILE="${requested}"
            ;;
        *)
            echo "Invalid nwctl profile '${requested}' (expected auto, cpu, or nvidia)" >&2
            return 1
            ;;
    esac

    if [ -z "${AUTOWARE_IMAGE}" ]; then
        if [ "${NWCTL_ACTIVE_PROFILE}" = "nvidia" ]; then
            AUTOWARE_IMAGE="${AUTOWARE_NVIDIA_IMAGE}"
        else
            AUTOWARE_IMAGE="${AUTOWARE_CPU_IMAGE}"
        fi
    fi
    export NWCTL_ACTIVE_PROFILE AUTOWARE_IMAGE
}

# Shared data paths (read-only)
SHARED_MAP_PATH="${SHARED_MAP_PATH:-${HOME}/autoware_map}"
SHARED_DATA_PATH="${SHARED_DATA_PATH:-${HOME}/autoware_data}"
SHARED_ROSBAG_PATH="${SHARED_ROSBAG_PATH:-${HOME}/autoware_map/sample-rosbag}"
SHARED_SRC_PATH="${SHARED_SRC_PATH:-${HOME}/autoware/src}"

# Runtime state. A system installation creates /var/lib/nwctl for members of
# the docker group. Source-tree usage falls back to the invoking user's XDG
# state directory so runtime files never dirty the repository.
if [ -z "${NWCTL_STATE_DIR:-}" ]; then
    if [ -d /var/lib/nwctl ] && [ -w /var/lib/nwctl ]; then
        NWCTL_STATE_DIR=/var/lib/nwctl
    else
        NWCTL_STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/nwctl"
    fi
fi

# User workspaces root (each registered name gets isolated build/install/log).
USER_WORKSPACES_ROOT="${USER_WORKSPACES_ROOT:-${NWCTL_STATE_DIR}/workspaces}"

# User registry file. Override for testing or custom deployments.
USER_REGISTRY="${USER_REGISTRY:-${NWCTL_STATE_DIR}/users.conf}"

# Default vehicle and sensor model
VEHICLE_MODEL="${VEHICLE_MODEL:-sample_vehicle}"
SENSOR_MODEL="${SENSOR_MODEL:-sample_sensor_kit}"

# Default map name
DEFAULT_MAP_NAME="${DEFAULT_MAP_NAME:-sample-map-rosbag}"
