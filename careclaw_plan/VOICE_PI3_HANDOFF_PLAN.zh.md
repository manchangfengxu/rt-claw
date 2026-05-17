# Raspberry Pi 3 本地语音 + 表情交接计划

## 已确认决策

- 本地语音在正常使用时不应该要求用户在终端输入命令。
- Raspberry Pi 3 的本地语音输入由实体按钮控制。
- 按钮行为采用按下切换：
  - 如果当前没有采集，一次按下开始采集。
  - 如果当前正在采集，一次按下停止采集，并让本轮语音流程继续执行。
- 按钮输入使用 Linux GPIO。
- 现有 `/voice_local start/stop` 行为继续保留，用于调试和手动测试。
- 按钮路径应该复用 `/voice_local` 使用的同一组 local endpoint API，不要通过字符串调用 shell 命令。
- 简单表情切换能力应该暴露为 AI 可调用的 tool/类似 skill 的能力。
- 表情第一版使用固定枚举，不做任意绘图。
- 表情第一版只由 AI tool call 触发，不做 voice 状态自动联动。

## 架构约束

保持当前语音分层不变：

- `voice_service` 负责 endpoint 无关的语音状态和 STT/TTS 流程。
- `voice_endpoint` 负责 transport/backend 分发。
- `platform/linux/local_voice_endpoint.c` 负责 Linux 本地音频采集和播放。
- Linux GPIO 按钮处理属于 `platform/linux`，不要放进 `voice_service`。
- 显示硬件细节属于 `platform/linux` 或平台显示抽象，不要放进 AI/tool 逻辑。
- AI 可调用的表情行为应该注册为 `claw_tool`，不要让 voice service 直接依赖显示代码。

不要在 `voice_service` 里添加 Raspberry Pi 判断或 backend 名称判断。

## Part 1：复用 `/voice_local start/stop`，但不要依赖 shell 命令

当前手动控制实现在 `claw/shell/shell_commands.c`：

- `/voice_local start` 调用 `local_voice_endpoint_capture_start()`。
- `/voice_local stop` 调用 `local_voice_endpoint_capture_stop()`。
- `/voice_local cancel` 调用 `local_voice_endpoint_cancel()`。

按钮实现应该直接复用这些 endpoint 函数。

建议在 `platform/linux/local_voice_endpoint.c` 及其头文件中增加：

```c
int local_voice_endpoint_capturing(void);
int local_voice_endpoint_capture_toggle(void);
```

推荐语义：

```c
int local_voice_endpoint_capture_toggle(void)
{
    if (local_voice_endpoint_capturing()) {
        return local_voice_endpoint_capture_stop();
    }
    return local_voice_endpoint_capture_start();
}
```

shell 命令可以继续使用显式 start/stop。实体按钮调用 `local_voice_endpoint_capture_toggle()`。

这样 shell 仍然是调试/手动入口，按钮则作为独立的平台输入源，共享同一个 local endpoint 状态。

## Part 2：Linux GPIO 按钮实现

推荐文件：

```text
platform/linux/local_voice_button.c
include/platform/linux/local_voice_button.h
```

如果项目更偏好 platform-local 头文件，也可以使用：

```text
platform/linux/local_voice_button.c
platform/linux/local_voice_button.h
```

推荐公共 API：

```c
int local_voice_button_init(void);
int local_voice_button_start(void);
void local_voice_button_stop(void);
int local_voice_button_running(void);
```

推荐行为：

- 初始化 GPIO 输入。
- 启动一个低优先级 Linux 线程。
- 等待按钮按下事件。
- 对按下事件做消抖。
- 有效按下时调用 `local_voice_endpoint_capture_toggle()`。
- 失败时用 `CLAW_LOGW` 记录日志，但不要崩溃，也不要直接修改 `voice_service` 状态。

重要场景：

- 如果 voice 被禁用，`local_voice_endpoint_capture_start()` 应拒绝采集。按钮线程只需要记录失败。
- 如果 local capture 已经处于 active，按钮按下应停止采集。
- 如果因为 ALSA/arecord 不可用导致 start 失败，记录日志并继续监听后续按钮。
- 快速重复按下应该被消抖。

推荐 GPIO 后端：

1. Raspberry Pi 3 优先使用 `libgpiod`。
2. 如果想避免新增依赖，可以通过 `/dev/gpiochipN` 和 `linux/gpio.h` 使用 Linux GPIO character-device ioctl。
3. 新代码避免使用 sysfs GPIO。

推荐配置值：

```text
voice_button_gpiochip=/dev/gpiochip0
voice_button_line=17
voice_button_active_low=1
voice_button_debounce_ms=50
```

第一版可以使用 Meson option 或环境变量生成配置。后续如果需要，再加 runtime `/voice_set` 支持。

## Part 3：按钮构建选项接线

新增 Meson option：

