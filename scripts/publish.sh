#!/usr/bin/env bash
#
# 创建 GitHub 仓库并推送本地提交。
#
# 前置：已通过 device flow 获得 token，存放于 $GITHUB_TOKEN 或 /tmp/gh_token.txt
#
# 用法：
#   scripts/publish.sh                          # 用 /tmp/gh_token.txt，推到 token 对应账号
#   scripts/publish.sh --repo owner/name        # 指定仓库
#   scripts/publish.sh --dry-run                # 只打印将要执行的动作

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_SLUG=""
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --repo) REPO_SLUG="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "未知参数：$1" >&2; exit 1 ;;
    esac
done

# ── 取 token ───────────────────────────────────────────────────
if [ -n "${GITHUB_TOKEN:-}" ]; then
    TOKEN="$GITHUB_TOKEN"
elif [ -f /tmp/gh_token.txt ]; then
    TOKEN="$(cat /tmp/gh_token.txt)"
else
    echo "找不到 token：设置 GITHUB_TOKEN 或先完成 device flow" >&2
    exit 1
fi

if [ -z "$TOKEN" ]; then
    echo "token 为空" >&2
    exit 1
fi

# ── 确认登录身份 ──────────────────────────────────────────────
LOGIN="$(curl -s -H "Authorization: token $TOKEN" https://api.github.com/user \
    | sed -n 's/.*"login": *"\([^"]*\)".*/\1/p')"

if [ -z "$LOGIN" ]; then
    echo "token 无效或已过期" >&2
    exit 1
fi
echo "登录身份：$LOGIN"

# ── 确定仓库 slug ─────────────────────────────────────────────
# 默认使用本仓库的规范地址；可用 --repo 覆盖
if [ -z "$REPO_SLUG" ]; then
    REPO_SLUG="yzc514-bot/ubuntu26-wechat-theme-fcitx5"
fi
REPO_NAME="${REPO_SLUG#*/}"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "（dry-run）将创建仓库：$REPO_SLUG"
    echo "（dry-run）将推送分支：$(git -C "$REPO_DIR" branch --show-current)"
    exit 0
fi

# ── 确认仓库不存在，存在则跳过创建 ───────────────────────────
if curl -s -H "Authorization: token $TOKEN" \
    "https://api.github.com/repos/$REPO_SLUG" | grep -q '"full_name"'; then
    echo "仓库已存在：$REPO_SLUG（跳过创建）"
else
    echo "创建仓库：$REPO_SLUG"
    RESP="$(curl -s -X POST -H "Authorization: token $TOKEN" \
        -H "Accept: application/vnd.github+json" \
        -d "{\"name\":\"$REPO_NAME\",\"description\":\"仿微信输入法的 fcitx5 + Rime 主题，一键安装\",\"private\":false,\"has_issues\":true,\"has_wiki\":false}" \
        https://api.github.com/user/repos)"
    if echo "$RESP" | grep -q '"full_name"'; then
        echo "  ✓ 创建成功"
    else
        echo "  ✗ 创建失败：$(echo "$RESP" | head -c 300)" >&2
        exit 1
    fi
fi

# ── 配置 remote 并推送 ────────────────────────────────────────
cd "$REPO_DIR"

if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "https://$LOGIN:$TOKEN@github.com/$REPO_SLUG.git"
else
    git remote add origin "https://$LOGIN:$TOKEN@github.com/$REPO_SLUG.git"
fi

BRANCH="$(git branch --show-current)"
echo "推送分支：$BRANCH → $REPO_SLUG"
git push -u origin "$BRANCH"

# ── 验证推送结果 ──────────────────────────────────────────────
REMOTE_SHA="$(git ls-remote origin "$BRANCH" | cut -f1)"
LOCAL_SHA="$(git rev-parse HEAD)"

if [ "$REMOTE_SHA" = "$LOCAL_SHA" ]; then
    echo "  ✓ 推送成功，远端 HEAD = $REMOTE_SHA"
else
    echo "  ✗ 推送后校验不一致（远端=$REMOTE_SHA 本地=$LOCAL_SHA）" >&2
    exit 1
fi

# ── 清理 remote 中的 token（避免明文留在 .git/config）────────
git remote set-url origin "https://github.com/$REPO_SLUG.git"

echo "完成：https://github.com/$REPO_SLUG"
