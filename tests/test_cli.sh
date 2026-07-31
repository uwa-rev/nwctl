#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEST_ROOT}"' EXIT

STATE_DIR="${TEST_ROOT}/state"
SOURCE_ROOT="${TEST_ROOT}/autoware"
FAKE_BIN="${TEST_ROOT}/bin"
DOCKER_LOG="${TEST_ROOT}/docker.log"
ENTRY_COPY="${TEST_ROOT}/entry.sh"
mkdir -p "${STATE_DIR}" "${SOURCE_ROOT}/src" "${FAKE_BIN}"
touch "${STATE_DIR}/users.conf"

cat > "${FAKE_BIN}/docker" <<'FAKE_DOCKER'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${DOCKER_LOG}"
case "${1:-} ${2:-}" in
    "ps -q")
        printf '%s\n' container-one container-two
        ;;
    "image inspect")
        exit 0
        ;;
    "inspect "*)
        printf '%s\n' true
        ;;
    "stop "*|"rm "*)
        ;;
    "run "*)
        for arg in "$@"; do
            case "${arg}" in
                *:/entry.sh:ro)
                    cp "${arg%:/entry.sh:ro}" "${ENTRY_COPY}"
                ;;
            esac
        done
        if [ -n "${FAKE_DOCKER_RUN_SLEEP:-}" ]; then
            : > "${DOCKER_RUN_READY}"
            sleep "${FAKE_DOCKER_RUN_SLEEP}"
        fi
        ;;
esac
FAKE_DOCKER
chmod +x "${FAKE_BIN}/docker"

export NWCTL_STATE_DIR="${STATE_DIR}"
export SHARED_MAP_PATH="${TEST_ROOT}/maps"
export SHARED_ROSBAG_PATH="${TEST_ROOT}/bags"
export SHARED_DATA_PATH="${TEST_ROOT}/data"
export DISPLAY=:99
export PATH="${FAKE_BIN}:${ROOT}:${PATH}"
export DOCKER_LOG ENTRY_COPY
mkdir -p "${SHARED_MAP_PATH}/sample-map-rosbag" \
         "${SHARED_ROSBAG_PATH}/run-a" "${SHARED_DATA_PATH}"
cat > "${SHARED_ROSBAG_PATH}/run-a/metadata.yaml" <<'EOF'
rosbag2_bagfile_information:
  storage_identifier: sqlite3
EOF

run_nwctl() {
    bash "${ROOT}/nwctl" "$@"
}

assert_contains() {
    local file="$1" expected="$2"
    if ! grep -Fq -- "${expected}" "${file}"; then
        echo "FAIL: expected '${expected}' in ${file}" >&2
        sed -n '1,160p' "${file}" >&2
        exit 1
    fi
}

run_nwctl version | grep -q 'nwctl v0.2.2'
run_nwctl help | grep -F 'Nuway Autoware Command Toolkit' >/dev/null
if NWCTL_STATE_DIR=/var/lib/nwctl run_nwctl register blocked \
    --src "${SOURCE_ROOT}/src" >"${TEST_ROOT}/admin-denied.log" 2>&1; then
    echo "FAIL: unprivileged system registry mutation was accepted" >&2
    exit 1
fi
assert_contains "${TEST_ROOT}/admin-denied.log" "Administrator privileges are required"
run_nwctl register alice --src "${SOURCE_ROOT}/src" >/dev/null
run_nwctl _complete users | grep -qx alice
run_nwctl register bob --src "${SOURCE_ROOT}/src" >/dev/null
run_nwctl set-domain bob --domain-id 42 >/dev/null
grep -q '^bob:42:' "${STATE_DIR}/users.conf"
if run_nwctl set-domain bob --domain-id 5 >/dev/null 2>&1; then
    echo "FAIL: production DOMAIN_ID was accepted without --production" >&2
    exit 1
fi
run_nwctl set-domain bob --domain-id 5 --production >/dev/null
grep -q '^bob:5:' "${STATE_DIR}/users.conf"

if run_nwctl alice shell --rate 0 >/dev/null 2>&1; then
    echo "FAIL: zero playback rate was accepted" >&2
    exit 1
fi

if run_nwctl alice rosbag-replay --bag ../../ >/dev/null 2>&1; then
    echo "FAIL: rosbag path traversal was accepted" >&2
    exit 1
fi
mkdir -p "${SHARED_ROSBAG_PATH}/missing-metadata"
if run_nwctl alice rosbag-replay --bag missing-metadata >/dev/null 2>&1; then
    echo "FAIL: rosbag directory without metadata.yaml was accepted" >&2
    exit 1
fi

: > "${DOCKER_LOG}"
run_nwctl alice stop >/dev/null
assert_contains "${DOCKER_LOG}" "stop container-one container-two"

