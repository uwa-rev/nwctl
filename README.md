# NWCTL — Nuway Autoware Command Toolkit

Multi-user development and testing toolkit for Autoware. Multiple team members can work on the same host machine with fully isolated environments.

Member quick starts:
[English](docs/member-quick-start-en.md) |
[English / 中文](docs/member-quick-start-bilingual.md)

Team onboarding and vehicle-test workflow:
[English](docs/team-development-tutorial-en.md) |
[中文](docs/team-development-tutorial-zh.md)

## Architecture

```
Host Machine
├── ~/zhangsan_aw/           User A's git clone (source only)
│   └── src/                        User A's source code & branches
├── ~/lisi_aw/               User B's git clone (source only)
│   └── src/
├── /var/lib/nwctl/          Shared runtime state
│   ├── users.conf                  User and ROS domain registry
│   └── workspaces/<user>/          Isolated build/install/log output
├── ~/autoware_map/          Shared map data (read-only)
├── ~/autoware_data/         Shared model data (read-only)
└── /opt/nwctl/              Installed program files

Inside Docker Container
├── /workspace/                     Mounted from user's git clone (shell mode)
│   ├── src/                        User's source code
│   ├── build/                      User's build output
│   └── install/                    User's install (overlays prebuilt)
├── /opt/autoware/                  Prebuilt Autoware (shared, from image)
├── /autoware_map/                  Mounted map data (read-only)
├── /autoware_data/                 Mounted model data (read-only)
└── /rosbag_data/                   Mounted rosbag data (read-only)
```

### Isolation

| Resource | Method | Details |
|----------|--------|---------|
| ROS topics | ROS_DOMAIN_ID | Development IDs 10-199 are auto-assigned; vehicle IDs 0-9 are admin-controlled |
| Source code | Separate git clones | Each user manages their own repo & branches |
| Build artifacts | Separate mounts | `/var/lib/nwctl/workspaces/<user>/` |
| Containers | Named per user | `aw-zhangsan-shell`, `aw-lisi-rosbag-replay` |
| Map / Data | Shared read-only | Saves disk space |
| GPU | Shared | NVIDIA runtime supports multi-container |

### Two Operating Modes

| Mode | Source Mount | Setup | Use Case |
|------|-------------|-------|----------|
| **planning-sim / rosbag-replay** | None | `/opt/autoware/setup.bash` (prebuilt) | Testing, demo, validation |
| **shell** | User's workspace | `/workspace/install/setup.bash` (user-built) | Development, debugging |

## Requirements

| Item | Requirement |
|------|-------------|
| OS | Ubuntu 22.04 (x86_64 or arm64) |
| GPU | Optional; NVIDIA uses the `nvidia` profile, no-GPU hosts use `cpu` |
| Docker | >= 24.0 |
| nvidia-container-toolkit | Installed |
| RAM | >= 16GB (64GB recommended for multi-user) |

## Quick Start

### 1. Install (admin, one-time)

```bash
sudo bash install.sh
```

This installs the program under `/opt/nwctl`, creates shared state under
`/var/lib/nwctl`, and installs Bash and Zsh completion. Start a new shell after
installation, then press Tab after `nwctl`.

### 2. Pull Docker Image (admin, one-time)

```bash
# Automatically selects the CPU or NVIDIA image for this host
nwctl pull

# Explicit no-GPU image
nwctl pull --profile cpu
```

### 3. Clone Your Own Code

Each team member clones their own copy:

```bash
cd ~
git clone https://github.com/autowarefoundation/autoware.git myname_autoware
cd myname_autoware
vcs import src < repositories/autoware.repos

# Switch to your feature branch if needed
cd src/universe/autoware_universe
git checkout feature/my-algorithm
```

### 4. Register (administrator)

```bash
sudo nwctl register myname --src /home/myname/myname_autoware/src
```

Registration, source updates, removal, and DOMAIN_ID changes modify the
system-wide registry and therefore require administrator privileges. New
targets automatically receive a development DOMAIN_ID in the range 10-199.

Administrators may assign an integration ID (200-232):

```bash
sudo nwctl set-domain myname --domain-id 200
```

Vehicle/production IDs 0-9 require an explicit acknowledgement:

```bash
sudo nwctl set-domain approved_vehicle_build --domain-id 5 --production
```

`ROS_DOMAIN_ID` provides DDS discovery separation, not authentication or
authorization. Developers in the `docker` group can obtain host-equivalent
privileges and must be treated as trusted administrators; remove untrusted
developers from that group and use a controlled container service/rootless
runtime when stronger isolation is required.

### 5. Use

```bash
# Planning simulation (uses prebuilt image, no compilation needed)
nwctl myname planning-sim

# Rosbag replay (uses prebuilt image)
nwctl myname rosbag-replay

# Development shell (mounts your source code)
nwctl myname shell
```

## Runtime Profiles

`nwctl` supports two execution paths and an automatic selector:

| Profile | Image | Container acceleration |
|---------|-------|------------------------|
| `cpu` | `ghcr.io/autowarefoundation/autoware:universe-devel-humble` | llvmpipe software rendering; no NVIDIA runtime |
| `nvidia` | `ghcr.io/autowarefoundation/autoware:universe-devel-cuda` | NVIDIA container runtime |
| `auto` | Selects one of the above | NVIDIA only when both the GPU and Docker runtime are available |

`auto` is the default. Override it per invocation:

