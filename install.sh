#!/usr/bin/env bash
#
# ubuntu26-wechat-theme-fcitx5 —— 一键安装仿微信输入法主题
#
# 用法：
#   ./install.sh              安装（浅色主题）
#   ./install.sh --dark       安装（深色主题）
#   ./install.sh --uninstall  卸载，恢复安装前的配置
#   ./install.sh --no-rime    只装 fcitx5 主题，不动 rime 配置
#
# 脚本可重复执行：重复安装会覆盖本项目自己部署的文件，
# 但不会破坏用户自己的其它配置（会先备份）。

set -euo pipefail

# ── 常量 ────────────────────────────────────────────────────────
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FCITX_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fcitx5"
FCITX_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fcitx5"
FCITX_CONF_DIR="$FCITX_CONFIG_DIR/conf"
RIME_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fcitx5/rime"
THEMES_SRC="$REPO_DIR/themes"
RIME_SRC="$REPO_DIR/rime"

BACKUP_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/fcitx5/wechat-theme-backups"
STAMP_FILE="$BACKUP_ROOT/.installed"

THEME_LIGHT="wechat"
THEME_DARK="wechat-dark"

# ── 输出辅助 ────────────────────────────────────────────────────
if [ -t 1 ]; then
    C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
    C_BLU=$'\033[34m'; C_BLD=$'\033[1m'; C_RST=$'\033[0m'
else
    C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_BLD=""; C_RST=""
fi

info()  { printf '%s\n' "${C_BLU}[*]${C_RST} $*"; }
ok()    { printf '%s\n' "${C_GRN}[✓]${C_RST} $*"; }
warn()  { printf '%s\n' "${C_YEL}[!]${C_RST} $*" >&2; }
err()   { printf '%s\n' "${C_RED}[✗]${C_RST} $*" >&2; }
die()   { err "$*"; exit 1; }

# ── 参数解析 ────────────────────────────────────────────────────
INSTALL_THEME="$THEME_LIGHT"
DO_UNINSTALL=0
DO_RIME=1

while [ $# -gt 0 ]; do
    case "$1" in
        --dark)      INSTALL_THEME="$THEME_DARK" ;;
        --light)     INSTALL_THEME="$THEME_LIGHT" ;;
        --uninstall) DO_UNINSTALL=1 ;;
        --no-rime)   DO_RIME=0 ;;
        -h|--help)   sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)           die "未知参数：$1（用 --help 查看用法）" ;;
    esac
    shift
done

# ── 前置检查 ────────────────────────────────────────────────────
check_deps() {
    local missing=0

    if ! command -v fcitx5 >/dev/null 2>&1; then
        warn "未检测到 fcitx5，请先安装：sudo apt install fcitx5 fcitx5-rime"
        missing=1
    else
        ok "fcitx5 已安装（$(fcitx5 --version 2>/dev/null | head -1)）"
    fi

    if ! dpkg -s fcitx5-rime >/dev/null 2>&1; then
        warn "未检测到 fcitx5-rime，请先安装：sudo apt install fcitx5-rime"
        missing=1
    else
        ok "fcitx5-rime 已安装"
    fi

    if [ "$missing" -ne 0 ]; then
        die "缺少依赖，请先安装后重试"
    fi

    if ! command -v fcitx5-remote >/dev/null 2>&1; then
        warn "fcitx5-remote 不可用，将跳过输入法重载"
    fi
}

# ── 备份 ────────────────────────────────────────────────────────
# 只备份一次：首次安装时保存用户原始配置，卸载时原样恢复。
backup_once() {
    local key="$1" src="$2"
    [ -e "$src" ] || return 0
    mkdir -p "$BACKUP_ROOT"
    local dst="$BACKUP_ROOT/$key"
    if [ -e "$dst" ]; then
        return 0   # 已备份过，保留最初版本
    fi
    cp -a "$src" "$dst"
    info "已备份 $src → $dst"
}

backup_all() {
    backup_once "classicui.conf" "$FCITX_CONF_DIR/classicui.conf"
    backup_once "default.custom.yaml" "$RIME_DIR/default.custom.yaml"
}

