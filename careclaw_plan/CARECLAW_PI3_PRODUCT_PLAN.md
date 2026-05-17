# CareClaw Raspberry Pi 3 Product Handoff Plan

## Confirmed scope

CareClaw is a Raspberry Pi 3 embedded AI companion focused on supportive psychological counseling style conversation.

First-stage scope is intentionally small:

- Change runtime personality and user-facing tone.
- Use the existing AI API configuration mechanism with CareClaw API key, URL, and model supplied by environment variables.
- Keep the existing rt-claw codebase structure and service boundaries.
- Do not rename core directories, public prefixes, OSAL names, or internal service architecture.
- Do not make a broad rebrand pass over the whole repository.
- Do not turn the first phase into a medical/clinical product redesign.

This document is for handoff. It should guide a future contributor toward a focused product-style adaptation without polluting the underlying rt-claw architecture.

## Relationship to existing Pi3 voice handoff plan

`careclaw_plan/VOICE_PI3_HANDOFF_PLAN.md` already defines important boundaries for local voice input and expression display:

- GPIO button handling belongs under `platform/linux`, not in `voice_service`.
- Local voice button code should reuse `local_voice_endpoint_capture_start/stop/toggle` APIs, not call shell commands.
- Display hardware details belong in platform display code, not in voice service or AI prompt logic.
- Expression changes should be an AI-callable tool registered through `CLAW_TOOL_REGISTER`, not hardcoded into the voice flow.
- First version should avoid automatic voice-state-to-expression coupling.

This CareClaw plan follows the same boundary style:

- Product personality belongs in AI prompt/configuration surfaces.
- Platform behavior belongs in `platform/linux`.
- Voice transport and STT/TTS remain endpoint/provider abstractions.
- CareClaw-specific product defaults should be layered as configuration/profile choices, not scattered through core services.

## Product direction

CareClaw should feel like:

- Warm and patient.
- Supportive rather than command-and-control.
- Short enough for voice interaction.
- Calm when the user is distressed.
- Able to ask gentle follow-up questions.
- Clear that it is an AI companion, not a doctor or emergency service.

Because the first version is light-touch, use gentle safety wording rather than a heavy legal/medical disclaimer.

Suggested behavioral constraints:

- Do not diagnose mental illness.
- Do not claim to provide professional therapy.
- Do not prescribe medication or treatment.
- If the user appears to be in immediate danger or at risk of self-harm, encourage contacting trusted people or local emergency support.
- Prefer reflective listening, grounding suggestions, and small next-step questions.
- Keep responses concise for voice playback.
- Respond in the user's language.

## Recommended first-stage implementation strategy

Prefer a CareClaw runtime profile over broad code renaming.

The project is still structurally rt-claw. CareClaw should be a product profile on top of it:

```text
rt-claw core/runtime        remains unchanged
CareClaw product profile    changes persona/defaults/user-facing tone
Raspberry Pi 3 platform     hosts local voice/button/display integrations
```

This avoids breaking existing build logic, docs, tests, service registration, and OSAL boundaries.

## Key touchpoints to modify or wrap

### 1. AI system prompt

Primary current touchpoint:

```text
claw/services/ai/ai_engine.c
```

The current base prompt is embedded as `SYSTEM_PROMPT` and describes the assistant as rt-claw on an embedded RTOS device.

First-stage target:

- Replace or profile-gate the base prompt so CareClaw uses counseling companion wording.
- Keep hardware/tool awareness, because CareClaw still runs on embedded hardware and may call local tools.
- Keep the response language rule.
- Add light safety guidance.

Recommended CareClaw prompt content:

```text
You are CareClaw, a warm and supportive AI companion running on a Raspberry Pi 3 embedded device.
You help users reflect on feelings, reduce stress, and take small constructive next steps.
You are not a doctor, therapist, or emergency service, and you should not diagnose conditions or prescribe treatment.
If the user may be in immediate danger or at risk of self-harm, gently encourage contacting trusted people or local emergency support.
Use available tools only when helpful for the local device experience.
Keep replies concise for voice interaction, empathetic, and in the same language the user uses.
```

Recommended implementation choices:

Option A, smallest change:

- Directly update `SYSTEM_PROMPT` in `ai_engine.c` on the CareClaw branch.
- This is acceptable if the branch is now product-specific.
- It is the lowest-risk change for a handoff.

Option B, cleaner profile:

- Add a compile-time product profile option such as `product_profile=rtclaw|careclaw`.
- Select between rt-claw and CareClaw prompts at build time.
- Slightly more work but avoids permanent loss of rt-claw identity.

