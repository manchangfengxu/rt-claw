# CareClaw Raspberry Pi 3 产品化交接计划

## 已确认范围

CareClaw 是一个运行在 Raspberry Pi 3 上的嵌入式 AI 陪伴设备，重点是偏心理支持/心理辅导风格的对话。

第一阶段范围刻意保持小：

- 修改运行时人格和用户可见语气。
- 复用现有 AI API 配置机制，通过环境变量传入 CareClaw 的 API key、URL 和 model。
- 保持现有 rt-claw 代码结构和 service 边界。
- 不重命名核心目录、公共前缀、OSAL 名称或内部 service 架构。
- 不对整个仓库做大规模品牌重命名。
- 不把第一阶段变成医疗/临床产品重设计。

这份文档用于交接。它应该指导后续贡献者做一次聚焦的产品风格适配，同时避免污染底层 rt-claw 架构。

## 与现有 Pi3 语音交接计划的关系

`careclaw_plan/VOICE_PI3_HANDOFF_PLAN.md` 已经为本地语音输入和表情显示划定了重要边界：

- GPIO 按钮处理属于 `platform/linux`，不要放进 `voice_service`。
- 本地语音按钮代码应该复用 `local_voice_endpoint_capture_start/stop/toggle` API，不要调用 shell 命令。
- 显示硬件细节属于 platform display 代码，不要进入 voice service 或 AI prompt 逻辑。
- 表情变化应该注册为 AI 可调用 tool，即通过 `CLAW_TOOL_REGISTER`，不要硬编码进 voice flow。
- 第一版应该避免 voice-state-to-expression 自动联动。

这份 CareClaw plan 也遵循同样的边界风格：

- 产品人格属于 AI prompt / 配置表面。
- 平台行为属于 `platform/linux`。
- Voice transport 和 STT/TTS 继续保持 endpoint/provider 抽象。
- CareClaw 特有的产品默认值应该作为配置/profile 层叠加，不要散落到 core services 里。

## 产品方向

CareClaw 应该给人的感觉是：

- 温暖、有耐心。
- 支持性，而不是命令控制式。
- 足够短，适合语音交互。
- 用户情绪低落时保持平静。
- 能温和地追问。
- 明确自己是 AI 陪伴，不是医生或紧急服务。

因为第一版是轻量产品化，使用温和的安全边界提示即可，不要加入很重的法律/医疗免责声明。

建议行为约束：

- 不诊断心理疾病。
- 不声称提供专业治疗。
- 不开药或给治疗处方。
- 如果用户看起来处于立即危险或自伤风险中，引导其联系可信任的人或当地紧急支持。
- 优先使用反映式倾听、 grounding 建议和小的下一步问题。
- 回答保持简短，适合语音播放。
- 使用用户使用的语言回复。

## 推荐第一阶段实现策略

优先把 CareClaw 作为运行时 profile，而不是大规模代码重命名。

项目结构上仍然是 rt-claw。CareClaw 应该作为产品 profile 叠在其上：

```text
rt-claw core/runtime        保持不变
CareClaw product profile    修改 persona/defaults/用户可见语气
Raspberry Pi 3 platform     承载本地语音/按钮/显示集成
```

这样能避免破坏现有 build 逻辑、文档、测试、service 注册和 OSAL 边界。

## 需要修改或包装的关键触点

### 1. AI system prompt

主要当前触点：

```text
claw/services/ai/ai_engine.c
```

当前 base prompt 嵌在 `SYSTEM_PROMPT` 中，描述 assistant 是运行在嵌入式 RTOS 设备上的 rt-claw。

第一阶段目标：

- 替换或通过 profile gate 选择 base prompt，使 CareClaw 使用心理支持型陪伴人格。
- 保留硬件/tool awareness，因为 CareClaw 仍然运行在嵌入式硬件上，也可能调用本地 tools。
- 保留跟随用户语言回复的规则。
- 加入轻量安全边界。

推荐 CareClaw prompt 内容：

```text
You are CareClaw, a warm and supportive AI companion running on a Raspberry Pi 3 embedded device.
You help users reflect on feelings, reduce stress, and take small constructive next steps.
You are not a doctor, therapist, or emergency service, and you should not diagnose conditions or prescribe treatment.
If the user may be in immediate danger or at risk of self-harm, gently encourage contacting trusted people or local emergency support.
Use available tools only when helpful for the local device experience.
Keep replies concise for voice interaction, empathetic, and in the same language the user uses.
```

推荐实现选择：

Option A，最小改动：

- 在 CareClaw 分支上直接更新 `ai_engine.c` 里的 `SYSTEM_PROMPT`。
- 如果这个分支已经是产品化分支，这是可接受的。
- 这是交接时风险最低的改法。

Option B，更干净的 profile：

- 增加类似 `product_profile=rtclaw|careclaw` 的编译期产品 profile option。
- 构建时选择 rt-claw 或 CareClaw prompt。
- 工作量略大，但可以避免永久丢失 rt-claw 身份。