# ── 设置 classicui.conf 的键值 ─────────────────────────────────
# classicui.conf 是扁平的顶级键文件（没有 [Addon/ClassicUI] 段），
# 因此这里按「顶级键」处理：存在则替换，不存在则追加到文件末尾。
set_flat_key() {
    local file="$1" key="$2" value="$3"
    [ -f "$file" ] || : > "$file"

    if grep -qE "^[[:space:]]*${key}=" "$file"; then
        sed -i -E "s|^[[:space:]]*${key}=.*$|${key}=${value}|" "$file"
    else
        printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
}

# 通用 ini 分段写入（供未来需要分段的文件使用）
# 使用 ini 风格的键替换：若键已存在则替换，否则追加到对应段落。
set_ini_key() {
    local file="$1" section="$2" key="$3" value="$4"
    [ -f "$file" ] || : > "$file"

    # 键已存在 → 直接替换
    if grep -qE "^[[:space:]]*${key}=" "$file"; then
        sed -i -E "s|^[[:space:]]*${key}=.*$|${key}=${value}|" "$file"
        return 0
    fi

    # 目标段存在 → 追加到该段末尾
    if grep -qE "^\[${section}\][[:space:]]*$" "$file"; then
        awk -v sec="$section" -v kv="${key}=${value}" '
            /^\[/ { insec = ($0 == "[" sec "]") }
            { print }
            insec && !done && /^$/ { print kv; done = 1 }
        ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
        # 段内没有空行时兜底：追加到文件末尾
        if ! grep -qE "^[[:space:]]*${key}=" "$file"; then
            printf '\n[%s]\n%s=%s\n' "$section" "$key" "$value" >> "$file"
        fi
        return 0
    fi

    # 段不存在 → 新建段落
    printf '\n[%s]\n%s=%s\n' "$section" "$key" "$value" >> "$file"
}

# ── 安装 ────────────────────────────────────────────────────────
install_theme() {
    local theme="$1"
    local src="$THEMES_SRC/$theme"
    [ -d "$src" ] || die "主题源目录不存在：$src"

    local dst="$FCITX_DATA_DIR/themes/$theme"
    mkdir -p "$(dirname "$dst")"
    rm -rf "$dst"
    cp -r "$src" "$dst"
    ok "主题已安装 → $dst"
}

install_rime_config() {
    local src="$RIME_SRC/default.custom.yaml"
    [ -f "$src" ] || { warn "未找到 rime 补丁文件，跳过"; return 0; }

    mkdir -p "$RIME_DIR"
    cp "$src" "$RIME_DIR/default.custom.yaml"
    ok "rime 配置已部署 → $RIME_DIR/default.custom.yaml"
}

apply_classicui() {
    local theme="$1"
    local conf="$FCITX_CONF_DIR/classicui.conf"

    mkdir -p "$FCITX_CONF_DIR"

    # 清理历史版本可能写入的错误分段（classicui.conf 本是扁平结构，
    # 不应存在 [Addon/ClassicUI] 之类的段）。
    # 连同段内内容一并删除，直到遇到下一个段标题或文件末尾。
    if [ -f "$conf" ] && grep -qE '^\[Addon/ClassicUI\][[:space:]]*$' "$conf"; then
        awk '
            /^\[Addon\/ClassicUI\][[:space:]]*$/ { skip = 1; next }
            /^\[/ { skip = 0 }
            !skip { print }
        ' "$conf" > "$conf.tmp" && mv "$conf.tmp" "$conf"
        # 去掉尾部多余空行
        sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$conf" 2>/dev/null || true
        info "已清理 classicui.conf 中多余的分段"
    fi

    # 主题选择：浅色 → Theme；深色 → Theme 同时配 DarkTheme
    if [ "$theme" = "$THEME_DARK" ]; then
        set_flat_key "$conf" "Theme" "$THEME_LIGHT"
        set_flat_key "$conf" "DarkTheme" "$THEME_DARK"
        set_flat_key "$conf" "UseDarkTheme" "True"
    else
        set_flat_key "$conf" "Theme" "$THEME_LIGHT"
        set_flat_key "$conf" "DarkTheme" "$THEME_DARK"
        set_flat_key "$conf" "UseDarkTheme" "False"
    fi

    # 字体跟随系统中文字体
    set_flat_key "$conf" "Font" "Noto Sans CJK SC 14"
    set_flat_key "$conf" "MenuFont" "Noto Sans CJK SC 13"
    set_flat_key "$conf" "TrayFont" "Noto Sans CJK SC 12"

    ok "classicui.conf 已更新"
}

# ── 部署 rime ───────────────────────────────────────────────────
deploy_rime() {
    if ! command -v rime_deployer >/dev/null 2>&1; then
        warn "未找到 rime_deployer，跳过词典部署"
        return 0
    fi
    info "正在部署 rime 词典（首次可能较慢）..."
    # rime_deployer 必须在 rime 用户配置目录下运行，否则找不到配置
    if (cd "$RIME_DIR" && rime_deployer --build) >/dev/null 2>&1; then
        ok "rime 词典部署完成"
    else
        warn "rime 部署返回非零状态，可稍后手动执行：cd $RIME_DIR && rime_deployer --build"
    fi
}

# ── 重载 fcitx5 ─────────────────────────────────────────────────
reload_fcitx() {
    if ! command -v fcitx5-remote >/dev/null 2>&1; then
        return 0
    fi
    if fcitx5-remote -r >/dev/null 2>&1; then
        ok "fcitx5 已重载"
    else
        warn "fcitx5 重载失败，请手动执行：fcitx5 -r"
    fi
}

# ── 卸载 ────────────────────────────────────────────────────────
uninstall() {
    info "开始卸载"

    # 还原备份的配置
    if [ -d "$BACKUP_ROOT" ]; then
        if [ -f "$BACKUP_ROOT/classicui.conf" ]; then
            cp -a "$BACKUP_ROOT/classicui.conf" "$FCITX_CONF_DIR/classicui.conf"
            ok "已恢复 classicui.conf"
        fi
        if [ -f "$BACKUP_ROOT/default.custom.yaml" ]; then
            cp -a "$BACKUP_ROOT/default.custom.yaml" "$RIME_DIR/default.custom.yaml"
            ok "已恢复 default.custom.yaml"
        elif [ -f "$RIME_DIR/default.custom.yaml" ]; then
            rm -f "$RIME_DIR/default.custom.yaml"
            ok "已移除 default.custom.yaml"
        fi
        rm -rf "$BACKUP_ROOT"
        ok "已清理备份目录"
    fi

    # 移除主题
    for t in "$THEME_LIGHT" "$THEME_DARK"; do
        if [ -d "$FCITX_DATA_DIR/themes/$t" ]; then
            rm -rf "$FCITX_DATA_DIR/themes/$t"
            ok "已移除主题 $t"
        fi
    done

    deploy_rime
    reload_fcitx
    ok "卸载完成"
}

# ── 主流程 ──────────────────────────────────────────────────────
main() {
    printf '%s\n' "${C_BLD}ubuntu26-wechat-theme-fcitx5 —— 仿微信输入法主题安装程序${C_RST}"
    printf '%s\n' ""

    if [ "$DO_UNINSTALL" -eq 1 ]; then
        uninstall
        exit 0
    fi

    check_deps
    backup_all

    install_theme "$INSTALL_THEME"
    apply_classicui "$INSTALL_THEME"

    if [ "$DO_RIME" -eq 1 ]; then
        install_rime_config
        deploy_rime
    else
        info "已跳过 rime 配置（--no-rime）"
    fi

    reload_fcitx

    printf '%s\n' ""
    ok "安装完成"
    printf '%s\n' ""
    printf '%s\n' "  主题：$( [ "$INSTALL_THEME" = "$THEME_DARK" ] && echo "$THEME_DARK（深色）" || echo "$THEME_LIGHT（浅色）" )"
    printf '%s\n' "  备份：$BACKUP_ROOT"
    printf '%s\n' ""
    printf '%s\n' "  提示：切换输入法后即可看到新主题。"
    printf '%s\n' "  如需深色：./install.sh --dark"
    printf '%s\n' "  如需卸载：./install.sh --uninstall"
    printf '%s\n' ""
}

main "$@"