For this branch, start with Option A unless maintainers explicitly want one binary to support multiple product profiles.

### 2. Built-in AI skill prompt text

Current touchpoint:

```text
claw/services/ai/ai_skill.c
```

The built-in `greet` skill currently says:

```text
You are rt-claw on an embedded RTOS device.
```

Change only user-facing skill text, not skill framework behavior.

Recommended first-stage update:

```text
You are CareClaw, a warm embedded AI companion on Raspberry Pi 3.
Greet the user gently and briefly describe that you can chat, listen, and help with simple local device interactions.
```

Do not rename `ai_skill_*` APIs or the skill subsystem.

### 3. Startup banner and Linux runtime title

Current touchpoints:

```text
claw/init.c
platform/linux/main.c
```

Current user-visible strings include:

```text
RT-Claw v%s
rt-claw: Linux native - Real-Time Claw
```

First-stage recommendation:

- If this branch is now CareClaw-only, change Linux user-visible startup strings to CareClaw.
- Do not rename `RT_CLAW_VERSION`, library names, Meson targets, or source directories.

Example:

```text
CareClaw v%s
careclaw: Raspberry Pi 3 embedded AI companion
```

If maintainers want to preserve upstream identity, gate this behind the same future `product_profile` option.

### 4. AI API configuration

Use existing environment variables. Do not add a new secret mechanism for first stage.

Current configuration path:

```text
RTCLAW_AI_API_KEY
RTCLAW_AI_API_URL
RTCLAW_AI_MODEL
```

Current code paths:

```text
meson_options.txt
claw_config.h
claw_gen_config.h.in
claw/services/ai/ai_engine.c
claw/shell/shell_commands.c
```

Deployment should inject CareClaw API values through environment variables at Meson configure time:

```bash
export RTCLAW_AI_API_KEY='...'
export RTCLAW_AI_API_URL='...'
export RTCLAW_AI_MODEL='...'
make build-linux
```

Do not commit real API keys or URLs if they are private.

Optional later improvement:

- Add `CARECLAW_AI_API_KEY` / `CARECLAW_AI_API_URL` aliases in Meson only.
- Internally still map them to `CONFIG_RTCLAW_AI_*`.
- This would improve product deployment ergonomics without changing runtime internals.

First stage does not need this.

### 5. Voice style prompt defaults

Current voice TTS style prompt is configured through voice runtime config:

```text
tts_style_prompt
```

Relevant files:

```text
claw/services/voice/voice_service.c
claw/services/voice/voice_tts.c
claw/shell/shell_commands.c
```

For CareClaw, set a default TTS style that is gentle and calm. Do this through runtime configuration or deployment defaults, not by hardcoding provider-specific behavior in `voice_service`.

Suggested TTS style prompt:

```text
Speak warmly and calmly, like a patient supportive companion. Keep the tone gentle, natural, and not overly excited.
```

If MiMo voice/style settings are used, keep provider-specific request construction inside `voice_tts.c`, as it is today.

### 6. Web/local voice user-facing labels

Potential touchpoints:

```text
website/voice.html
platform/linux/web_voice_server.c
platform/linux/local_voice_endpoint.c
```

First-stage recommendation:

- Only change visible page title or labels if the Raspberry Pi demo uses the web endpoint.
- The current target is local Pi3, so this is optional.
- Do not alter web endpoint protocol names just for branding.

### 7. Shell command names

Do not rename shell commands in the first stage.

Keep:

```text
/voice_enable
/voice_set
/voice_local
/ai_set
```

Rationale:

- They are developer/debug controls.
- User-facing operation should move to the GPIO button and voice interaction.
- Renaming commands creates churn with little product benefit.

If desired later, add aliases rather than replacing existing commands.

## Files not to rename in first stage

Do not rename:

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

These are structural identifiers. Renaming them would create broad churn and risk breaking cross-platform builds.

## Proposed file-level change list

Minimal CareClaw branch adaptation:

1. `claw/services/ai/ai_engine.c`
   - Update `SYSTEM_PROMPT` to CareClaw supportive companion persona.
   - Keep tool awareness and same-language behavior.
   - Add light safety boundary.

2. `claw/services/ai/ai_skill.c`
   - Update built-in `greet` skill wording from rt-claw to CareClaw.
   - Do not change skill registration mechanics.

3. `claw/init.c`
   - Optionally change banner text to CareClaw.
   - Keep version macro and init logic unchanged.

4. `platform/linux/main.c`
   - Optionally change Linux startup print to CareClaw/Pi3 wording.
   - Do not change platform startup sequence.

