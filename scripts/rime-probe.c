/*
 * librime API 探针 —— 验证 Rime 配置是否真正生效。
 *
 * "配置能解析" 不等于 "配置已生效"：必须通过引擎自己的 API 读回
 * 你设置的值，才能证明补丁被正确合并。
 *
 * 用法：
 *   gcc -o rime-probe rime-probe.c /usr/lib/x86_64-linux-gnu/librime.so
 *   ./rime-probe
 *
 * 需要 librime-dev：sudo apt install librime-dev
 */
#include <stdio.h>
#include <string.h>
#include <rime_api.h>

#ifndef TRUE
#define TRUE 1
#endif
#ifndef FALSE
#define FALSE 0
#endif

/* 用户 rime 配置目录，按需修改 */
static const char *USER_DIR = "/home/ubuntu26/.local/share/fcitx5/rime/";

/* 要验证的方案 */
static const char *SCHEMA = "rime_ice";

/* 要检查的候选词 */
static const char *TEST_KEYS = "nihao";

int main(void) {
    RimeApi *rime = rime_get_api();
    if (!rime) {
        fprintf(stderr, "rime_get_api failed\n");
        return 1;
    }

    RIME_STRUCT(RimeTraits, traits);
    traits.shared_data_dir = "/usr/share/rime-data/";
    traits.user_data_dir = USER_DIR;
    traits.distribution_name = "Rime";
    traits.distribution_code_name = "fcitx-rime";
    traits.distribution_version = "5.1.15";
    traits.app_name = "probe";
    rime->setup(&traits);
    rime->initialize(&traits);

    /* 1. 方案列表 */
    RimeSchemaList schemas;
    memset(&schemas, 0, sizeof(schemas));
    if (rime->get_schema_list(&schemas)) {
        printf("=== 方案列表 (%zu) ===\n", schemas.size);
        for (size_t i = 0; i < schemas.size; i++)
            printf("  %s (%s)\n", schemas.list[i].schema_id,
                   schemas.list[i].name ? schemas.list[i].name : "");
        rime->free_schema_list(&schemas);
    }

    /* 2. 打开会话并输入测试串 */
    RimeSessionId session = rime->create_session();
    if (!session) {
        fprintf(stderr, "create_session failed\n");
        return 1;
    }
    rime->select_schema(session, SCHEMA);

    printf("\n=== 输入 '%s' 后的候选状态 ===\n", TEST_KEYS);
    for (const char *p = TEST_KEYS; *p; p++)
        rime->process_key(session, (int)*p, 0);

    RIME_STRUCT(RimeContext, ctx);
    if (rime->get_context(session, &ctx)) {
        printf("PAGE_SIZE      = %d\n", ctx.menu.page_size);
        printf("NUM_CANDIDATES = %d\n", ctx.menu.num_candidates);
        printf("SELECT_KEYS    = %s\n",
               ctx.menu.select_keys ? ctx.menu.select_keys : "(null)  <-- 空则数字键无法选词");
        for (int i = 0; i < ctx.menu.num_candidates && i < 5; i++) {
            RimeCandidate *c = &ctx.menu.candidates[i];
            printf("  CANDIDATE[%d] = %s\n", i, c->text ? c->text : "(null)");
        }
        if (ctx.select_labels) {
            printf("SELECT_LABELS[0] = %s\n",
                   ctx.select_labels[0] ? ctx.select_labels[0] : "(null)");
        } else {
            printf("SELECT_LABELS = (null)\n");
        }
    }

    /* 3. 直接读回配置文件中的键（验证补丁合并） */
    printf("\n=== default.yaml 合并后的键值 ===\n");
    RimeConfig cfg;
    memset(&cfg, 0, sizeof(cfg));
    if (rime->config_open("default", &cfg)) {
        const char *keys[] = {
            "menu/page_size",
            "menu/alternative_select_keys",
            "comment_format/comment_format",
            "inline_preedit",
            NULL,
        };
        for (int i = 0; keys[i]; i++) {
            const char *v = rime->config_get_cstring(&cfg, keys[i]);
            printf("  %-38s = %s\n", keys[i], v ? v : "(null)");
        }
        rime->config_close(&cfg);
    } else {
        printf("  config_open failed\n");
    }

    rime->destroy_session(session);
    rime->finalize();
    return 0;
}
