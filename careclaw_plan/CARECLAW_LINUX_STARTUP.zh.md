# CareClaw Linux / Raspberry Pi 3 启动文档

## 目标

本文档用于接手者在 Linux / Raspberry Pi 3 环境中构建并启动 CareClaw。

当前 `careclaw` 分支仍复用 rt-claw 的 Linux native 构建入口。第一阶段不重命名 Meson target、Makefile target 或核心目录，只通过运行时 persona、环境变量和默认启用的 Linux voice endpoint 形成 CareClaw 产品形态。

相关规划：

- `careclaw_plan/CARECLAW_PI3_PRODUCT_PLAN.zh.md`：CareClaw 产品人格、API 配置和边界。
- `careclaw_plan/VOICE_PI3_HANDOFF_PLAN.zh.md`：Pi3 本地语音按钮和 GIF 表情窗口方案。

## 默认编译配置

当前 `make build-linux` 已经适合作为 CareClaw Pi3 第一阶段默认构建入口。

Makefile 中 Linux 默认配置为：

```text
-Dosal=linux
-Dtool_script=true
-Dvoice=true
-Dlinux_web_voice=true
-Dlinux_local_voice=true
```

含义：

- `osal=linux`：使用 Linux OSAL。
- `tool_script=true`：启用脚本工具。
- `voice=true`：启用语音服务。
- `linux_web_voice=true`：启用 Linux web voice endpoint。
- `linux_local_voice=true`：启用 Linux local ALSA voice endpoint。

虽然 CareClaw 第一目标是 Raspberry Pi 3 local voice，但保留 web voice endpoint 对调试有帮助；不要因为产品化就急着删掉。

后续如果完成按钮和 GIF 表情窗口，可以在默认构建中考虑加入：

```text
-Dlinux_local_voice_button=true
-Dtool_expression=true
```

但只有在对应代码和依赖都稳定后再改默认值。第一阶段不要为了规划文档提前改 Makefile。

## 依赖准备

基础依赖：

```bash
sudo apt update
sudo apt install -y build-essential meson ninja-build pkg-config libcurl4-openssl-dev libssl-dev
```

本地语音依赖：

```bash
sudo apt install -y alsa-utils
```

如果后续启用 GPIO 按钮，优先准备：

```bash
sudo apt install -y gpiod libgpiod-dev
```

如果后续启用 GIF 表情窗口，根据实现选择安装窗口依赖。例如：

- Python/PyQt/PyGObject 方案：安装对应 Python GUI 包。
- SDL2 方案：安装 `libsdl2-dev` 和 image/gif 支持库。
- 浏览器/WebView 方案：安装对应浏览器或 webview runtime。

第一版未实现前，不要把这些 GUI 依赖变成默认强依赖。

## API 环境变量

CareClaw 第一阶段继续使用现有 `RTCLAW_AI_*` 环境变量。

构建前设置：

```bash
export RTCLAW_AI_API_KEY='你的 CareClaw API Key'
export RTCLAW_AI_API_URL='你的 CareClaw API URL'
export RTCLAW_AI_MODEL='你的 CareClaw 模型名'
```

注意：

- 不要把真实 key、私有 URL 写入仓库。
- 不要提交包含 secret 的脚本或配置文件。
- 如果用 systemd，建议把 secret 放到 `/etc/careclaw/careclaw.env`，并确保该文件不进 git。

## 构建

在仓库根目录执行：

```bash
make build-linux
```

输出路径：

```text
build/linux/platform/linux/rtclaw
```

如果修改了 Meson option 或想清理重来：

```bash
make clean-linux
make build-linux
```

## 启动

直接运行：

```bash
make run-linux
```

或运行编译产物：

```bash
build/linux/platform/linux/rtclaw
```

当前 Linux 程序仍会进入 shell loop。产品化后，普通用户不应该依赖 shell；shell 只作为调试入口保留。

## 首次配置建议

如果需要从 shell 调试 AI：

