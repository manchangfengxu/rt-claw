# Raspberry Pi 3 Local Voice + Expression Handoff Plan

## Confirmed decisions

- Local voice should not require users to type terminal commands for normal use.
- Raspberry Pi 3 local voice input will be controlled by a physical button.
- Button behavior is toggle-on-press:
  - If local capture is inactive, one press starts capture.
  - If local capture is active, one press stops capture and lets the voice turn continue.
- Button input should use Linux GPIO.
- The existing `/voice_local start/stop` behavior should remain available for debugging and manual testing.
- The button path should reuse the same local endpoint APIs used by `/voice_local`, not invoke shell commands as strings.
- Simple expression changes should be exposed to the AI as a callable tool/skill-like capability.
- First expression version should use a fixed enum, not arbitrary drawing.
- First expression trigger should be AI tool call only, not automatic voice-state linkage.

## Architectural constraints

Keep the current voice layering intact:

- `voice_service` owns endpoint-agnostic voice state and STT/TTS flow.
- `voice_endpoint` owns transport/backend dispatch.
- `platform/linux/local_voice_endpoint.c` owns Linux local audio capture/playback.
- Linux GPIO button handling belongs under `platform/linux`, not in `voice_service`.
- Display hardware details belong under `platform/linux` or a platform display abstraction, not in AI/tool logic.
- AI-callable expression behavior should be registered as a `claw_tool`, not as a hard dependency from voice service to display code.

Do not add Raspberry Pi checks or backend-name checks in `voice_service`.

## Part 1: Reuse `/voice_local start/stop` without depending on shell commands

Current manual control is implemented in `claw/shell/shell_commands.c`:

- `/voice_local start` calls `local_voice_endpoint_capture_start()`.
- `/voice_local stop` calls `local_voice_endpoint_capture_stop()`.
- `/voice_local cancel` calls `local_voice_endpoint_cancel()`.

The button implementation should reuse these endpoint functions directly.

Recommended additions to `platform/linux/local_voice_endpoint.c` and its header:

```c
int local_voice_endpoint_capturing(void);
int local_voice_endpoint_capture_toggle(void);
```

Recommended semantics:

```c
int local_voice_endpoint_capture_toggle(void)
{
    if (local_voice_endpoint_capturing()) {
        return local_voice_endpoint_capture_stop();
    }
    return local_voice_endpoint_capture_start();
}
```

The shell command can continue using explicit start/stop. The physical button should call `local_voice_endpoint_capture_toggle()`.

This keeps the shell as a debug/manual entry point and makes the button a separate platform input source using the same local endpoint state.

## Part 2: Linux GPIO button implementation

Recommended files:

```text
platform/linux/local_voice_button.c
include/platform/linux/local_voice_button.h
```

If the project prefers platform-local headers, use:

```text
platform/linux/local_voice_button.c
platform/linux/local_voice_button.h
```

Recommended public API:

```c
int local_voice_button_init(void);
int local_voice_button_start(void);
void local_voice_button_stop(void);
int local_voice_button_running(void);
```

Recommended behavior:

- Initialize GPIO input.
- Start a low-priority Linux thread.
- Wait for button press events.
- Debounce press events.
- On valid press, call `local_voice_endpoint_capture_toggle()`.
- Log failures with `CLAW_LOGW`, but do not crash or change `voice_service` state directly.

Important cases:

- If voice is disabled, `local_voice_endpoint_capture_start()` should reject capture. The button thread should simply log the failure.
- If local capture is already active, button press should stop capture.
- If capture start fails because ALSA/arecord is unavailable, log and keep listening for future button presses.
- Rapid repeated presses should be debounced.

Recommended GPIO backend:

1. Prefer `libgpiod` for Raspberry Pi 3.
2. If avoiding new dependency, use Linux GPIO character-device ioctls via `/dev/gpiochipN` and `linux/gpio.h`.
3. Avoid sysfs GPIO for new code.

