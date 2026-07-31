# nwctl 多成员 Autoware 开发与实车测试教程

本文面向在同一台主机上进行 Autoware 开发、仿真、ROSbag 回放和实车验证的团队。

## 1. 基本原则

- 安全要求较高时，每位成员使用独立 Linux 账号；受信任的小团队也可以使用共享 `dev` 实车测试账号。
- 无论采用哪种 Linux 账号模式，不同源码版本都应使用可追溯的目录、分支和构建记录。
- 每个源码版本使用独立目标，不复用其他架构或版本的 build/install。
- 日常开发不得使用车辆 DOMAIN。
- 车辆 DOMAIN 只运行审核后、可追溯、可回滚的固定提交或构建产物。
- `ROS_DOMAIN_ID` 只隔离 DDS discovery，不提供身份认证或访问授权。
- `docker` 组近似拥有主机 root 权限，不能作为不可信成员的安全边界。

DOMAIN 规划：

| 范围 | 用途 | 分配方式 |
|---|---|---|
| 0–9 | 车辆/生产 | 管理员显式授权 |
| 10–199 | 个人开发、Planning、ROSbag | 注册时自动分配 |
| 200–232 | 团队集成测试 | 管理员显式分配 |

建议预先记录车辆实际使用的 DOMAIN，例如：

```text
车辆 DOMAIN_ID=5
集成 DOMAIN_ID=200
```

## 2. 管理员准备 Linux 账号

### 2.1 独立账号模式（推荐）

为每位成员创建独立账号：

```bash
sudo adduser alice
sudo adduser bob
```

源码、SSH key、Git 凭据都由成员自己的账号管理。不要多人共享一个 Linux 账号。

根据硬件类型添加最小权限组：

```bash
# 串口、USB-CAN、GNSS
sudo usermod -aG dialout alice

# V4L2 摄像头
sudo usermod -aG video alice

# 某些 USB/GPIO 设备按主机规则需要
sudo usermod -aG plugdev alice
```

成员需要注销并重新登录，组权限才会生效。

独立账号的优势是操作日志、文件所有权、SSH key 和 Git 凭据可以追溯到个人。

### 2.2 共享 dev 账号模式（受信任团队）

如果车辆主机只供受信任的内部成员做排期实车测试，可以保留一个共享
`dev` Linux 账号。管理员只需一次性创建一个车辆测试目标：

```bash
sudo nwctl register vehicle_dev \
  --src /home/dev/autoware-vehicle-test/src

sudo nwctl set-domain vehicle_dev \
  --domain-id 5 \
  --production
```

`dev` 账号属于 docker 组时，成员仍可自行启动这个已经注册的目标：

```bash
nwctl vehicle_dev shell --profile cpu
```

v0.2.2 要求 sudo 的只是 `register`、`update`、`set-domain` 和
`unregister`，启动已注册容器不要求 sudo。

共享账号的限制：

- 所有成员拥有相同的主机和 Docker 权限，不能形成成员之间的安全隔离；
- Git 凭据和 shell history 不应共用，推荐成员使用自己的 SSH 登录身份或跳板审计；
- 同一时间只允许一个车辆测试容器使用车辆 DOMAIN；
- 切换分支前必须停止上一测试、记录 SHA，并处理旧 build/install；
- 车辆测试必须使用排期锁或书面测试记录，避免两人同时切换代码。

推荐共享车辆工作目录只保留一个当前测试分支：

```bash
cd /home/dev/autoware-vehicle-test
git fetch origin
git switch feature/alice-lane-change
git reset --hard origin/feature/alice-lane-change
git rev-parse HEAD
```

其中 `git reset --hard` 只能在确认该目录没有未提交工作后由测试流程执行；
个人开发内容应先推送到远端 feature 分支。

分支差异较大时，应清理或使用分支专属构建目录，避免旧产物污染：

```bash
nwctl vehicle_dev clean
```

该操作会删除构建缓存，执行前应确认车辆测试容器已停止。

## 3. 成员准备源码

以成员账号执行：

