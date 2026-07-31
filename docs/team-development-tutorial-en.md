# NWCTL Multi-Member Autoware Development and Vehicle-Test Tutorial

This tutorial is for teams using the same host for Autoware development,
simulation, ROSbag replay, and vehicle validation.

## 1. Core Principles

- Use an independent Linux account for each member when stronger accountability
  is required. A trusted small team may use a shared `dev` vehicle-test account.
- Keep every source version, branch, build, and test result traceable,
  regardless of the Linux account model.
- Use a separate NWCTL target for each source version. Never reuse build/install
  artifacts across different architectures or substantially different versions.
- Never use a vehicle DOMAIN for routine development.
- Run only reviewed, traceable, and reversible commits or build artifacts on a
  vehicle DOMAIN.
- `ROS_DOMAIN_ID` separates DDS discovery; it does not provide authentication or
  authorization.
- Membership in the `docker` group is approximately equivalent to host root
  access. It is not a security boundary for untrusted members.

DOMAIN allocation:

| Range | Purpose | Allocation |
|---|---|---|
| 0–9 | Vehicle/production | Explicit administrator assignment |
| 10–199 | Personal development, Planning, ROSbag | Automatically assigned at registration |
| 200–232 | Team integration testing | Explicit administrator assignment |

Record the IDs used by the deployment, for example:

```text
Vehicle DOMAIN_ID=5
Integration DOMAIN_ID=200
```

## 2. Administrator: Prepare Linux Accounts

### 2.1 Independent Accounts (Recommended)

Create an account for each member:

```bash
sudo adduser alice
sudo adduser bob
```

Each member manages their own source code, SSH keys, and Git credentials. Do not
share one Linux account among multiple members.

Grant only the hardware groups each member needs:

```bash
# Serial devices, USB-CAN, and GNSS
sudo usermod -aG dialout alice

# V4L2 cameras
sudo usermod -aG video alice

# USB/GPIO devices when required by host rules
sudo usermod -aG plugdev alice
```

The member must log out and log back in before new group membership takes
effect.

Independent accounts make shell activity, file ownership, SSH keys, and Git
credentials attributable to an individual.

### 2.2 Shared `dev` Account (Trusted Teams)

A vehicle host used only by trusted internal members in scheduled test windows
may keep one shared `dev` Linux account. The administrator creates one vehicle
target:

```bash
sudo nwctl register vehicle_dev \
  --src /home/dev/autoware-vehicle-test/src

sudo nwctl set-domain vehicle_dev \
  --domain-id 5 \
  --production
```

When the `dev` account belongs to the `docker` group, members can start this
registered target without `sudo`:

```bash
nwctl vehicle_dev shell --profile cpu
```

In v0.2.2, only `register`, `update`, `set-domain`, and `unregister` require
administrator privileges. Starting an already registered container does not.

Limitations of a shared account:

- all members have the same host and Docker privileges;
- Git credentials and shell history should not be shared—prefer individual SSH
  identities or audited bastion access;
- only one vehicle-test container may use the vehicle DOMAIN at a time;
- stop the previous test, record its Git SHA, and handle old build/install
  artifacts before changing branches;
- use a scheduling lock or written test record to prevent concurrent code
  changes.

Keep only the branch currently under test in the shared vehicle workspace:

```bash
cd /home/dev/autoware-vehicle-test
git fetch origin
git switch feature/alice-lane-change
git reset --hard origin/feature/alice-lane-change
git rev-parse HEAD
```

Use `git reset --hard` only after confirming that the shared test directory has
no uncommitted work. Personal work must be pushed to a remote feature branch
first.

When branches differ substantially, clean the target or use branch-specific
build directories:

```bash
nwctl vehicle_dev clean
```

Confirm that the vehicle-test container is stopped before deleting its build
cache.

## 3. Member: Prepare Source Code

Run as the member:

```bash
cd /home/alice
git clone https://github.com/autowarefoundation/autoware.git autoware-main
cd autoware-main
vcs import src < repositories/autoware.repos
```

Use separate directories for substantially different versions:

```text
/home/alice/autoware-2025.02/src
/home/alice/autoware-main/src
/home/alice/autoware-feature-lane-change/src
```

## 4. Administrator: Create NWCTL Workspaces

In NWCTL v0.2.2, only an administrator can modify the system registry:

