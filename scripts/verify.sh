#!/usr/bin/env bash
#
# 端到端验证：证明主题真的生效，而不只是"安装脚本说成功了"。
#
# 四项检查：
#   1. 守护进程确实读取了主题文件（strace 追踪，fd >= 0）
#   2. Rime 补丁通过引擎 API 读回确认生效（编译运行 librime 探针）
#   3. 离屏预览 PNG 已生成
#   4. 安装 → 卸载 → 安装 往返正常
#
# 用法：
#   scripts/verify.sh            # 全部检查
#   scripts/verify.sh --no-roundtrip   # 跳过往返测试（不改动当前配置）

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME_FILE="$HOME/.local/share/fcitx5/themes/wechat/theme.conf"
RIME_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fcitx5/rime"
ROUNDTRIP=1

if [ "${1:-}" = "--no-roundtrip" ]; then
    ROUNDTRIP=0
fi

if [ -t 1 ]; then
    C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
    C_BLU=$'\033[34m'; C_BLD=$'\033[1m'; C_RST=$'\033[0m'
else
    C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_BLD=""; C_RST=""
fi
PASS=0; FAIL=0
ok()   { printf '%s\n' "${C_GRN}[✓]${C_RST} $*"; PASS=$((PASS+1)); }
bad()  { printf '%s\n' "${C_RED}[✗]${C_RST} $*" >&2; FAIL=$((FAIL+1)); }
warn() { printf '%s\n' "${C_YEL}[!]${C_RST} $*"; }
info() { printf '%s\n' "${C_BLU}[*]${C_RST} $*"; }

printf '%s\n' "${C_BLD}===== 仿微信输入法主题验证 =====${C_RST}"
echo

# ── 检查 1：守护进程确实读取主题文件 ──────────────────────────
info "检查 1/4：守护进程是否真的读取主题文件"
if [ ! -f "$THEME_FILE" ]; then
    bad "主题文件不存在：$THEME_FILE（请先运行 install.sh）"
else
    TRACE_OUT="$("$REPO_DIR/scripts/trace-config-load.sh" "fcitx5 --replace" \
                 "$THEME_FILE" --timeout 12 2>&1)"
    if echo "$TRACE_OUT" | grep -q "成功打开"; then
        ok "fcitx5 成功打开主题文件"
        echo "$TRACE_OUT" | grep "成功打开" | head -2 | sed 's/^/    /'
    else
        bad "fcitx5 未读取主题文件"
        echo "$TRACE_OUT" | tail -5 | sed 's/^/    /'
    fi
fi
echo

# ── 检查 2：Rime 补丁通过引擎 API 生效 ───────────────────────
info "检查 2/4：Rime 补丁是否通过引擎 API 生效"
if ! dpkg -s librime-dev >/dev/null 2>&1; then
    warn "未安装 librime-dev，跳过（sudo apt install librime-dev）"
else
    PROBE_BIN="$(mktemp -t rime-probe.XXXXXX)"
    LIB="$(ls /usr/lib/*/librime.so /usr/lib/librime.so 2>/dev/null | head -1)"
    if [ -n "$LIB" ] && gcc -o "$PROBE_BIN" "$REPO_DIR/scripts/rime-probe.c" "$LIB" 2>/dev/null; then
        PROBE_OUT="$("$PROBE_BIN" 2>/dev/null | grep -v '^warning')"
        echo "$PROBE_OUT" | sed 's/^/    /'
        # 关键断言：page_size 与 select_keys 必须是补丁后的值
        if echo "$PROBE_OUT" | grep -q "PAGE_SIZE      = 5" \
           && echo "$PROBE_OUT" | grep -q "SELECT_KEYS    = 1234567890"; then
            ok "Rime 补丁已生效（page_size=5, select_keys=1234567890）"
        else
            bad "Rime 补丁未生效"
        fi
    else
        warn "探针编译失败，跳过"
    fi
    rm -f "$PROBE_BIN"
fi
echo

# ── 检查 3：离屏预览已生成 ───────────────────────────────────
info "检查 3/4：离屏预览图"
if [ -f "$REPO_DIR/docs/preview-wechat.png" ]; then
    ok "预览图存在：docs/preview-wechat.png"
else
    bad "预览图缺失，请运行：python3 scripts/preview.py --theme wechat"
fi
if [ -f "$REPO_DIR/docs/preview-wechat-dark.png" ]; then
    ok "深色预览图存在：docs/preview-wechat-dark.png"
else
    warn "深色预览图缺失（可选）"
fi
echo

# ── 检查 4：安装 → 卸载 → 安装 往返 ──────────────────────────
info "检查 4/4：安装 / 卸载往返"
if [ "$ROUNDTRIP" -eq 0 ]; then
    warn "已跳过（--no-roundtrip）"
else
    BEFORE_CONF="$HOME/.config/fcitx5/conf/classicui.conf"
    BACKUP_DIR="$HOME/.local/share/fcitx5/wechat-theme-backups"
    TMP_DIR="$(mktemp -d)"

    # 记录卸载前的状态
    if [ -d "$BACKUP_DIR" ]; then
        cp -a "$BACKUP_DIR/classicui.conf" "$TMP_DIR/orig.conf" 2>/dev/null || true
    fi

    if "$REPO_DIR/install.sh" --uninstall >/dev/null 2>&1; then
        if [ -d "$HOME/.local/share/fcitx5/themes/wechat" ]; then
            bad "卸载后主题目录仍在"
        else
            ok "卸载移除了主题目录"
        fi
        if [ -f "$TMP_DIR/orig.conf" ]; then
            if diff -q "$TMP_DIR/orig.conf" "$BEFORE_CONF" >/dev/null 2>&1; then
                ok "卸载后 classicui.conf 与安装前逐字节一致"
            else
                bad "卸载后配置未正确还原"
                diff "$TMP_DIR/orig.conf" "$BEFORE_CONF" | head -10 | sed 's/^/    /'
            fi
        fi
    else
        bad "卸载命令执行失败"
    fi

    if "$REPO_DIR/install.sh" --light >/dev/null 2>&1; then
        if grep -q "^Theme=wechat" "$BEFORE_CONF" 2>/dev/null; then
            ok "重新安装成功（Theme=wechat）"
        else
            bad "重新安装后主题键未生效"
        fi
    else
        bad "重新安装命令执行失败"
    fi
    rm -rf "$TMP_DIR"
fi

echo
printf '%s\n' "${C_BLD}===== 结果：通过 ${PASS} 项，失败 ${FAIL} 项 =====${C_RST}"
[ "$FAIL" -eq 0 ]
