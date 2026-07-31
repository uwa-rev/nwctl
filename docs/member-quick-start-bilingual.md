# NWCTL v0.2.2 Member Quick Start / 成员快速使用教程

NWCTL (Nuway Autoware Command Toolkit) manages Autoware development,
simulation, and ROSbag containers.

NWCTL（Nuway Autoware Command Toolkit）用于管理 Autoware 开发、仿真和
ROSbag 容器。本文只介绍团队成员日常使用所需的命令。

## 1. Check NWCTL / 检查 NWCTL

```bash
nwctl version
export DISPLAY=:0   # Only if DISPLAY is empty / 仅在 DISPLAY 为空时执行
nwctl check-env
nwctl list
```

- `version` shows the installed version.
  `version` 显示已安装版本。
- `check-env` checks Docker, display, image, map, and ROSbag requirements.
  `check-env` 检查 Docker、显示、镜像、地图和 ROSbag 环境。
- `list` shows registered targets and their `ROS_DOMAIN_ID`.
  `list` 显示已注册的 target 及其 `ROS_DOMAIN_ID`。

Press `Tab` after `nwctl` or a target name to use command completion. Open a
new terminal once after installation if completion is not active.

在 `nwctl` 或 target 名称后按 `Tab` 可以自动补全。如果安装后补全尚未生效，
重新打开一次终端。

## 2. Prepare Your Code / 准备个人代码

Each member keeps an independent Autoware source directory and feature branch.

每位成员使用独立的 Autoware 源码目录和 feature 分支。

```bash
cd ~
git clone https://github.com/autowarefoundation/autoware.git my_autoware
cd my_autoware
vcs import src < repositories/autoware.repos

cd src/universe/autoware_universe
git switch -c feature/<your-name>-<topic>
```

Ask an administrator to register the source directory once:

请管理员对源码目录执行一次注册：

```bash
sudo nwctl register <target-name> --src /home/<linux-user>/my_autoware/src
```

Example / 示例：

```bash
sudo nwctl register alice --src /home/alice/my_autoware/src
```

## 3. Enter the Development Container / 进入开发容器

```bash
nwctl <target-name> shell
```

For a CPU-only computer:

无 GPU 电脑使用：

```bash
nwctl <target-name> shell --profile cpu
```

The default `auto` profile selects CPU or NVIDIA automatically.

默认的 `auto` profile 会自动选择 CPU 或 NVIDIA 环境。

Use separate targets for CPU and NVIDIA builds, for example `alice-cpu` and
`alice-gpu`. Do not reuse one target's build cache across the two profiles.

CPU 与 NVIDIA 编译应使用不同 target，例如 `alice-cpu` 和 `alice-gpu`，
不要让两种 profile 共用同一份编译缓存。

## 4. Build Your Code / 编译代码

Run these commands inside the container:

以下命令在容器内执行：

```bash
cd /workspace

# Build one modified package / 编译一个修改过的包
colcon build --packages-select <package-name> --symlink-install

# Load the new build / 加载新的编译结果
source /workspace/install/setup.bash
```

Type `exit` to leave the container. Build results are preserved for the target.

输入 `exit` 退出容器；该 target 的编译结果会保留。

## 5. Run Planning Demo / 运行 Planning Demo

```bash
nwctl <target-name> planning-sim
```

CPU mode / CPU 模式：

```bash
nwctl <target-name> planning-sim --profile cpu
```

In RViz:

在 RViz 中：

1. Select **2D Pose Estimate** and set the initial pose.
   选择 **2D Pose Estimate** 设置初始位置。
2. Select **2D Goal Pose** and set the destination.
   选择 **2D Goal Pose** 设置目标点。
3. Start driving from **AutowareStatePanel**.
   在 **AutowareStatePanel** 中启动行驶。

## 6. Replay a ROSbag / 回放 ROSbag

Use the default bag directory:

使用默认 ROSbag 目录：

```bash
nwctl <target-name> rosbag-replay
```

CPU mode / CPU 模式：

```bash
nwctl <target-name> rosbag-replay --profile cpu
```

The default host paths are:

默认主机路径：

```text
Map:    ~/autoware_map/sample-map-rosbag
ROSbag: ~/autoware_rosbag/sample-rosbag
```

The new ROSbag path above is the default from v0.2.2. On v0.2.1, set it once
in the terminal before using the short command:

以上 ROSbag 新路径从 v0.2.2 开始成为默认值。使用 v0.2.1 时，先在终端设置：

```bash
export SHARED_ROSBAG_PATH="$HOME/autoware_rosbag/sample-rosbag"
```

If the bag is stored in another directory:

如果 ROSbag 位于其他目录：

```bash
nwctl <target-name> rosbag-replay \
  --profile cpu \
  --rosbag-path /absolute/path/to/bags \
  --bag <bag-subdirectory> \
  --rate 1.0
```

`--bag` must be a subdirectory of `--rosbag-path`. If the selected directory
itself contains `metadata.yaml`, use only `--rosbag-path` and omit `--bag`.

`--bag` 必须是 `--rosbag-path` 下的子目录。如果指定目录本身已经包含
`metadata.yaml`，只使用 `--rosbag-path`，不要再添加 `--bag`。

## 7. Daily Development Flow / 日常开发流程

```text
Edit code → enter nwctl shell → build → test → commit → push feature branch
修改代码 → 进入 nwctl shell → 编译 → 测试 → 提交 → 推送 feature 分支
```

Before vehicle testing, confirm the target, Git commit, `ROS_DOMAIN_ID`, and
approved test window. Stop the container with `Ctrl+C` after testing. Autoware
may need several seconds to stop; if it remains running after the shutdown
messages, press `Ctrl+C` once more and confirm `nwctl list` shows `stopped`.

上车测试前确认 target、Git commit、`ROS_DOMAIN_ID` 和批准的测试时间；
测试完成后使用 `Ctrl+C` 停止容器。Autoware 退出可能需要几秒；如果退出日志后
仍未结束，再按一次 `Ctrl+C`，并通过 `nwctl list` 确认状态为 `stopped`。

## 8. Common Commands / 常用命令

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
an administrator to run `sudo nwctl <target-name> clean` once.

如果旧容器生成的文件导致 `clean` 报权限错误，请管理员执行一次
`sudo nwctl <target-name> clean`。