Recommended configuration values:

```text
voice_button_gpiochip=/dev/gpiochip0
voice_button_line=17
voice_button_active_low=1
voice_button_debounce_ms=50
```

First implementation can use Meson options or environment-derived generated config values. Runtime `/voice_set` support can be added later if needed.

## Part 3: Build option wiring for the button

Add a Meson option:

```meson
option('linux_local_voice_button', type: 'boolean', value: false,
    description: 'Enable Linux GPIO button control for local voice endpoint')
```

Validation rules:

- `linux_local_voice_button=true` requires `voice=true`.
- `linux_local_voice_button=true` requires `linux_local_voice=true`.
- `linux_local_voice_button=true` only applies to `osal=linux`.

If using `libgpiod`, make it optional and only required when the button option is enabled:

```meson
gpiod_dep = dependency('libgpiod', required: get_option('linux_local_voice_button'))
```

Keep default false so CI and non-Raspberry-Pi Linux builds are not affected.

Wire startup/shutdown from `platform/linux/main.c` only when the option is enabled:

```c
#ifdef CONFIG_RTCLAW_LINUX_LOCAL_VOICE_BUTTON_ENABLE
    local_voice_button_init();
    local_voice_button_start();
#endif
```

Shutdown:

```c
#ifdef CONFIG_RTCLAW_LINUX_LOCAL_VOICE_BUTTON_ENABLE
    local_voice_button_stop();
#endif
```

## Part 4: Expression capability as AI-callable tool

The project has two related concepts:

1. AI skills in `claw/services/ai/ai_skill.c` are prompt-template/slash-command style skills.
2. LLM-callable tools in `claw/services/tools/*.c` are registered with `CLAW_TOOL_REGISTER()` and are appropriate for hardware side effects.

For expression changes, implement a tool. Product wording may call it a skill, but code should use the tool system.

Recommended file:

```text
claw/services/tools/expression.c
```

Recommended platform abstraction:

```text
include/platform/expression_display.h
platform/linux/expression_display_linux.c
platform/linux/expression_window.c or platform/linux/expression_window.py
assets/expressions/*.gif
```

Suggested abstraction:

```c
#ifndef PLATFORM_EXPRESSION_DISPLAY_H
#define PLATFORM_EXPRESSION_DISPLAY_H

#include "claw/core/errno.h"

claw_err_t platform_expression_set(const char *name);
const char *platform_expression_current(void);

#endif
```

The tool should validate the enum and call `platform_expression_set()`.

First supported enum:

```text
idle
happy
thinking
sad
listening
speaking
```

First implementation should switch between prebuilt GIF expression assets in a desktop window, not draw faces manually. Suggested resource layout:

```text
assets/expressions/idle.gif
assets/expressions/happy.gif
assets/expressions/thinking.gif
assets/expressions/sad.gif
assets/expressions/listening.gif
assets/expressions/speaking.gif
```

The Linux implementation should control a small local expression window. The window owns GIF loading, animation, scaling, and fullscreen/windowed behavior. `expression.c` should only know the enum name and the result JSON; it must not know GIF paths, desktop APIs, or framebuffer details.

Recommended Linux split:

- `platform/linux/expression_display_linux.c`: C-side platform adapter used by the tool.
- `platform/linux/expression_window.*`: the actual desktop UI process or helper.
- `assets/expressions/`: product assets, replaceable without changing AI/tool logic.

The adapter can notify the window through a simple local IPC mechanism such as a Unix domain socket, FIFO, or loopback localhost connection. Prefer a tiny protocol like `set happy\n`. Keep the IPC Linux-only and do not add it to `voice_service`.

## Part 5: Tool registration pattern

Use the existing `CLAW_TOOL_REGISTER()` pattern from `claw/services/tools/*.c`.

Recommended schema:

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

Recommended tool implementation shape:

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

Recommended registration shape:

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