: > "${DOCKER_LOG}"
run_nwctl alice shell >/dev/null
assert_contains "${DOCKER_LOG}" "ghcr.io/autowarefoundation/autoware:universe-devel-humble"
assert_contains "${DOCKER_LOG}" "LIBGL_ALWAYS_SOFTWARE=1"
assert_contains "${DOCKER_LOG}" "${SOURCE_ROOT}:/workspace"
assert_contains "${DOCKER_LOG}" "${STATE_DIR}/workspaces/alice/build:/workspace/build"
assert_contains "${DOCKER_LOG}" "${STATE_DIR}/workspaces/alice/install:/workspace/install"
assert_contains "${DOCKER_LOG}" "${STATE_DIR}/workspaces/alice/log:/workspace/log"
assert_contains "${DOCKER_LOG}" "--cap-add=NET_ADMIN"
assert_contains "${DOCKER_LOG}" "CYCLONEDDS_URI="
if grep -Fq -- '--runtime=nvidia' "${DOCKER_LOG}"; then
    echo "FAIL: CPU profile unexpectedly enabled the NVIDIA runtime" >&2
    exit 1
fi

: > "${DOCKER_LOG}"
run_nwctl alice shell --profile nvidia >/dev/null
assert_contains "${DOCKER_LOG}" "ghcr.io/autowarefoundation/autoware:universe-devel-cuda"
assert_contains "${DOCKER_LOG}" "--runtime=nvidia"
assert_contains "${DOCKER_LOG}" "NVIDIA_DRIVER_CAPABILITIES=all"

: > "${DOCKER_LOG}"
NWCTL_ROSBAG_START_DELAY=0 run_nwctl alice rosbag-replay --bag run-a --rate 2.0 >/dev/null
assert_contains "${DOCKER_LOG}" "${SHARED_ROSBAG_PATH}/run-a:/rosbag_data:ro"
assert_contains "${ENTRY_COPY}" "ros2 bag play /rosbag_data -r 2.0 -s sqlite3"
assert_contains "${ENTRY_COPY}" "perception:=false"
assert_contains "${ENTRY_COPY}" "launch_perception:=false"
assert_contains "${ENTRY_COPY}" "use_cuda_ground_segmentation:=false"
assert_contains "${ENTRY_COPY}" "cuda_ground_segmentation_node_param_path:=/opt/autoware/autoware_ground_segmentation/share/autoware_ground_segmentation/config/scan_ground_filter.param.yaml"
assert_contains "${ENTRY_COPY}" "kill -0 \"\${launch_pid}\""

# TERM/SSH-style interruption stops and removes the managed container.
: > "${DOCKER_LOG}"
DOCKER_RUN_READY="${TEST_ROOT}/docker-run.ready"
export DOCKER_RUN_READY
(
    export FAKE_DOCKER_RUN_SLEEP=1
    exec bash "${ROOT}/nwctl" alice shell
) >/dev/null 2>&1 &
nwctl_pid=$!
for _ in $(seq 1 50); do
    [ -f "${DOCKER_RUN_READY}" ] && break
    sleep 0.02
done
[ -f "${DOCKER_RUN_READY}" ] || {
    echo "FAIL: fake docker run did not start" >&2
    exit 1
}
kill -TERM "${nwctl_pid}"
wait "${nwctl_pid}" 2>/dev/null || true
assert_contains "${DOCKER_LOG}" "stop -t 10 aw-alice-shell"
assert_contains "${DOCKER_LOG}" "rm -f aw-alice-shell"

# Bash completion includes dynamic users, modes, and command options.
# shellcheck source=../completions/nwctl.bash
source "${ROOT}/completions/nwctl.bash"
COMP_WORDS=(nwctl al); COMP_CWORD=1; _nwctl
[[ " ${COMPREPLY[*]} " == *" alice "* ]]
COMP_WORDS=(nwctl alice r); COMP_CWORD=2; _nwctl
[[ " ${COMPREPLY[*]} " == *" rosbag-replay "* ]]
COMP_WORDS=(nwctl register alice --); COMP_CWORD=3; _nwctl
[[ " ${COMPREPLY[*]} " != *" --domain-id "* ]]
COMP_WORDS=(nwctl set-domain alice --); COMP_CWORD=3; _nwctl
[[ " ${COMPREPLY[*]} " == *" --production "* ]]
COMP_WORDS=(nwctl alice shell --profile c); COMP_CWORD=4; _nwctl
[[ " ${COMPREPLY[*]} " == *" cpu "* ]]

# Staged installs preserve root-only registry modes (ownership is root when the
# real installer runs under sudo; DESTDIR tests run as the current user).
STAGE_ROOT="${TEST_ROOT}/stage"
env -u NWCTL_STATE_DIR DESTDIR="${STAGE_ROOT}" bash "${ROOT}/install.sh" >/dev/null
[[ "$(stat -c %a "${STAGE_ROOT}/var/lib/nwctl/users.conf")" == 644 ]]
[[ "$(stat -c %a "${STAGE_ROOT}/var/lib/nwctl/users.conf.lock")" == 600 ]]
[[ "$(stat -c %a "${STAGE_ROOT}/var/lib/nwctl")" == 755 ]]
[[ "$(stat -c %a "${STAGE_ROOT}/var/lib/nwctl/workspaces")" == 2775 ]]

echo "CLI behavior tests: PASS"