```bash
cd /home/alice
git clone https://github.com/autowarefoundation/autoware.git autoware-main
cd autoware-main
vcs import src < repositories/autoware.repos
```

为差异较大的版本使用不同目录：

```text
/home/alice/autoware-2025.02/src
/home/alice/autoware-main/src
/home/alice/autoware-feature-lane-change/src
```

## 4. 管理员创建 nwctl 工作区

nwctl v0.2.2 中，系统注册表只能由管理员修改。

```bash
sudo nwctl register alice_main \
  --src /home/alice/autoware-main/src

sudo nwctl register bob_main \
  --src /home/bob/autoware-main/src
```

开发 DOMAIN 会从 10–199 自动选择。检查结果：

```bash
nwctl list
```

映射关系示例：

```text
/home/alice/autoware-main/src
  → 容器 /workspace/src

/var/lib/nwctl/workspaces/alice_main/build
  → 容器 /workspace/build

/var/lib/nwctl/workspaces/alice_main/install
  → 容器 /workspace/install

/var/lib/nwctl/workspaces/alice_main/log
  → 容器 /workspace/log
```

如果同一成员需要测试另一个 Autoware 版本，应注册新目标：

```bash
sudo nwctl register alice_202502 \
  --src /home/alice/autoware-2025.02/src
```

不要用 `update` 在差异较大的版本之间反复切换，否则旧 build/install 可能污染新版本。

## 5. 日常开发流程

### 5.1 创建功能分支

```bash
cd /home/alice/autoware-main/src/universe/autoware_universe
git switch -c feature/alice-lane-change
```

### 5.2 进入开发容器

在允许成员运行容器的开发主机上：

```bash
nwctl alice_main shell --profile cpu
```

容器内：

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

返回路径应位于 `/workspace/install`。

### 5.3 仿真和 ROSbag

日常验证只使用成员自己的开发 DOMAIN：

```bash
nwctl alice_main planning-sim \
  --profile cpu \
  --map-name sample-map-rosbag

nwctl alice_main rosbag-replay \
  --profile cpu \
  --map-name sample-map-rosbag
```

完成以下检查后再提交：

- 修改包编译成功；
- Planning 或对应节点正常启动；
- 官方/项目 ROSbag 能完整回放；
- 没有 FATAL、Traceback 或节点异常退出；
- 关键输入输出 topic 有实际消息；
- 测试日志和使用的 Git SHA 已记录。

### 5.4 提交与合并

```bash
git status
git add <files>
git commit -m "feat: describe the change"
git push origin feature/alice-lane-change
```

提交 Merge Request 到 `dev`/`integration`，不要由个人直接把 feature 分支部署到车辆 DOMAIN。

## 6. 推荐的分支和发布流程

```text
feature/*（个人开发 DOMAIN）
  ↓ Merge Request + Review
dev / integration（集成 DOMAIN 200–232）
  ↓ CI 编译、仿真、ROSbag、接口检查
release candidate（固定 Git SHA 和构建产物）
  ↓ 测试负责人批准
vehicle target（车辆 DOMAIN 0–9）
  ↓ 实车测试、记录结果
release / rollback
```

集成目标由管理员创建：

```bash
sudo nwctl register integration_humble \
  --src /opt/autoware-integration/current/src

sudo nwctl set-domain integration_humble --domain-id 200
```

## 7. 实车测试流程

车辆目标应关联审核后的固定目录，而不是个人工作目录：

```bash
sudo nwctl register vehicle_rc \
  --src /opt/autoware-deployments/<approved-git-sha>/src

sudo nwctl set-domain vehicle_rc \
  --domain-id 5 \
  --production
```

实车测试前必须：

1. 确认车辆 DOMAIN 和目标名称；
2. 记录 Git SHA、镜像 digest、地图版本和参数版本；
3. 停止同一车辆 DOMAIN 上的其他 ROS 2 实例；
4. 确认车辆静止、急停有效、安全员在场；
5. 首次测试禁止直接开放自动驾驶控制输出；
6. 先检查感知、定位和规划只读数据；
7. 再按审批步骤开放车辆接口；
8. 测试后恢复已知稳定版本。