这个分支建议先用 Option A，除非维护者明确希望一个 binary 同时支持多个产品 profile。

### 2. 内置 AI skill prompt 文案

当前触点：

```text
claw/services/ai/ai_skill.c
```

内置 `greet` skill 当前包含：

```text
You are rt-claw on an embedded RTOS device.
```

只修改用户可见 skill 文案，不改变 skill framework 行为。

推荐第一阶段更新为：

```text
You are CareClaw, a warm embedded AI companion on Raspberry Pi 3.
Greet the user gently and briefly describe that you can chat, listen, and help with simple local device interactions.
```

不要重命名 `ai_skill_*` API 或 skill 子系统。

### 3. 启动 banner 和 Linux runtime 标题

当前触点：

```text
claw/init.c
platform/linux/main.c
```

当前用户可见字符串包括：

```text
RT-Claw v%s
rt-claw: Linux native - Real-Time Claw
```

第一阶段建议：

- 如果这个分支已经是 CareClaw-only，可以把 Linux 用户可见启动字符串改成 CareClaw。
- 不要重命名 `RT_CLAW_VERSION`、库名、Meson targets 或源码目录。

示例：

```text
CareClaw v%s
careclaw: Raspberry Pi 3 embedded AI companion
```

如果维护者希望保留上游身份，则可以和未来的 `product_profile` option 一起 gate。

### 4. AI API 配置

第一阶段使用现有环境变量。不要新增 secret 机制。

当前配置路径：

```text
RTCLAW_AI_API_KEY
RTCLAW_AI_API_URL
RTCLAW_AI_MODEL
```

当前代码路径：

```text
meson_options.txt
claw_config.h
claw_gen_config.h.in
claw/services/ai/ai_engine.c
claw/shell/shell_commands.c
```

部署时通过 Meson configure 时的环境变量注入 CareClaw API 值：

```bash
export RTCLAW_AI_API_KEY='...'
export RTCLAW_AI_API_URL='...'
export RTCLAW_AI_MODEL='...'
make build-linux
```

如果 key 或 URL 是私有的，不要提交真实值。

后续可选改进：

- 只在 Meson 中增加 `CARECLAW_AI_API_KEY` / `CARECLAW_AI_API_URL` alias。
- 内部仍然映射到 `CONFIG_RTCLAW_AI_*`。
- 这样可以改善产品部署体验，又不改变 runtime internals。

第一阶段不需要做这个。

### 5. Voice style prompt 默认值

当前 voice TTS style prompt 通过 voice runtime config 配置：

```text
tts_style_prompt
```

相关文件：

```text
claw/services/voice/voice_service.c
claw/services/voice/voice_tts.c
claw/shell/shell_commands.c
```

CareClaw 应设置一个温和、平静的默认 TTS 风格。通过 runtime configuration 或部署默认值完成，不要在 `voice_service` 中硬编码 provider-specific 行为。

建议 TTS style prompt：

```text
Speak warmly and calmly, like a patient supportive companion. Keep the tone gentle, natural, and not overly excited.
```

如果使用 MiMo voice/style settings，继续把 provider-specific 请求构造留在 `voice_tts.c` 中，就像现在一样。

### 6. Web/local voice 用户可见标签

潜在触点：

```text
website/voice.html
platform/linux/web_voice_server.c
platform/linux/local_voice_endpoint.c
```

第一阶段建议：

- 只有当 Raspberry Pi demo 使用 web endpoint 时，才修改可见页面标题或标签。
- 当前目标是 local Pi3，所以这是可选项。
- 不要为了品牌化修改 web endpoint 协议字段名。

### 7. Shell 命令名

第一阶段不要重命名 shell 命令。

保留：

```text
/voice_enable
/voice_set
/voice_local
/ai_set
```

理由：

- 它们是开发/调试控制命令。
- 面向用户的操作应该转移到 GPIO 按钮和语音交互。
- 重命名命令会产生 churn，但产品收益很小。

如果后续需要，可以增加 alias，而不是替换现有命令。

## 第一阶段不要重命名的文件/标识

不要重命名：

```text
claw/
osal/
include/claw/
RT_CLAW_VERSION
CONFIG_RTCLAW_*
rtclaw Meson targets
claw_* APIs
voice_service / voice_endpoint / voice_tts module names
```

这些是结构性标识。重命名会造成大范围 churn，并可能破坏跨平台构建。

## 建议的文件级改动列表

最小 CareClaw 分支适配：

1. `claw/services/ai/ai_engine.c`
   - 把 `SYSTEM_PROMPT` 更新为 CareClaw 支持性陪伴人格。
   - 保留 tool awareness 和跟随用户语言。
   - 加入轻量安全边界。

2. `claw/services/ai/ai_skill.c`
   - 把内置 `greet` skill 文案从 rt-claw 改为 CareClaw。
   - 不改变 skill 注册机制。

3. `claw/init.c`
   - 可选：把 banner 文案改成 CareClaw。
   - 保持 version macro 和 init 逻辑不变。