```bash
sudo nwctl register alice_main \
  --src /home/alice/autoware-main/src

sudo nwctl register bob_main \
  --src /home/bob/autoware-main/src
```

A development DOMAIN is selected automatically from 10–199. Check the result:

```bash
nwctl list
```

Example mappings:

```text
/home/alice/autoware-main/src
  → container /workspace/src

/var/lib/nwctl/workspaces/alice_main/build
  → container /workspace/build

/var/lib/nwctl/workspaces/alice_main/install
  → container /workspace/install

/var/lib/nwctl/workspaces/alice_main/log
  → container /workspace/log
```

Register another target when the same member needs a different Autoware
version:

```bash
sudo nwctl register alice_202502 \
  --src /home/alice/autoware-2025.02/src
```

Do not repeatedly use `update` to switch between substantially different
versions. Old build/install artifacts can contaminate the new version.

Use different targets for CPU and NVIDIA builds, even when both targets point
to the same source tree:

```bash
sudo nwctl register alice_main_cpu \
  --src /home/alice/autoware-main/src

sudo nwctl register alice_main_gpu \
  --src /home/alice/autoware-main/src
```

## 5. Daily Development Workflow

### 5.1 Create a Feature Branch

```bash
cd /home/alice/autoware-main/src/universe/autoware_universe
git switch -c feature/alice-lane-change
```

### 5.2 Enter the Development Container

On a development host where members may run containers:

```bash
nwctl alice_main_cpu shell --profile cpu
```

Inside the container:

```bash
source /opt/ros/humble/setup.bash
source /opt/autoware/setup.bash

cd /workspace
colcon build \
  --packages-up-to <modified_package> \
  --symlink-install \
  --cmake-args -DCMAKE_BUILD_TYPE=Release

source /workspace/install/setup.bash
ros2 pkg prefix <modified_package>
```

The returned prefix should be under `/workspace/install`.

### 5.3 Planning and ROSbag Validation

Routine validation uses the member's development DOMAIN:

```bash
nwctl alice_main_cpu planning-sim \
  --profile cpu \
  --map-name sample-map-rosbag

nwctl alice_main_cpu rosbag-replay \
  --profile cpu \
  --map-name sample-map-rosbag
```

The default data locations in v0.2.2 are:

```text
Map:    $HOME/autoware_map/sample-map-rosbag
ROSbag: $HOME/autoware_rosbag/sample-rosbag
```

The ROSbag directory must directly contain `metadata.yaml`. If another
directory is used, specify it explicitly:

```bash
nwctl alice_main_cpu rosbag-replay \
  --profile cpu \
  --rosbag-path /absolute/path/to/sample-rosbag
```

Complete these checks before submitting the change:

- the modified package builds successfully;
- Planning or the relevant node starts correctly;
- the official or project ROSbag replays successfully;
- there is no FATAL error, traceback, or unexpected node exit;
- important input and output topics contain messages;
- the test log and Git SHA are recorded.

### 5.4 Commit and Submit

```bash
git status
git add <files>
git commit -m "feat: describe the change"
git push origin feature/alice-lane-change
```

Open a merge request to `dev` or `integration`. Do not deploy an individual
feature branch directly to a vehicle DOMAIN.

## 6. Recommended Branch and Release Flow

```text
feature/* (personal development DOMAIN)
  ↓ Merge Request + Review
dev / integration (integration DOMAIN 200–232)
  ↓ CI build, simulation, ROSbag, and interface checks
release candidate (fixed Git SHA and build artifacts)
  ↓ Test-owner approval
vehicle target (vehicle DOMAIN 0–9)
  ↓ Vehicle test and result recording
release / rollback
```

The administrator creates the integration target:

```bash
sudo nwctl register integration_humble \
  --src /opt/autoware-integration/current/src

sudo nwctl set-domain integration_humble --domain-id 200
```

## 7. Vehicle-Test Workflow

A vehicle target should point to an approved fixed deployment directory, not a
member's personal workspace:

```bash
sudo nwctl register vehicle_rc \
  --src /opt/autoware-deployments/<approved-git-sha>/src

sudo nwctl set-domain vehicle_rc \
  --domain-id 5 \
  --production
```

Before every vehicle test:

1. Confirm the vehicle DOMAIN and target name.
2. Record the Git SHA, image digest, map version, and parameter version.
3. Stop every other ROS 2 process using the same vehicle DOMAIN.
4. Confirm that the vehicle is stationary, the emergency stop works, and the
   safety operator is present.
5. Do not enable autonomous control output during the first check.
6. Inspect perception, localization, and planning data in read-only mode first.
7. Enable vehicle interfaces only through the approved procedure.
8. Restore the known stable version after the test.

Never assign a vehicle DOMAIN temporarily to a personal target or bypass
approval by changing `ROS_DOMAIN_ID` in a shell.

## 8. Docker Group Permission Model

### 8.1 Development Host

If the host is isolated from the vehicle-control network and members are
trusted developers, they may remain in the `docker` group:

```bash
sudo usermod -aG docker alice
```

This allows the member to start `nwctl ... shell`, `planning-sim`, and
`rosbag-replay` themselves. It also gives the member approximately host-root
privileges.

### 8.2 Vehicle or Security-Sensitive Host

Remove ordinary developers from the `docker` group:

```bash
sudo gpasswd -d alice docker
sudo gpasswd -d bob docker
```

After the members log out and back in, verify:

```bash
id alice
getent group docker
```

Removing the Docker group does not change ROS 2, Ethernet LiDAR, GNSS, or CAN
protocol permissions. It prevents the member from running `docker run`, so the
member also cannot start a current NWCTL container directly.

Use one of these methods on a vehicle host:

1. An administrator runs NWCTL during an approved test window.
2. Protected CI/CD runs a fixed target through a controlled runner.
3. A restricted systemd/service launcher allows only approved targets and
   modes.
4. A validated rootless container solution is used.

Do not grant an ordinary member:

```text
NOPASSWD: /usr/bin/docker *
```

That is effectively equivalent to adding the member back to the `docker`
group.

## 9. Hardware Communication and Permissions

Grant hardware access per device rather than using the Docker group as a
universal solution.

| Hardware | Host requirement | Container requirement |
|---|---|---|
| Ethernet LiDAR/radar | Routing, VLAN, firewall | Controlled host/macvlan network |
| USB/serial GNSS | `dialout`, udev rule | Explicit `/dev/ttyUSB*` mapping |
| USB-CAN | `dialout` or device udev group | Explicit device mapping |
| SocketCAN `can0` | Interface configured by administrator | Only required network capabilities |
| V4L2 camera | `video` group | Explicit `/dev/video*` mapping |
| NVIDIA GPU | Driver and runtime | NVIDIA runtime/device |

Current NWCTL primarily covers Autoware development, simulation, and ROSbag
replay. It does not yet provide a complete hardware-device allowlist.

Before vehicle deployment, define a separate hardware profile specifying:

- allowed `/dev` devices;
- allowed network interfaces and ports;
- whether `NET_RAW` or `NET_ADMIN` is required;
- read-only and read-write mounts;
- vehicle-control topic/service allowlists;
- emergency-stop and control-ownership arbitration.

Until the hardware profile is complete, an administrator should start
containers on a security-sensitive host. Do not solve device access simply by
adding developers to the Docker group.

## 10. Common Administrator Commands

```bash
# Register a development target; DOMAIN 10–199 is assigned automatically
sudo nwctl register alice_main --src /home/alice/autoware-main/src

# Move the source path within a compatible version
sudo nwctl update alice_main --src /home/alice/autoware-new/src

# Assign an integration DOMAIN
sudo nwctl set-domain integration_humble --domain-id 200

# Assign a vehicle DOMAIN with explicit acknowledgement
sudo nwctl set-domain vehicle_rc --domain-id 5 --production

# Unregister while preserving build artifacts
sudo nwctl unregister alice_main --keep-workspace

# Inspect targets, running containers, and disk usage
nwctl list
nwctl status
nwctl disk
```

## 11. Security Boundary

None of these measures alone provides vehicle security:

- changing only `ROS_DOMAIN_ID`;
- using only different Git branches;
- making only the registry root-writable;
- relying only on container names or ordinary Linux groups.

Use a combination of:

- vehicle-network VLANs and firewalls;
- DDS Security or equivalent authentication;
- control topic/service allowlists;
- controlled builds and pinned image digests;
- least-privilege runtime accounts;
- approval, logging, rollback, and vehicle-test checklists.