5. Deployment/environment only
   - Configure `RTCLAW_AI_API_KEY`, `RTCLAW_AI_API_URL`, `RTCLAW_AI_MODEL` for CareClaw.
   - Configure voice defaults for local endpoint and gentle TTS style.

Avoid changing anything else unless the product demo specifically needs it.

## Optional profile-based design for later

If this branch needs to continue tracking upstream rt-claw while supporting CareClaw, add a profile abstraction later.

Suggested Meson option:

```meson
option('product_profile', type: 'combo', choices: ['rtclaw', 'careclaw'],
    value: 'rtclaw', description: 'Product personality/profile')
```

Generated define:

```c
#define CONFIG_RTCLAW_PRODUCT_PROFILE_CARECLAW
```

Then select strings in a small profile header/source:

```text
include/claw/product_profile.h
claw/product_profile.c
```

Potential API:

```c
const char *claw_product_name(void);
const char *claw_product_system_prompt(void);
const char *claw_product_greet_prompt(void);
```

This is cleaner but more invasive than direct prompt updates. Do not start here unless maintainers want both rt-claw and CareClaw from one codebase.

## Raspberry Pi 3 deployment notes

Expected Pi3 runtime stack:

- Linux native build.
- Local voice endpoint using ALSA tools (`arecord`/`aplay`).
- CareClaw AI API configured by environment variables.
- Optional GPIO button integration from `VOICE_PI3_HANDOFF_PLAN.md`.
- Optional expression display tool from `VOICE_PI3_HANDOFF_PLAN.md`.

Example build environment:

```bash
export RTCLAW_AI_API_KEY='careclaw-key-from-secure-place'
export RTCLAW_AI_API_URL='careclaw-api-url'
export RTCLAW_AI_MODEL='careclaw-model'
make build-linux
```

Do not commit secrets. Use shell environment, systemd environment file, or another local secret mechanism excluded from git.

For systemd deployment, use an environment file such as:

```text
/etc/careclaw/careclaw.env
```

Example service should reference that file, but the actual secret file must not be stored in the repository.

## Safety and tone guidance for handoff

This is not intended to be a certified medical device or clinical therapy system in the first phase.

The assistant should:

- Listen and reflect.
- Ask gentle follow-up questions.
- Offer grounding or journaling-style suggestions.
- Encourage reaching out to trusted people when appropriate.
- Avoid diagnosis and treatment claims.
- Keep answers suitable for voice playback.

Light crisis wording is enough for now:

```text
If you might hurt yourself or someone else, please contact local emergency services or a trusted person nearby right now.
```

Do not add a long disclaimer to every response.

## Testing plan

After prompt/branding changes:

```bash
make build-linux
make test-unit-linux
scripts/check-patch.sh --file claw/services/ai/ai_engine.c
scripts/check-patch.sh --file claw/services/ai/ai_skill.c
```

If banner strings are changed:

```bash
scripts/check-patch.sh --file claw/init.c
scripts/check-patch.sh --file platform/linux/main.c
```

Manual Pi3 validation:

1. Boot CareClaw on Raspberry Pi 3.
2. Confirm startup/user-visible text says CareClaw where intended.
3. Confirm AI API uses CareClaw key/url/model from environment.
4. Ask a neutral question and confirm warm concise style.
5. Ask a stress-support question and confirm supportive but non-clinical tone.
6. Ask for diagnosis or medication advice and confirm it avoids medical claims.
7. Ask in Chinese and English and confirm it follows the user's language.
8. Run local voice path and confirm TTS tone/style remains calm.

## Explicit non-goals

- Do not rename the whole repository or core `claw` APIs.
- Do not rename Meson targets from `rtclaw` in the first stage.
- Do not change OSAL/platform boundaries.
- Do not couple CareClaw persona to voice endpoint logic.
- Do not put GPIO or display code inside AI prompt code.
- Do not commit API keys, private URLs, or local Raspberry Pi secrets.
- Do not add a heavy medical disclaimer to every response.
- Do not implement crisis detection as a separate classifier in this first pass.

## Recommended handoff summary

Tell the next contributor:

1. Treat CareClaw as a product personality/profile on top of rt-claw, not a structural fork.
2. Start by changing `SYSTEM_PROMPT` and built-in greet wording.
3. Keep API key/url/model injection through existing `RTCLAW_AI_*` environment variables.
4. Keep Pi3 hardware integration in `platform/linux` and follow `VOICE_PI3_HANDOFF_PLAN.md`.
5. Keep the first pass small, buildable, and reversible.