4. `platform/linux/main.c`
   - 可选：把 Linux startup print 改成 CareClaw/Pi3 文案。
   - 不改变 platform startup sequence。

5. 仅部署/环境配置
   - 为 CareClaw 配置 `RTCLAW_AI_API_KEY`、`RTCLAW_AI_API_URL`、`RTCLAW_AI_MODEL`。
   - 配置 local endpoint 和温和 TTS style 的 voice defaults。

除非产品 demo 明确需要，否则不要改其他内容。

## 后续可选的 profile-based 设计

如果这个分支需要继续跟踪上游 rt-claw，同时支持 CareClaw，后续可以增加 profile 抽象。

建议 Meson option：

```meson
option('product_profile', type: 'combo', choices: ['rtclaw', 'careclaw'],
    value: 'rtclaw', description: 'Product personality/profile')
```

生成 define：

```c
#define CONFIG_RTCLAW_PRODUCT_PROFILE_CARECLAW
```

然后在一个小的 profile header/source 中选择字符串：

```text
include/claw/product_profile.h
claw/product_profile.c
```

潜在 API：

```c
const char *claw_product_name(void);
const char *claw_product_system_prompt(void);
const char *claw_product_greet_prompt(void);
```

这比直接改 prompt 更干净，但侵入性更高。除非维护者需要一个代码库同时支持 rt-claw 和 CareClaw，否则不要从这里开始。

## Raspberry Pi 3 部署说明

预期 Pi3 runtime stack：

- Linux native build。
- 使用 ALSA tools (`arecord`/`aplay`) 的 local voice endpoint。
- 通过环境变量配置 CareClaw AI API。
- 可选：来自 `VOICE_PI3_HANDOFF_PLAN.md` 的 GPIO 按钮集成。
- 可选：来自 `VOICE_PI3_HANDOFF_PLAN.md` 的 expression display tool。

示例构建环境：

```bash
export RTCLAW_AI_API_KEY='careclaw-key-from-secure-place'
export RTCLAW_AI_API_URL='careclaw-api-url'
export RTCLAW_AI_MODEL='careclaw-model'
make build-linux
```

不要提交 secrets。使用 shell 环境、systemd environment file，或其他被 git 排除的本地 secret 机制。

systemd 部署可以使用环境文件，例如：

```text
/etc/careclaw/careclaw.env
```

service 示例可以引用这个文件，但真实 secret 文件不能放入仓库。

## 交接用安全和语气指导

第一阶段目标不是认证医疗设备或临床治疗系统。

Assistant 应该：

- 倾听和复述。
- 温和追问。
- 提供 grounding 或 journaling 风格的小建议。
- 在适当时鼓励用户联系可信任的人。
- 避免诊断和治疗承诺。
- 保持适合语音播放的回答长度。

轻量危机场景话术就够了：

```text
If you might hurt yourself or someone else, please contact local emergency services or a trusted person nearby right now.
```

不要在每条回复里加很长的免责声明。

## 测试计划

prompt/branding 修改后：

```bash
make build-linux
make test-unit-linux
scripts/check-patch.sh --file claw/services/ai/ai_engine.c
scripts/check-patch.sh --file claw/services/ai/ai_skill.c
```

如果改了 banner 字符串：

```bash
scripts/check-patch.sh --file claw/init.c
scripts/check-patch.sh --file platform/linux/main.c
```

Pi3 手动验证：

1. 在 Raspberry Pi 3 上启动 CareClaw。
2. 确认预期的启动/用户可见文本显示 CareClaw。
3. 确认 AI API 使用来自环境变量的 CareClaw key/url/model。
4. 问一个中性问题，确认风格温暖且简短。
5. 问一个压力支持类问题，确认语气支持性但不临床化。
6. 请求诊断或用药建议，确认不会给医疗承诺。
7. 分别用中文和英文提问，确认跟随用户语言。
8. 运行 local voice 路径，确认 TTS 语气/style 保持平静。

## 明确不做

- 不重命名整个仓库或 core `claw` APIs。
- 第一阶段不把 Meson targets 从 `rtclaw` 改名。
- 不改变 OSAL/platform 边界。
- 不把 CareClaw persona 耦合到 voice endpoint 逻辑。
- 不把 GPIO 或 display 代码放进 AI prompt 代码。
- 不提交 API keys、私有 URLs 或 Raspberry Pi 本地 secrets。
- 不在每条回复里加入很重的医疗免责声明。
- 第一版不实现单独的 crisis detection classifier。

## 推荐交接总结

告诉下一位贡献者：

1. 把 CareClaw 当作叠在 rt-claw 上的产品人格/profile，而不是结构性 fork。
2. 从修改 `SYSTEM_PROMPT` 和内置 greet 文案开始。
3. 保持 API key/url/model 通过现有 `RTCLAW_AI_*` 环境变量注入。
4. Pi3 硬件集成放在 `platform/linux`，并遵循 `VOICE_PI3_HANDOFF_PLAN.md`。
5. 第一阶段保持小、可构建、可回退。