If the project requires a capability bit, add a display capability such as `SWARM_CAP_DISPLAY` or reuse an existing LCD capability only if it already means local display access. Do not use GPIO capability for expression display.

## Part 6: Build option wiring for expression tool

Add Meson option:

```meson
option('tool_expression', type: 'boolean', value: false,
    description: 'Enable local expression display tool')
```

In `claw/meson.build`:

```meson
if get_option('tool_expression')
    feature_defs += '-DCONFIG_RTCLAW_TOOL_EXPRESSION'
    src_files += files('services/tools/expression.c')
endif
```

Linux platform expression adapter and the expression window should only be built or installed when needed. Keep default false to avoid breaking CI and non-display Linux builds.

## Part 7: Raspberry Pi 3 runtime arrangement

Target runtime arrangement:

- rt-claw runs as a Linux process on Raspberry Pi 3.
- Local ALSA voice endpoint handles microphone/speaker through `arecord`/`aplay`.
- GPIO button toggles local capture.
- AI can call `expression_set` to switch GIFs in the local expression window.

Suggested future local config values:

```text
voice_button_gpiochip=/dev/gpiochip0
voice_button_line=17
voice_button_active_low=1
voice_button_debounce_ms=50
expression_ipc=/run/rtclaw-expression.sock
expression_assets_dir=assets/expressions
expression_window_mode=fullscreen
```

If the project does not yet have a Linux runtime config file, keep these as Meson/generated config values for the first version and revisit runtime configuration later.

For final user-facing deployment, consider a systemd service so users do not need a terminal:

```text
/etc/systemd/system/rtclaw.service
```

Systemd setup can be documented later; it does not need to be part of the first code change.

## Recommended implementation order

1. Add local endpoint capture state helpers:
   - `local_voice_endpoint_capturing()`
   - `local_voice_endpoint_capture_toggle()`
2. Add Linux GPIO button monitor under `platform/linux`.
3. Wire `linux_local_voice_button` Meson option and Linux startup/shutdown.
4. Test button start/stop on Raspberry Pi 3.
5. Add expression platform abstraction.
6. Add a Linux expression window that displays GIF assets.
7. Add `expression_set` tool with fixed enum.
8. Wire `tool_expression` Meson option and optional window install/run path.
9. Test AI tool call switches GIFs in the expression window.
10. Only after the first version works, consider optional voice-state-to-expression automation.

## Test plan

Local build checks:

```bash
make build-linux
make test-unit-linux
scripts/test-meson-matrix.sh
scripts/check-patch.sh --staged
```

If `.agents/skills/` changes, also run:

```bash
make check-agent-skills
```

Raspberry Pi 3 button tests:

1. Start rt-claw with voice disabled.
2. Press button.
3. Confirm it does not start `arecord` and logs a clear failure.
4. Enable voice and local endpoint config.
5. Press button once.
6. Confirm local capture starts.
7. Press button again.
8. Confirm local capture stops and STT/TTS turn continues.
9. Rapidly press the button several times.
10. Confirm debounce prevents duplicate start/stop storms.

Expression tests:

1. Enable `tool_expression`.
2. Start the local expression window on the Raspberry Pi desktop.
3. Invoke `expression_set` with `happy`.
4. Confirm the window switches to `assets/expressions/happy.gif` and animates it.
5. Invoke `expression_set` with each supported enum.
6. Confirm each enum switches to the matching GIF without restarting voice services.
7. Invoke it with an invalid value.
8. Confirm it returns an error and does not crash.

## Explicit non-goals for first version

- Do not add voice-state automatic expression switching yet.
- Do not move GPIO logic into `voice_service`.
- Do not make `voice_service` depend on display or expression code.
- Do not call shell commands from button code.
- Do not hardcode Raspberry Pi GPIO line, GIF path, IPC path, or window behavior into platform-independent code.
- Do not make the AI tool load GIFs or call desktop APIs directly.
- Do not require new Linux display/button dependencies unless the corresponding Meson option is enabled.