```meson
option('linux_local_voice_button', type: 'boolean', value: false,
    description: 'Enable Linux GPIO button control for local voice endpoint')
```

校验规则：

- `linux_local_voice_button=true` 要求 `voice=true`。
- `linux_local_voice_button=true` 要求 `linux_local_voice=true`。
- `linux_local_voice_button=true` 只适用于 `osal=linux`。

如果使用 `libgpiod`，让它成为可选依赖，并且只在启用按钮选项时 required：

```meson
gpiod_dep = dependency('libgpiod', required: get_option('linux_local_voice_button'))
```

默认保持 false，避免影响 CI 和非 Raspberry Pi 的 Linux build。

只在启用选项时，从 `platform/linux/main.c` 接入启动/停止：

```c
#ifdef CONFIG_RTCLAW_LINUX_LOCAL_VOICE_BUTTON_ENABLE
    local_voice_button_init();
    local_voice_button_start();
#endif
```

退出时：

```c
#ifdef CONFIG_RTCLAW_LINUX_LOCAL_VOICE_BUTTON_ENABLE
    local_voice_button_stop();
#endif
```

## Part 4：表情能力作为 AI 可调用 tool

项目里有两个相关概念：

1. `claw/services/ai/ai_skill.c` 里的 AI skill 是 prompt template / slash command 风格的技能。
2. `claw/services/tools/*.c` 里的 LLM-callable tools 通过 `CLAW_TOOL_REGISTER()` 注册，适合硬件副作用。

表情变化应实现为 tool。产品话术可以叫 skill，但代码里应走 tool system。

推荐文件：

```text
claw/services/tools/expression.c
```

推荐平台抽象：

```text
include/platform/expression_display.h
platform/linux/expression_display_linux.c
platform/linux/expression_window.c 或 platform/linux/expression_window.py
assets/expressions/*.gif
```

建议抽象：

```c
#ifndef PLATFORM_EXPRESSION_DISPLAY_H
#define PLATFORM_EXPRESSION_DISPLAY_H

#include "claw/core/errno.h"

claw_err_t platform_expression_set(const char *name);
const char *platform_expression_current(void);

#endif
```

tool 负责校验枚举并调用 `platform_expression_set()`。

第一版支持枚举：

```text
idle
happy
thinking
sad
listening
speaking
```

第一版实现应该在桌面窗口中切换预置 GIF 表情资源，不要手动画脸。建议资源布局：

```text
assets/expressions/idle.gif
assets/expressions/happy.gif
assets/expressions/thinking.gif
assets/expressions/sad.gif
assets/expressions/listening.gif
assets/expressions/speaking.gif
```

Linux 实现应该控制一个小的本地表情窗口。窗口负责 GIF 加载、动画、缩放、全屏/窗口模式。`expression.c` 只应该知道枚举名和结果 JSON；它不应该知道 GIF 路径、桌面 API 或 framebuffer 细节。

推荐 Linux 拆分：

- `platform/linux/expression_display_linux.c`：tool 使用的 C 侧平台适配层。
- `platform/linux/expression_window.*`：真正的桌面 UI 进程或 helper。
- `assets/expressions/`：产品资源，可替换，不影响 AI/tool 逻辑。

adapter 可以通过简单本地 IPC 通知窗口，比如 Unix domain socket、FIFO 或 loopback localhost。协议优先保持简单，例如 `set happy\n`。IPC 保持 Linux-only，不要加入 `voice_service`。

## Part 5：Tool 注册模式

使用 `claw/services/tools/*.c` 里已有的 `CLAW_TOOL_REGISTER()` 模式。

推荐 schema：

```c
static const char schema_expression_set[] =
    "{\"type\":\"object\"," 
    "\"properties\":{" 
    "\"expression\":{\"type\":\"string\"," 
    "\"enum\":[\"idle\",\"happy\",\"thinking\",\"sad\"," 
    "\"listening\",\"speaking\"],"
    "\"description\":\"Expression to show on the local display\"}},"
    "\"required\":[\"expression\"]}";
```

推荐 tool 实现形态：

```c
static claw_err_t tool_expression_set(struct claw_tool *tool,
                                      const cJSON *params,
                                      cJSON *result)
{
    cJSON *expr_j = cJSON_GetObjectItem(params, "expression");

    (void)tool;
    if (!expr_j || !cJSON_IsString(expr_j)) {
        cJSON_AddStringToObject(result, "error", "missing expression");
        return CLAW_ERROR;
    }
    if (platform_expression_set(expr_j->valuestring) != CLAW_OK) {
        cJSON_AddStringToObject(result, "error", "unsupported expression");
        return CLAW_ERROR;
    }
    cJSON_AddStringToObject(result, "status", "ok");
    cJSON_AddStringToObject(result, "expression", expr_j->valuestring);
    return CLAW_OK;
}
```

推荐注册形态：

