# LocalMarkdown

macOS 14 及以上的本地 Markdown 编辑器。SwiftUI 提供原生文档窗口、文件管理和设置；WKWebView 中的 CodeMirror 与 Markdown 解析器提供即时排版。编辑引擎、公式字体和图表库随应用打包，核心编辑与渲染不需要网络、登录或服务端。文档中的网络图片需要网络。

## 使用

自行构建安装包后，打开 `dist/LocalMarkdown-0.1.1-macOS-arm64.dmg`，将 LocalMarkdown 拖到 Applications，推出磁盘映像后从「应用程序」打开。当前安装包为未公证的本地测试版。

开发时可双击 `.build/package/debug/LocalMarkdown.app`。打开 `docs/格式验收.md` 可以检查第一阶段支持的格式。

在排版后的正文中点击内容块显示 Markdown 源码，离开后恢复排版。普通段落按段编辑；表格、列表、引用、公式按结构块编辑。在「设置 → 编辑」中关闭「即时渲染」可切换全文源码模式，立即应用到所有已打开文档。渲染不会将 HTML 转回 Markdown 或重写原文。

| 快捷键 | 操作 |
| --- | --- |
| ⌘N / ⌘O / ⌘S | 新建 / 打开 / 保存 |
| ⌘Z / ⇧⌘Z | 撤销 / 重做 |
| ⌘F | 查找 / 替换 |
| ⌘B / ⌘I | 加粗 / 斜体 |
| ⇧⌘K | 行内代码 |
| ⌥⌘1 | 显示 / 隐藏大纲 |
| ⌘, | 设置 |

正文按 [默认正文排版参数](docs/typography.md)校准：默认 16 号字、1.6 倍行高、左右各 30 px 留白，相邻段落间距合并。设置中可「恢复默认排版」。

## 格式支持

- **通用基础**：六级标题与 Setext 标题、段落与软/硬换行、嵌套强调、引用、嵌套有序/无序列表、行内代码、围栏与缩进代码块、语法高亮、分隔线、普通/引用式/自动链接、标题跳转、图片、转义和字符实体。
- **GFM 常用扩展**：表格及列对齐、表格内行内格式、可点击任务复选框、删除线。
- **写作扩展**：行内/独立 LaTeX 公式（KaTeX）、脚注、高亮、YAML 元数据、Mermaid 图表、GitHub 风格提示块。
- **HTML**：静态排版元素，包括上下标、下划线、颜色、换行等；脚本、事件属性、iframe 和表单不执行。
- 图片支持相对于当前文档的路径、绝对路径、网络 URL；尚未保存的文档需要先保存，才能解析相对路径。代码块有复制按钮。

公式使用 KaTeX 的 TeX 子集，不是完整 LaTeX 编译器，部分 MathJax 专有命令不同。Mermaid 按所锁定依赖版本支持图表，错误语法保留可编辑源码并显示提示。表格目前通过 Markdown 源码编辑，没有新增/删除行列的图形工具栏。YAML 显示为元数据块，不提供 Obsidian 式属性表单。

不包含第二阶段 Obsidian 双链、笔记嵌入、块引用、插件语法，也不包含 Typora 的 `[toc]`、上下标简写或独立 flow/sequence 图表语言。

## 设置

`⌘,` 或工具栏齿轮：外观跟随系统/浅色/深色、字号 13–24 pt、正文宽度 600/720/800/900 pt、即时渲染开关和默认大纲显示。设置保存在本机。

默认 Markdown 应用按钮通过 macOS 的文件关联 API 设置 `.md` / `.markdown`。只在用户点击时修改；单个文件已有的打开方式可在访达“显示简介”中调整。

## 构建

需要支持 Swift 6 的 macOS 开发工具。已打包的网页资源在 `Sources/LocalMarkdown/Resources/Editor`，普通 Swift 构建无需安装 Node 或联网：

```sh
./script/build_and_run.sh --verify
```

脚本正常退出旧应用（保留未保存文档提示），构建并复制资源到 `.build/package/debug/LocalMarkdown.app`，进行本地 ad hoc 签名后启动。支持 `--debug`、`--logs`。

修改网页编辑器时，需要 Node.js 和 npm：

```sh
cd EditorWeb
npm ci
npm test
npm run build
```

依赖版本锁定在 `EditorWeb/package-lock.json`，许可证随资源打包在 `THIRD-PARTY-NOTICES.txt`。

## 验证

```sh
npm --prefix EditorWeb test
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
swift test --disable-sandbox --cache-path .build/cache
```

Swift 集成测试会启动真实 WebKit，需要正常 macOS 桌面权限。覆盖离线资源加载、格式渲染、任务点击、撤销/重做、源码切换、外部文本更新、HTML 清理、CRLF 与 Unicode 原文保留。格式夹具见 `docs/格式验收.md`。

首版目标为 macOS 14+、Apple Silicon。使用 `./script/build_and_run.sh --release` 生成优化的 arm64 应用、ZIP 和 SHA-256 校验和；构建自动检查包结构、架构、最低系统版本和签名完整性。

目前实际测试环境为 macOS 26.7 / Apple Silicon，尚未在 macOS 14 真机验证，也未做 Developer ID 签名或 Apple 公证。详细结果、待验收项与正式分发步骤见 [macOS 兼容与分发验收](docs/macos-compatibility.md)。

## 应用包装

应用显示名称、版本、构建号和文件类型声明集中在 `packaging/Info.plist`。菜单提供「关于 LocalMarkdown」和「LocalMarkdown 使用帮助」，关于窗口可打开随包附带的第三方许可。应用已采用三行叠页图标，源图和 ICNS 位于 packaging/。

`--release` 同时生成 ZIP、可拖入 Applications 的 DMG 和各自的 SHA-256 校验和；安装说明位于 `packaging/安装说明.txt`。修改版本只需更新 plist，关于窗口和打包文件名会读取它。

## 快捷键与工具栏

标题使用 Command+1～6，正文使用 Command+0，同时支持 Control+0～6 兼容操作。设置中的「快捷键与工具栏」可修改或清除格式快捷键，并选择显示哪些工具栏按钮。设置立即生效，重复和保留快捷键会提示冲突。

即时渲染显示排版结果，点击内容块展开源码；源码模式始终显示全部标记。两者编辑同一份文件，切换不会转换内容。

## 许可证

项目原创代码采用 [MIT 许可证](LICENSE)。随包提供的第三方代码和字体遵循各自许可证，详见 [第三方许可声明](Sources/LocalMarkdown/Resources/Editor/THIRD-PARTY-NOTICES.txt)；MIT 不替代这些许可。

## 反馈与贡献

欢迎通过 GitHub Issues 报告问题，附上 macOS 版本、应用版本和最小复现步骤。提交示例文档前请移除个人信息。修改编辑器后请运行上面的网页测试和 Swift 集成测试，再提交 Pull Request。
