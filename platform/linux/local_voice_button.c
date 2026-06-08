/* SPDX-License-Identifier: MIT */

#include "osal/claw_os.h"
#include "platform/linux/local_voice_button.h"
#include "platform/linux/local_voice_endpoint.h"

#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/gpio.h>

#define TAG "voice_btn"

#ifndef CONFIG_RTCLAW_VOICE_BUTTON_GPIOCHIP
#define CONFIG_RTCLAW_VOICE_BUTTON_GPIOCHIP "/dev/gpiochip0"
#endif

#ifndef CONFIG_RTCLAW_VOICE_BUTTON_LINE
#define CONFIG_RTCLAW_VOICE_BUTTON_LINE 17
#endif

#ifndef CONFIG_RTCLAW_VOICE_BUTTON_ACTIVE_LOW
#define CONFIG_RTCLAW_VOICE_BUTTON_ACTIVE_LOW 1
#endif

#ifndef CONFIG_RTCLAW_VOICE_BUTTON_DEBOUNCE_MS
#define CONFIG_RTCLAW_VOICE_BUTTON_DEBOUNCE_MS 50
#endif

struct local_voice_button_ctx {
    int running;
    int chip_fd;
    int line_fd;
    struct claw_thread *thread;
};

static struct local_voice_button_ctx s_button = {
    .chip_fd = -1,
    .line_fd = -1,
};

static int button_read_value(int line_fd)
{
    struct gpiohandle_data data;
    int ret;

    ret = ioctl(line_fd, GPIOHANDLE_GET_LINE_VALUES_IOCTL, &data);
    if (ret < 0) {
        CLAW_LOGW(TAG, "gpio read failed: %d", errno);
        return -1;
    }
    return data.values[0];
}

static void local_voice_button_thread(void *arg)
{
    int last_value = -1;
    int stable_count = 0;
    int prev_stable = 0;  /* last debounced state: 0=released, 1=pressed */
    int debounce_ticks;
    int value;

    (void)arg;

    debounce_ticks = (CONFIG_RTCLAW_VOICE_BUTTON_DEBOUNCE_MS + 9) / 10;

    while (!claw_thread_should_exit()) {
        value = button_read_value(s_button.line_fd);
        if (value < 0) {
            claw_thread_delay_ms(10);
            continue;
        }

        if (value == last_value) {
            stable_count++;
        } else {
            stable_count = 0;
            last_value = value;
        }

        /* Kernel GPIOHANDLE_REQUEST_ACTIVE_LOW already handles polarity:
           physical LOW → logical 1 (active).  Just check value == 1. */
        if (stable_count == debounce_ticks) {
            int pressed = (value == 1);

            /* Edge: released → pressed fires once per press */
            if (pressed && !prev_stable) {
                CLAW_LOGI(TAG, "button pressed, toggling capture");
                int ret = local_voice_endpoint_capture_toggle();
                if (ret != CLAW_OK) {
                    CLAW_LOGW(TAG, "toggle failed: %d", ret);
                }
            }
            prev_stable = pressed;
        }

        claw_thread_delay_ms(10);
    }

    CLAW_LOGI(TAG, "button thread exited");
}

int local_voice_button_init(void)
{
    struct gpiochip_info chip_info;
    struct gpiohandle_request req;
    int ret;

    if (s_button.chip_fd >= 0) {
        CLAW_LOGI(TAG, "already initialized");
        return CLAW_OK;
    }

    CLAW_LOGI(TAG, "opening %s line %d (active_low=%d debounce=%dms)",
              CONFIG_RTCLAW_VOICE_BUTTON_GPIOCHIP,
              CONFIG_RTCLAW_VOICE_BUTTON_LINE,
              CONFIG_RTCLAW_VOICE_BUTTON_ACTIVE_LOW,
              CONFIG_RTCLAW_VOICE_BUTTON_DEBOUNCE_MS);

    s_button.chip_fd = open(CONFIG_RTCLAW_VOICE_BUTTON_GPIOCHIP, O_RDONLY);
    if (s_button.chip_fd < 0) {
        CLAW_LOGW(TAG, "failed to open %s: %d",
                  CONFIG_RTCLAW_VOICE_BUTTON_GPIOCHIP, errno);
        return CLAW_ERR_IO;
    }

    ret = ioctl(s_button.chip_fd, GPIO_GET_CHIPINFO_IOCTL, &chip_info);
    if (ret < 0) {
        CLAW_LOGW(TAG, "failed to get chip info: %d", errno);
        close(s_button.chip_fd);
        s_button.chip_fd = -1;
        return CLAW_ERR_IO;
    }

    memset(&req, 0, sizeof(req));
    req.lineoffsets[0] = CONFIG_RTCLAW_VOICE_BUTTON_LINE;
    req.flags = GPIOHANDLE_REQUEST_INPUT
              | GPIOHANDLE_REQUEST_BIAS_PULL_UP;
    if (CONFIG_RTCLAW_VOICE_BUTTON_ACTIVE_LOW) {
        req.flags |= GPIOHANDLE_REQUEST_ACTIVE_LOW;
    }
    strncpy(req.consumer_label, "rtclaw-voice-btn",
            sizeof(req.consumer_label) - 1);
    req.lines = 1;

    ret = ioctl(s_button.chip_fd, GPIO_GET_LINEHANDLE_IOCTL, &req);
    if (ret < 0) {
        CLAW_LOGW(TAG, "failed to request line %d: %d",
                  CONFIG_RTCLAW_VOICE_BUTTON_LINE, errno);
        close(s_button.chip_fd);
        s_button.chip_fd = -1;
        return CLAW_ERR_IO;
    }

    s_button.line_fd = req.fd;

    CLAW_LOGI(TAG, "initialized: chip=%s line=%d active_low=%d",
              CONFIG_RTCLAW_VOICE_BUTTON_GPIOCHIP,
              CONFIG_RTCLAW_VOICE_BUTTON_LINE,
              CONFIG_RTCLAW_VOICE_BUTTON_ACTIVE_LOW);
    return CLAW_OK;
}

int local_voice_button_start(void)
{
    if (s_button.running) {
        return CLAW_OK;
    }
    if (s_button.line_fd < 0) {
        return CLAW_ERR_STATE;
    }

    s_button.running = 1;
    s_button.thread = claw_thread_create("voice_btn",
                                         local_voice_button_thread,
                                         NULL, 4096, 30);
    if (!s_button.thread) {
        s_button.running = 0;
        CLAW_LOGW(TAG, "failed to create thread");
        return CLAW_ERR_NOMEM;
    }

    CLAW_LOGI(TAG, "monitor started");
    return CLAW_OK;
}

void local_voice_button_stop(void)
{
    if (!s_button.running) {
        return;
    }

    s_button.running = 0;
    if (s_button.thread) {
        claw_thread_delete(s_button.thread);
        s_button.thread = NULL;
    }
    if (s_button.line_fd >= 0) {
        close(s_button.line_fd);
        s_button.line_fd = -1;
    }
    if (s_button.chip_fd >= 0) {
        close(s_button.chip_fd);
        s_button.chip_fd = -1;
    }

    CLAW_LOGI(TAG, "stopped");
}

int local_voice_button_running(void)
{
    return s_button.running;
}