```c
static const struct claw_tool_ops expression_set_ops = {
    .execute = tool_expression_set,
};

static struct claw_tool expression_set_tool = {
    .name = "expression_set",
    .description = "Switch the local expression window to a named expression.",
    .input_schema_json = schema_expression_set,
    .ops = &expression_set_ops,
    .flags = CLAW_TOOL_LOCAL_ONLY,
};

CLAW_TOOL_REGISTER(expression_set, &expression_set_tool);
```

如果项目要求 capability bit，新增类似 `SWARM_CAP_DISPLAY` 的显示能力，或者仅在现有 LCD capability 已明确表示本地显示访问时复用它。不要用 GPIO capability 表示表情显示。

## Part 6：表情 tool 构建选项接线

新增 Meson option：

```meson
option('tool_expression', type: 'boolean', value: false,
    description: 'Enable local expression display tool')
```

在 `claw/meson.build` 中：

```meson
if get_option('tool_expression')
    feature_defs += '-DCONFIG_RTCLAW_TOOL_EXPRESSION'
    src_files += files('services/tools/expression.c')
endif
```

Linux 平台 expression adapter 和 expression window 只应在需要时构建或安装。默认保持 false，避免影响 CI 和无显示环境的 Linux build。

## Part 7：Raspberry Pi 3 运行时安排

目标运行时安排：

- rt-claw 作为 Linux 进程运行在 Raspberry Pi 3 上。
- Local ALSA voice endpoint 通过 `arecord`/`aplay` 处理麦克风/扬声器。
- GPIO 按钮切换本地采集。
- AI 可以调用 `expression_set` 在本地表情窗口里切换 GIF。

建议未来本地配置值：

```text
voice_button_gpiochip=/dev/gpiochip0
voice_button_line=17
voice_button_active_low=1
voice_button_debounce_ms=50
expression_ipc=/run/rtclaw-expression.sock
expression_assets_dir=assets/expressions
expression_window_mode=fullscreen
```

如果项目还没有统一 Linux runtime config 文件，第一版可以先用 Meson/generated config，之后再补 runtime 配置。

最终用户部署可以考虑 systemd service，这样用户不需要终端：

```text
/etc/systemd/system/rtclaw.service
```

systemd setup 可以后续再写文档，第一版代码不必包含。

## 推荐实现顺序

1. 添加 local endpoint 采集状态 helper：
   - `local_voice_endpoint_capturing()`
   - `local_voice_endpoint_capture_toggle()`
2. 在 `platform/linux` 下添加 Linux GPIO button monitor。
3. 接入 `linux_local_voice_button` Meson option 和 Linux 启动/停止流程。
4. 在 Raspberry Pi 3 上测试按钮 start/stop。
5. 添加 expression platform abstraction。
6. 添加显示 GIF 资源的 Linux expression window。
7. 添加固定枚举的 `expression_set` tool。
8. 接入 `tool_expression` Meson option 和可选 window install/run 路径。
9. 测试 AI tool call 能切换 expression window 里的 GIF。
10. 第一版跑通后，再考虑可选的 voice-state-to-expression 自动联动。

## 测试计划

本地 build 检查：

```bash
make build-linux
make test-unit-linux
scripts/test-meson-matrix.sh
scripts/check-patch.sh --staged
```

如果 `.agents/skills/` 有改动，还要运行：

```bash
make check-agent-skills
```

Raspberry Pi 3 按钮测试：

1. 在 voice disabled 状态启动 rt-claw。
2. 按按钮。
3. 确认不会启动 `arecord`，并且日志中有清晰失败信息。
4. 启用 voice 和 local endpoint 配置。
5. 按一次按钮。
6. 确认 local capture 开始。
7. 再按一次按钮。
8. 确认 local capture 停止，并且 STT/TTS turn 继续。
9. 快速连续按几次按钮。
10. 确认消抖能避免重复 start/stop 风暴。

Expression 测试：

1. 启用 `tool_expression`。
2. 在 Raspberry Pi 桌面启动本地 expression window。
3. 用 `happy` 调用 `expression_set`。
4. 确认窗口切到 `assets/expressions/happy.gif` 并播放动画。
5. 用每个支持的 enum 调用 `expression_set`。
6. 确认每个 enum 都能切换到对应 GIF，且不需要重启 voice services。
7. 用非法值调用。
8. 确认返回错误且不会崩溃。

## 第一版明确不做

- 不做 voice-state 自动表情切换。
- 不把 GPIO 逻辑放进 `voice_service`。
- 不让 `voice_service` 依赖 display 或 expression 代码。
- 不从按钮代码调用 shell 命令。
- 不把 Raspberry Pi GPIO line、GIF 路径、IPC 路径或窗口行为硬编码进平台无关代码。
- 不让 AI tool 直接加载 GIF 或调用桌面 API。
- 不在未启用对应 Meson option 时强制引入新的 Linux display/button 依赖。
