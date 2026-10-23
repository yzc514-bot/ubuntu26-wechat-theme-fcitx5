# ubuntu26-wechat-theme-fcitx5

仿微信输入法的 **fcitx5 + Rime** 主题，一键安装。

![浅色主题预览](docs/preview-wechat.png)

采用微信官方设计规范配色：

| 用途 | 色值 |
|---|---|
| 品牌绿（选中态底色） | `#07C160` |
| 正文 | `#353535` |
| 次要文字 / 序号 / 注释 | `#888888` |
| 分割线 / 边框 | `#E5E5E5` |
| 面板背景 | `#FFFFFF` |

---

## 特性

- **微信绿圆角高亮**：选中的候选词是微信绿的圆角块，白字
- **圆角候选面板**：白底、浅灰描边、柔和投影（SVG 九宫格拉伸，任意宽度不变形）
- **浅色 / 深色双主题**：深色版面板 `#191919`，跟随系统深浅色自动切换
- **数字键直选**：按 `1`–`5` 直接上屏，与微信输入法一致
- **幂等安装**：可重复执行，自动备份、部署词典、重载 fcitx5
- **可完整卸载**：一键还原安装前的配置

## 前置要求

- Ubuntu 22.04+ / Debian 12+（其他发行版原理相同）
- `fcitx5` 与 `fcitx5-rime`
- 中文字体（默认使用 `Noto Sans CJK SC`）

安装依赖：

```bash
sudo apt install fcitx5 fcitx5-rime fonts-noto-cjk
```

## 快速开始

```bash
git clone https://github.com/ubuntu26/ubuntu26-wechat-theme-fcitx5.git
cd ubuntu26-wechat-theme-fcitx5
./install.sh
```

安装完成后切换到 Rime 输入法即可看到新主题。

### 命令

```bash
./install.sh              # 安装浅色主题
./install.sh --dark       # 安装深色主题
./install.sh --no-rime    # 只装 fcitx5 主题，不改动 Rime 配置
./install.sh --uninstall  # 卸载并还原安装前的配置
```

## 安装脚本做了什么

1. 检查 `fcitx5` / `fcitx5-rime` 是否存在
2. 备份 `classicui.conf` 与 `default.custom.yaml` 到
   `~/.local/share/fcitx5/wechat-theme-backups/`
3. 安装主题到 `~/.local/share/fcitx5/themes/wechat/`（深色版为 `wechat-dark/`）
4. 写入 `~/.config/fcitx5/conf/classicui.conf`：`Theme`、`DarkTheme`、字体
5. 部署 `~/.local/share/fcitx5/rime/default.custom.yaml`
6. 在 Rime 配置目录下执行 `rime_deployer --build` 重建词典
7. 执行 `fcitx5 -r` 重载输入法

## 工作原理

fcitx5-rime 的候选窗**不是**由 librime 的 `squirrel.yaml` 渲染的 —— 实测确认
`fcitx5-rime` 只读取 `default.yaml` 和 `fcitx5.yaml`，候选窗的实际绘制由
**fcitx5 classicui 主题层**完成。

所以这个项目分两层改：

```
themes/wechat/theme.conf   → 候选窗外观（配色、圆角、高亮、字体、边距）
rime/default.custom.yaml   → 候选行为（候选数、选字键、注释格式）
```

### 圆角是怎么实现的

classicui 没有圆角配置项，但 `InputPanel/Background` 和 `InputPanel/Highlight`
都支持 `Image` 背景图，SVG 会按**九宫格**方式拉伸：

```
sourceX = {0, marginLeft, width - marginRight, width}
sourceY = {0, marginTop,  height - marginBottom,  height}
```

因此 `theme.conf` 里的 `Margin` 必须与 SVG 的圆角半径严格一致，否则圆角会被拉伸变形：

| 资源 | 尺寸 | 圆角半径 | 对应 Margin |
|---|---|---|---|
| `panel.svg` | 56×56 | 14px | `InputPanel/Background/Margin` = 14 |
| `highlight.svg` | 32×32 | 8px | `InputPanel/Highlight/Margin` = 8 |

## 目录结构

```
├── install.sh                    一键安装 / 卸载脚本
├── themes/
│   ├── wechat/                   浅色主题
│   │   ├── theme.conf            classicui 主题配置
│   │   ├── panel.svg             圆角面板背景（九宫格）
│   │   ├── highlight.svg         微信绿高亮块（九宫格）
│   │   ├── prev.svg / next.svg   翻页箭头
│   └── wechat-dark/              深色主题（同结构）
├── rime/
│   └── default.custom.yaml       Rime 配置补丁
├── scripts/
│   └── preview.py                离屏渲染主题预览图
└── docs/
    ├── preview-wechat.png
    └── preview-wechat-dark.png
```

## Rime 补丁说明

```yaml
patch:
  menu:
    page_size: 5                        # 一屏 5 个候选，与微信一致
    alternative_select_keys: "1234567890"
    alternative_select_labels: [1,2,3,4,5]
```

> **注意**：只设置 `alternative_select_labels` 会导致 `select_keys` 变为空，
> 数字键将无法选词。必须同时显式声明 `alternative_select_keys`。

## 生成预览图

```bash
python3 scripts/preview.py --theme wechat
python3 scripts/preview.py --theme wechat-dark
```

依赖：`python3-pil`、`librsvg2-bin`（`rsvg-convert`）。预览按 fcitx5 的九宫格
规则渲染，用于在没有截图权限的环境中核对主题效果。

## 兼容性

基于以下版本验证：

- fcitx5 **5.1.22**
- librime **1.17.0**
- Ubuntu **26.10** (Wayland + XWayland)

主题键取自 fcitx5 5.1.22 的 `src/ui/classic/theme.h`；更高版本新增的键
（如 `SupportedScale`）本主题未使用，低版本若缺少某些键会退回到默认值。

## 许可

MIT，见 [LICENSE](LICENSE)。