```bash
nwctl check-env shell --profile cpu
nwctl myname shell --profile cpu
nwctl myname planning-sim --profile cpu
```

Set `NWCTL_PROFILE=cpu` in the environment to make CPU mode the default for a
host or login session.

## Modes

### Planning Simulation

```bash
nwctl <username> planning-sim
```

1. Wait for rviz2 window to appear (~30 seconds)
2. Click **2D Pose Estimate** in toolbar, click and drag on map to set initial pose
3. Click **2D Goal Pose** to set destination
4. Click buttons in **AutowareStatePanel** to start autonomous driving

### Rosbag Replay

```bash
nwctl <username> rosbag-replay
# Select a bag subdirectory and playback speed:
nwctl <username> rosbag-replay --bag run-001 --rate 0.5
```

The command starts Autoware, waits for initialization, and then runs
`ros2 bag play` automatically. Use `--bag`, `--rosbag-path`, and `--rate` to
choose the recording and speed.

In the CPU profile, nwctl disables the CUDA/ML-model perception pipeline and
uses a 60-second startup delay by default. Map loading, sensor decoding,
localization, RViz, and rosbag playback remain enabled. Override the delay with
`NWCTL_ROSBAG_START_DELAY` when needed.

### Development Shell

```bash
nwctl <username> shell
```

Inside the container:

```bash
# Your workspace is already sourced

# Build only the package you modified (incremental, fast)
cd /workspace
colcon build --packages-select <package_name> --symlink-install

# Source updated workspace
source /workspace/install/setup.bash

# Test your changes - e.g. launch planning simulation
ros2 launch autoware_launch planning_simulator.launch.xml \
    map_path:=/autoware_map/sample-map-rosbag \
    vehicle_model:=sample_vehicle \
    sensor_model:=sample_sensor_kit
```

**Build a single package for testing:**
```bash
colcon build --packages-select autoware_node --symlink-install
```

**Build a package with its dependencies:**
```bash
colcon build --packages-up-to autoware_ndt_scan_matcher --symlink-install
```

**Full build (first time only, takes a while):**
```bash
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release
```

## Management Commands

```bash
nwctl list                     # List all registered users
nwctl status                   # Show running containers
nwctl disk                     # Show disk usage per user
nwctl <username> stop          # Stop user's containers
nwctl <username> clean         # Clean user's build cache
sudo nwctl update <username> --src <path>  # Update source path
sudo nwctl unregister <username> --keep-workspace
nwctl cleanup --dry-run
nwctl pull
```

## Shell Completion

Bash and Zsh completion is installed automatically by `install.sh`. For a
source checkout, enable it in the current shell with:

```bash
source completions/nwctl.bash                  # Bash
fpath=("$PWD/completions" $fpath); compinit    # Zsh
```

Completion includes commands, modes, options, registered usernames, common
playback rates, and filesystem paths.

## FAQ

### Q: rviz2 shows black screen or crashes
```bash
xhost +local:docker
echo $DISPLAY    # Should be :0 or :1
```

### Q: GPU error "could not select device driver"
```bash
docker run --rm --runtime=nvidia nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi
```
If this fails, reinstall nvidia-container-toolkit and restart Docker.

### Q: Multiple users' ROS topics interfere with each other
Administrator-created development targets receive unique IDs from 10-199.
Do not use a vehicle/production ID for normal development.

### Q: colcon build can't find dependencies
```bash
# Source the prebuilt workspace first
source /opt/autoware/setup.bash
# Then build
colcon build --packages-select <pkg> --symlink-install
```

### Q: Pointcloud map doesn't load
Check file permissions:
```bash
ls -la ~/autoware_map/sample-map-rosbag/pointcloud_map.pcd
# If permission is -rw-------, fix with:
sudo chmod 644 ~/autoware_map/sample-map-rosbag/pointcloud_map.pcd
```

### Q: Rosbag play shows no data
Make sure `ROS_DOMAIN_ID` matches. Check the startup output for your assigned ID:
```bash
export ROS_DOMAIN_ID=<your_id>
ros2 bag play /rosbag_data -r 0.2 -s sqlite3
```

### Q: Are build artifacts preserved after container exit?
Yes. Build artifacts are stored in `/var/lib/nwctl/workspaces/<user>/` for an
installed deployment and persist across container restarts and source branch
changes.

### Q: How to switch branches for testing?
Manage your code on the host machine:
```bash
cd ~/myname_autoware/src/universe/autoware_universe
git checkout feature/new-branch
# Then enter dev shell and rebuild
nwctl myname shell
```

## Command Reference

| Command | Description |
|---------|-------------|
| `sudo nwctl register <name> --src <path>` | Register a target with an automatic development DOMAIN |
| `sudo nwctl set-domain <name> --domain-id <ID> [--production]` | Assign a DOMAIN |
| `sudo nwctl update <name> --src <path>` | Update source path |
| `nwctl <name> planning-sim` | Planning simulation |
| `nwctl <name> rosbag-replay` | Rosbag replay |
| `nwctl <name> shell` | Development shell |
| `nwctl <name> stop` | Stop containers |
| `nwctl <name> clean` | Clean build cache |
| `nwctl list` | List all users |
| `nwctl status` | Show running containers |
| `nwctl disk` | Show disk usage |
| `nwctl cleanup [--dry-run]` | Clean or preview orphan resources |
| `nwctl pull` | Pull the configured image |
| `nwctl completion <bash\|zsh>` | Print completion setup |
| `nwctl -h` | Show help |
