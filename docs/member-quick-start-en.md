# NWCTL v0.2.2 Member Quick Start

NWCTL (Nuway Autoware Command Toolkit) is a command-line toolkit for managing
Autoware development, simulation, and ROSbag containers.

## 1. Check the Environment

```bash
nwctl version
export DISPLAY=:0   # Run this only if DISPLAY is empty
nwctl check-env
nwctl list
```

- `version` shows the installed NWCTL version.
- `check-env` checks Docker, the display, images, maps, and ROSbag data.
- `list` shows registered targets and their `ROS_DOMAIN_ID`.

Press `Tab` after `nwctl` or a target name to use command completion. Open a
new terminal once after installation if completion is not active.

## 2. Prepare Your Source Code

Each member should use an independent Autoware source directory and feature
branch.

```bash
cd ~
git clone https://github.com/autowarefoundation/autoware.git my_autoware
cd my_autoware
vcs import src < repositories/autoware.repos

cd src/universe/autoware_universe
git switch -c feature/<your-name>-<topic>
```

Ask an administrator to register the source directory once:

```bash
sudo nwctl register <target-name> \
  --src /home/<linux-user>/my_autoware/src
```

Example:

```bash
sudo nwctl register alice-cpu \
  --src /home/alice/my_autoware/src
```

Use separate targets for CPU and NVIDIA builds, such as `alice-cpu` and
`alice-gpu`. Do not share one target's build cache between the two profiles.

## 3. Enter the Development Container

Use automatic profile selection:

```bash
nwctl <target-name> shell
```

Force CPU mode on a no-GPU computer:

```bash
nwctl <target-name> shell --profile cpu
```

Force the NVIDIA environment:

```bash
nwctl <target-name> shell --profile nvidia
```

The default `auto` profile selects CPU or NVIDIA based on the host.

## 4. Build Your Code

Run the following commands inside the container:

```bash
cd /workspace

# Recommended daily workflow: build only the package you changed
colcon build --packages-select <package-name> --symlink-install

# Load the new build
source /workspace/install/setup.bash
```

Type `exit` to leave the development container. Build results are preserved
for that target.

## 5. Run the Planning Demo

```bash
nwctl <target-name> planning-sim
```

CPU mode:

```bash
nwctl <target-name> planning-sim --profile cpu
```

In RViz:

1. Select **2D Pose Estimate** and set the initial pose.
2. Select **2D Goal Pose** and set the destination.
3. Start driving from **AutowareStatePanel**.

Press `Ctrl+C` in the terminal to stop the demo.

## 6. Replay the Sample ROSbag

Recommended host paths:

```text
Map:    ~/autoware_map/sample-map-rosbag
ROSbag: ~/autoware_rosbag/sample-rosbag
```

The ROSbag directory must directly contain `metadata.yaml` and its `.db3` or
`.mcap` data files.

The new ROSbag path is the default from v0.2.2. On v0.2.1, set it in the
terminal before running the short command:

```bash
export SHARED_ROSBAG_PATH="$HOME/autoware_rosbag/sample-rosbag"
```

Start replay:

```bash
nwctl <target-name> rosbag-replay --profile cpu
```

To select another ROSbag directory:

```bash
nwctl <target-name> rosbag-replay \
  --profile cpu \
  --rosbag-path /absolute/path/to/sample-rosbag \
  --rate 1.0
```

If `/absolute/path/to/bags` is a parent directory containing multiple bags,
select one of its subdirectories with `--bag`:

```bash
nwctl <target-name> rosbag-replay \
  --profile cpu \
  --rosbag-path /absolute/path/to/bags \
  --bag run-001 \
  --rate 1.0
```

Do not use `--bag` when `--rosbag-path` already points to the directory that
contains `metadata.yaml`.

## 7. Daily Workflow

```text
Edit code → enter the NWCTL shell → build → test → commit → push the feature branch
```

Before a vehicle test, confirm:

- the target name;
- the Git commit;
- the assigned `ROS_DOMAIN_ID`;
- the approved test window.

Stop a running demo with `Ctrl+C`. Autoware may need several seconds to stop.
If it remains active after the shutdown messages, press `Ctrl+C` once more and
confirm that `nwctl list` shows `stopped`.

## 8. Common Commands

```bash
nwctl version
nwctl list
nwctl check-env
nwctl <target-name> shell
nwctl <target-name> planning-sim
nwctl <target-name> rosbag-replay
nwctl <target-name> clean
```

If `clean` reports permission errors from old container-generated files, ask
an administrator to run the following command once:

```bash
sudo nwctl <target-name> clean
```