车辆 DOMAIN 不应临时分配给个人目标，也不应通过修改 shell 中的
`ROS_DOMAIN_ID` 绕过审批。

## 8. docker 组权限模型

### 8.1 开发主机

如果主机与车辆控制网络隔离，且成员是可信开发者，可以保留 docker 组：

```bash
sudo usermod -aG docker alice
```

这让成员可以自行启动 `nwctl ... shell/planning-sim/rosbag-replay`，但也意味着该成员近似拥有主机 root 权限。

### 8.2 车辆或安全敏感主机

移除普通开发者的 docker 组：

```bash
sudo gpasswd -d alice docker
sudo gpasswd -d bob docker
```

然后让成员注销并重新登录，验证：

```bash
id alice
getent group docker
```

移除 docker 组不会改变 ROS 2、以太网 LiDAR、GNSS 或 CAN 协议本身，但成员将不能直接执行 `docker run`，因此也不能自行启动当前版本的 nwctl 容器。

车辆主机应由以下方式之一启动容器：

1. 管理员在批准的测试窗口运行 nwctl；
2. CI/CD 使用受保护的 runner 运行固定目标；
3. 后续部署受限的 systemd/服务端启动器，只允许白名单目标和模式；
4. 使用经过验证的 rootless 容器方案。

不要直接给普通成员配置：

```text
NOPASSWD: /usr/bin/docker *
```

这与重新加入 docker 组没有本质区别。

## 9. 硬件通信与权限

硬件通信权限应按设备单独授予，而不是通过 docker 组统一解决。

| 硬件 | 主机侧要求 | 容器侧要求 |
|---|---|---|
| 以太网 LiDAR/雷达 | 网络路由、VLAN、防火墙 | 受控 host/macvlan 网络 |
| USB/串口 GNSS | `dialout`、udev 规则 | 显式映射 `/dev/ttyUSB*` |
| USB-CAN | `dialout` 或设备 udev 组 | 显式映射对应 `/dev` |
| SocketCAN `can0` | 管理员预先配置接口 | 仅授予所需网络 capability |
| V4L2 摄像头 | `video` 组 | 显式映射 `/dev/video*` |
| NVIDIA GPU | 驱动与 runtime | NVIDIA runtime/device |

当前 nwctl 主要覆盖 Autoware 开发、仿真和 ROSbag，并未提供完整的硬件设备白名单配置。车辆部署前应增加独立的 hardware profile，明确：

- 允许的 `/dev` 设备；
- 允许的网卡和端口；
- 是否需要 `NET_RAW`/`NET_ADMIN`；
- 只读和读写挂载；
- 车辆控制 topic/service 白名单；
- 急停和控制权仲裁。

在 hardware profile 完成前，安全敏感主机应由管理员启动容器，不应通过把开发者加入 docker 组来解决设备访问问题。

## 10. 管理员常用命令

```bash
# 注册开发目标，自动分配 10–199
sudo nwctl register alice_main --src /home/alice/autoware-main/src

# 修改源码路径（同版本小范围迁移）
sudo nwctl update alice_main --src /home/alice/autoware-new/src

# 分配集成 DOMAIN
sudo nwctl set-domain integration_humble --domain-id 200

# 分配车辆 DOMAIN，需要显式确认
sudo nwctl set-domain vehicle_rc --domain-id 5 --production

# 保留构建产物并注销
sudo nwctl unregister alice_main --keep-workspace

# 查看目标、运行容器和磁盘占用
nwctl list
nwctl status
nwctl disk
```

## 11. 安全边界说明

以下措施不能单独提供车辆安全：

- 只修改 `ROS_DOMAIN_ID`；
- 只使用不同 Git 分支；
- 只把注册表设为 root 可写；
- 仅依赖容器名称或普通 Linux 组。

建议同时使用：

- 车辆网络 VLAN/防火墙；
- DDS Security 或等价认证机制；
- 控制 topic/service 白名单；
- 受控构建和镜像 digest；
- 运行账户最小权限；
- 审批、日志、回滚和实车测试清单。
