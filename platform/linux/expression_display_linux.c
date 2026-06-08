/* SPDX-License-Identifier: MIT */

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>

#include "osal/claw_os.h"
#include "platform/expression_display.h"

#define TAG "expr_disp"

#ifndef CONFIG_RTCLAW_EXPRESSION_IPC
#define CONFIG_RTCLAW_EXPRESSION_IPC "/tmp/rtclaw-expression.sock"
#endif

#define EXPR_WINDOW_SCRIPT "platform/linux/expression_window.py"
#define EXPR_ASSETS_DIR    "assets/expressions"

static char s_current_expression[32];
static pid_t s_window_pid = -1;

claw_err_t platform_expression_set(const char *name)
{
    if (!name) {
        return CLAW_ERROR;
    }

    /* Validate expression enum */
    static const char *valid_expressions[] = {
        "idle", "happy", "thinking", "sad", "listening", "speaking", NULL
    };

    int i;
    int valid = 0;

    for (i = 0; valid_expressions[i]; i++) {
        if (strcmp(name, valid_expressions[i]) == 0) {
            valid = 1;
            break;
        }
    }

    if (!valid) {
        CLAW_LOGW(TAG, "invalid expression: %s", name);
        return CLAW_ERROR;
    }

    /* Notify expression window via Unix domain socket */
    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock < 0) {
        CLAW_LOGW(TAG, "socket create failed: %s", strerror(errno));
        return CLAW_ERROR;
    }

    struct sockaddr_un addr = {
        .sun_family = AF_UNIX,
    };
    strncpy(addr.sun_path, CONFIG_RTCLAW_EXPRESSION_IPC,
            sizeof(addr.sun_path) - 1);

    if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        CLAW_LOGW(TAG, "connect to expression window failed: %s",
                  strerror(errno));
        close(sock);
        return CLAW_ERROR;
    }

    char cmd[64];
    snprintf(cmd, sizeof(cmd), "set %s\n", name);
    ssize_t sent = send(sock, cmd, strlen(cmd), 0);
    close(sock);

    if (sent < 0) {
        CLAW_LOGW(TAG, "send expression command failed: %s",
                  strerror(errno));
        return CLAW_ERROR;
    }

    snprintf(s_current_expression, sizeof(s_current_expression),
             "%s", name);
    CLAW_LOGI(TAG, "expression set to: %s", name);
    return CLAW_OK;
}

const char *platform_expression_current(void)
{
    return s_current_expression[0] ? s_current_expression : NULL;
}

int platform_expression_launch(void)
{
    pid_t pid;

    if (s_window_pid > 0) {
        CLAW_LOGI(TAG, "expression window already running (pid=%d)",
                  s_window_pid);
        return CLAW_OK;
    }

    CLAW_LOGI(TAG, "launching expression window: script=%s assets=%s",
              EXPR_WINDOW_SCRIPT, EXPR_ASSETS_DIR);

    pid = fork();
    if (pid < 0) {
        CLAW_LOGW(TAG, "fork for expression window failed: %s",
                  strerror(errno));
        return CLAW_ERR_IO;
    }
    if (pid == 0) {
        int devnull = open("/dev/null", O_WRONLY);
        int max_fd;
        int fd;

        if (devnull >= 0) {
            dup2(devnull, STDOUT_FILENO);
            dup2(STDERR_FILENO, STDOUT_FILENO);
            close(devnull);
        }
        /* Close inherited fds beyond stderr so the Python window
           does not hold CURL sockets or other parent resources. */
        max_fd = (int)sysconf(_SC_OPEN_MAX);
        if (max_fd <= 0 || max_fd > 4096) {
            max_fd = 4096;
        }
        for (fd = 3; fd < max_fd; fd++) {
            close(fd);
        }
        execlp("python3", "python3", EXPR_WINDOW_SCRIPT,
               "--assets", EXPR_ASSETS_DIR,
               "--ipc", CONFIG_RTCLAW_EXPRESSION_IPC,
               NULL);
        _exit(127);
    }

    s_window_pid = pid;
    CLAW_LOGI(TAG, "expression window launched (pid=%d)", pid);
    return CLAW_OK;
}

void platform_expression_shutdown(void)
{
    if (s_window_pid <= 0) {
        return;
    }

    kill(s_window_pid, SIGTERM);
    waitpid(s_window_pid, NULL, 0);
    CLAW_LOGI(TAG, "expression window stopped (pid=%d)", s_window_pid);
    s_window_pid = -1;
    unlink(CONFIG_RTCLAW_EXPRESSION_IPC);
}