```text
/ai_set key <你的 key>
/ai_set url <你的 URL>
/ai_set model <你的 model>
```

如果需要启用 local voice：

```text
/voice_enable on
/voice_set endpoint_backend local
```

如果需要配置本地音频设备：

```text
/voice_local input <ALSA input device>
/voice_local output <ALSA output device>
```

如果使用默认 ALSA 设备，可以先不设置 input/output。

调试采集：

```text
/voice_local start
/voice_local stop
```

注意：这些命令是开发/调试入口。真正用户入口应按 `VOICE_PI3_HANDOFF_PLAN.zh.md` 接入 GPIO 按钮。

## ALSA 设备检查

在 Raspberry Pi 3 上检查录音设备：

```bash
arecord -l
```

检查播放设备：

```bash
aplay -l
```

快速录放测试：

```bash
arecord -f S16_LE -r 16000 -c 1 -d 3 /tmp/test.wav
aplay /tmp/test.wav
```

如果这一步失败，先修 ALSA/硬件设备，不要直接改 voice service。

## 推荐 Raspberry Pi 3 本地启动流程

1. 准备依赖。
2. 设置 `RTCLAW_AI_API_KEY`、`RTCLAW_AI_API_URL`、`RTCLAW_AI_MODEL`。
3. 执行 `make build-linux`。
4. 用 `arecord` / `aplay` 单独验证麦克风和扬声器。
5. 执行 `make run-linux`。
6. 用 shell 设置 local voice backend。
7. 用 `/voice_local start/stop` 验证语音链路。
8. 后续接入 GPIO 按钮后，用按钮替代 `/voice_local start/stop`。
9. 后续接入 GIF 表情窗口后，用 `expression_set` tool 验证表情切换。

## systemd 部署建议

最终产品不应要求用户手动开终端运行。可以后续增加 systemd service。

建议环境文件：

```text
/etc/careclaw/careclaw.env
```

示例内容：

```text
RTCLAW_AI_API_KEY=你的 CareClaw API Key
RTCLAW_AI_API_URL=你的 CareClaw API URL
RTCLAW_AI_MODEL=你的 CareClaw 模型名
```

示例 service 方向：

```ini
[Unit]
Description=CareClaw Raspberry Pi Companion
After=network-online.target sound.target
Wants=network-online.target

[Service]
WorkingDirectory=/home/pi/rt-claw
EnvironmentFile=/etc/careclaw/careclaw.env
ExecStart=/home/pi/rt-claw/build/linux/platform/linux/rtclaw
Restart=on-failure
User=pi

[Install]
WantedBy=multi-user.target
```

真实路径按部署环境调整。

如果 expression window 需要桌面会话，可能要用用户级 systemd service 或桌面 autostart，而不是普通 system service。不要把 GUI 窗口强行塞进 headless service。

## 默认能力边界

第一阶段默认可以认为：

- Linux native build 是 CareClaw Pi3 主路径。
- local voice 是主用户语音入口。
- web voice 保留为调试/备用入口。
- `/voice_local start/stop` 是调试入口，按钮是未来用户入口。
- `expression_set` 是未来 AI 表情入口，GIF window 是平台显示实现。
- API key/url/model 使用环境变量注入。

不要做：

- 不重命名 `rtclaw` binary 或 Meson target。
- 不把 secret 写进源码。
- 不把 GPIO 按钮逻辑放入 `voice_service`。
- 不把 GIF/window 逻辑放入 AI tool 或 voice service。
- 不为了产品化删除 web endpoint 或 shell 调试命令。

## 验证命令

基础验证：

```bash
make build-linux
make test-unit-linux
```

配置矩阵验证：

```bash
scripts/test-meson-matrix.sh
```

样式检查：

```bash
scripts/check-patch.sh --staged
```

如果只改文档，至少确认文档路径和文件名正确。若后续改代码，再按相关文件运行 `check-patch.sh --file <path>`。
