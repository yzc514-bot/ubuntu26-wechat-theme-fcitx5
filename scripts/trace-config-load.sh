#!/usr/bin/env bash
#
# 证明运行中的守护进程确实读取了某个配置文件。
#
# 用 strace 跟踪守护进程的文件打开操作，找出目标配置文件的加载记录。
# 关键：看返回值 —— 非负的 fd 表示**成功打开**；`= -1 ENOENT` 表示没找到。
#
# 用法：
#   scripts/trace-config-load.sh "fcitx5 --replace" "/path/to/theme.conf"
#   scripts/trace-config-load.sh "fcitx5 --replace" "theme.conf" --timeout 20

set -uo pipefail

CMD="${1:-}"
TARGET="${2:-}"
TIMEOUT=15

if [ $# -ge 3 ] && [ "$3" = "--timeout" ]; then
    TIMEOUT="$4"
fi

if [ -z "$CMD" ] || [ -z "$TARGET" ]; then
    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
fi

if ! command -v strace >/dev/null 2>&1; then
    echo "需要 strace：sudo apt install strace" >&2
    exit 1
fi

TRACE_FILE="$(mktemp -t trace-config-load.XXXXXX)"
BASE_NAME="$(basename "$TARGET")"

echo "跟踪命令：$CMD"
echo "目标文件：$TARGET"
echo "超时：${TIMEOUT}s"
echo "---"

# strace 跟踪 openat；进程被 timeout 杀掉属正常
timeout "$TIMEOUT" strace -f -e trace=openat -o "$TRACE_FILE" \
    bash -c "$CMD" >/dev/null 2>&1

FOUND=0
SUCCESS=0

if [ -f "$TRACE_FILE" ]; then
    while IFS= read -r line; do
        # 只看包含目标文件名的记录
        case "$line" in
            *"$BASE_NAME"*) ;;
            *) continue ;;
        esac
        FOUND=1
        if echo "$line" | grep -q 'ENOENT\|EACCES\|ENOTDIR'; then
            printf '  [未找到] %s\n' "$line"
        else
            # 成功打开：提取 fd 号
            fd=$(echo "$line" | sed -n 's/.*= \([0-9][0-9]*\)$/\1/p')
            if [ -n "$fd" ]; then
                printf '  [成功打开 fd=%s] %s\n' "$fd" "$line"
                SUCCESS=$((SUCCESS + 1))
            else
                printf '  [成功] %s\n' "$line"
                SUCCESS=$((SUCCESS + 1))
            fi
        fi
    done < "$TRACE_FILE"
fi

rm -f "$TRACE_FILE"

echo "---"
if [ "$SUCCESS" -gt 0 ]; then
    echo "结论：成功打开 ${SUCCESS} 次 —— 守护进程确实读取了该文件 ✓"
    exit 0
elif [ "$FOUND" -gt 0 ]; then
    echo "结论：只找到未成功的打开记录 —— 该路径未被加载 ✗"
    exit 1
else
    echo "结论：未找到相关记录 —— 请确认路径正确、且追踪期间进程确实重启了 ✗"
    exit 1
fi
