/*
 * Copyright (c) 2026, Chao Liu <chao.liu.zevorn@gmail.com>
 * SPDX-License-Identifier: MIT
 *
 * OSAL Key-Value storage for Zephyr RTOS.
 * Uses Zephyr Settings subsystem over NVS backend.
 * Reads use settings_load_subtree_direct() for one-shot lookups.
 */

#include "osal/claw_kv.h"
#include "osal/claw_os.h"

#include <zephyr/kernel.h>
#include <zephyr/settings/settings.h>
#include <zephyr/logging/log.h>

#include <stdio.h>
#include <string.h>

LOG_MODULE_REGISTER(claw_kv, LOG_LEVEL_INF);

#define KV_PATH_MAX  64

static int s_initialized;
static struct claw_mutex *s_kv_lock;

/* --- one-shot read context --- */

struct kv_read_ctx {
    void   *dest;
    size_t  dest_size;
    size_t  read_len;
    int     found;
};

static int kv_direct_load_cb(const char *key, size_t len,
                              settings_read_cb read_cb, void *cb_arg,
                              void *param)
{
    struct kv_read_ctx *ctx = param;

    (void)key;

    size_t to_read = len;

    if (to_read > ctx->dest_size) {
        to_read = ctx->dest_size;
    }

    int rc = read_cb(cb_arg, ctx->dest, to_read);

    if (rc >= 0) {
        ctx->read_len = (size_t)rc;
        ctx->found = 1;
    }

    return 0;
}

/* --- helpers --- */

static int build_path(char *out, size_t out_size,
                      const char *ns, const char *key)
{
    int n = snprintf(out, out_size, "%s/%s", ns, key);

    if (n < 0 || (size_t)n >= out_size) {
        return CLAW_ERR_INVALID;
    }
    return CLAW_OK;
}

static int kv_read(const char *path, void *data, size_t size,
                    size_t *out_len)
{
    struct kv_read_ctx ctx = {
        .dest      = data,
        .dest_size = size,
        .read_len  = 0,
        .found     = 0,
    };

    claw_mutex_lock(s_kv_lock, CLAW_WAIT_FOREVER);

    int ret = settings_load_subtree_direct(path,
                                            kv_direct_load_cb, &ctx);

    claw_mutex_unlock(s_kv_lock);

    if (ret < 0 || !ctx.found) {
        return CLAW_ERR_NOENT;
    }

    if (out_len) {
        *out_len = ctx.read_len;
    }
    return CLAW_OK;
}

/* --- public API --- */

int claw_kv_init(void)
{
    if (s_initialized) {
        return CLAW_OK;
    }

    s_kv_lock = claw_mutex_create("kv_lock");
    if (!s_kv_lock) {
        LOG_ERR("failed to create KV mutex");
        return CLAW_ERR_NOMEM;
    }

    int ret = settings_subsys_init();

    if (ret) {
        LOG_ERR("settings_subsys_init failed: %d", ret);
        return CLAW_ERROR;
    }

    s_initialized = 1;
    return CLAW_OK;
}

int claw_kv_set_str(const char *ns, const char *key, const char *value)
{
    char path[KV_PATH_MAX];

    if (build_path(path, sizeof(path), ns, key) != CLAW_OK) {
        return CLAW_ERR_INVALID;
    }

    int ret = settings_save_one(path, value, strlen(value) + 1);

    return (ret == 0) ? CLAW_OK : CLAW_ERROR;
}

int claw_kv_get_str(const char *ns, const char *key,
                     char *buf, size_t size)
{
    char path[KV_PATH_MAX];

    if (build_path(path, sizeof(path), ns, key) != CLAW_OK) {
        return CLAW_ERR_INVALID;
    }

    size_t read_len = 0;
    int ret = kv_read(path, buf, size, &read_len);

    if (ret != CLAW_OK) {
        return ret;
    }

    if (read_len < size) {
        buf[read_len] = '\0';
    } else if (size > 0) {
        buf[size - 1] = '\0';
    }

    return CLAW_OK;
}

int claw_kv_set_blob(const char *ns, const char *key,
                      const void *data, size_t len)
{
    char path[KV_PATH_MAX];

    if (build_path(path, sizeof(path), ns, key) != CLAW_OK) {
        return CLAW_ERR_INVALID;
    }

    int ret = settings_save_one(path, data, len);

    return (ret == 0) ? CLAW_OK : CLAW_ERROR;
}

int claw_kv_get_blob(const char *ns, const char *key,
                      void *data, size_t *len)
{
    char path[KV_PATH_MAX];

    if (build_path(path, sizeof(path), ns, key) != CLAW_OK) {
        return CLAW_ERR_INVALID;
    }

    return kv_read(path, data, *len, len);
}

int claw_kv_set_u8(const char *ns, const char *key, uint8_t val)
{
    char path[KV_PATH_MAX];

    if (build_path(path, sizeof(path), ns, key) != CLAW_OK) {
        return CLAW_ERR_INVALID;
    }

    int ret = settings_save_one(path, &val, sizeof(val));

    return (ret == 0) ? CLAW_OK : CLAW_ERROR;
}

int claw_kv_get_u8(const char *ns, const char *key, uint8_t *val)
{
    char path[KV_PATH_MAX];

    if (build_path(path, sizeof(path), ns, key) != CLAW_OK) {
        return CLAW_ERR_INVALID;
    }

    return kv_read(path, val, sizeof(*val), NULL);
}

int claw_kv_delete(const char *ns, const char *key)
{
    char path[KV_PATH_MAX];

    if (build_path(path, sizeof(path), ns, key) != CLAW_OK) {
        return CLAW_ERR_INVALID;
    }

    int ret = settings_delete(path);

    return (ret == 0) ? CLAW_OK : CLAW_ERROR;
}

int claw_kv_erase_ns(const char *ns)
{
    (void)ns;
    return CLAW_ERR_NOENT;
}
