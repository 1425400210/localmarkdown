# macOS 兼容与分发验收

首版目标：macOS 14+、Apple Silicon（arm64），名称暂用 LocalMarkdown。Intel 未纳入本次发行范围。

## 可重复的构建

```sh
./script/build_and_run.sh --verify
./script/build_and_run.sh --release
```

Release 使用优化构建，明确指定 arm64，不退出正在使用的开发版。产物在 `.build/package/release/LocalMarkdown.app`，压缩包及 SHA-256 在 `dist/`。复制应用至 Applications 后打开即可进行本地验收；应用包含网页编辑资源，不依赖源码目录、Node.js 或 npm。

每次构建执行 `script/verify_bundle.sh`，验证 plist、Markdown 扩展名声明、资源和许可文件、可执行文件架构、Mach-O 最低系统版本及签名完整性。开发包也限定在当前首版验证范围 arm64。

## 2026-10-04 验收记录

环境：macOS 26.7（25G229）、arm64、Swift 6.4；SwiftPM deployment target 和二进制最低版本均为 14.0，网页编译目标为 Safari 17。

| 项目 | 结果 |
| --- | --- |
| macOS 26.7 / Apple Silicon | 本机构建与测试通过 |
| 安装包独立性 | ZIP 校验和通过；解压到独立临时目录后签名校验、启动及包内编辑资源加载通过 |
| macOS 14、15、其他版本 | 未取得对应系统环境，仍需真机/虚拟机验收；编译目标不代表运行实测 |
| Intel | 未测试，不作为首版支持承诺 |
| 格式解析 | 11 项 Node 测试通过 |
| WebKit / SwiftUI | 10 项集成测试通过 |
| 长文档 | 1,000 节中文/Emoji 文档加载、末尾输入、撤销及外部文本更新通过；不代表无限文档规模的性能保证 |
| 深浅色 | 背景与 color-scheme 切换、切换后撤销与原文保留通过 |
| 编辑器进程重载 | 通过调用重载恢复路径验证原生绑定中的未保存文字恢复；不是整机崩溃恢复测试 |
| 首次保存 | 独立临时文档手动保存后，磁盘 UTF-8 内容核对通过 |
| 自动保存 | 勾选任务后未按保存键，磁盘内容自动更新通过 |
| 外部文件修改 | 不保证立即刷新；再次保存时出现系统冲突提示，选择保留外部版本后正确载入 |
| 冲突保护 | 实测提供 Save Anyway / Revert / Save As；不静默覆盖 |
| 原文/图片/撤销 | Unicode、CRLF、相对图片、撤销重做等回归通过 |
| 默认应用 | 已有显式设置按钮及 `.md` / `.markdown` 声明；本轮未改用户系统默认应用 |
| 中文输入法候选 | 中文文本输入已测；候选、组合输入仍需专项人工验收 |
| 受限目录/只读文件 | 依赖系统文件授权和保存错误提示，仍需不同权限环境实测 |

## 签名与公证

当前本机查询到 0 个有效代码签名身份，产物使用 ad hoc 本地签名，**未公证，不应作为已获 macOS 信任的正式下载包发布**。不要让用户关闭 Gatekeeper。

取得 Developer ID Application 证书后，可以通过环境变量 `DEVELOPER_ID_APPLICATION` 指定签名身份，再运行 `--release`；脚本启用 hardened runtime 和安全时间戳，生成名称带 `unnotarized` 的包。该签名路径尚无证书实测。

后续发布前的操作（本轮未提交 Apple、未上传 GitHub）：

1. 使用 Keychain 中的公证凭据，通过 `xcrun notarytool submit` 提交已签名 ZIP，等待 Accepted；失败时读取公证日志。
2. 对应用执行 `xcrun stapler staple` 和 `xcrun stapler validate`。
3. 用 `spctl --assess --type execute --verbose=2` 验证 Gatekeeper 接受。
4. 重新压缩已装订票据的应用并生成校验和；在另一台 Mac 从真实下载入口安装验收。

最低版本发布门槛还包括：macOS 14 上验证中文候选、保存/自动保存/冲突、默认打开、深浅色、长文档、相对图片和离线启动。

## 应用包装验收

2026-10-04：应用名统一为 LocalMarkdown，版本 0.1.0（2）。实际打开关于窗口与帮助窗口，版本和内容显示正常。Release 同时生成 DMG；只读挂载后检查应用、Applications 链接和安装说明，并对映像及内部应用签名分别验证通过。10 项原生回归测试通过。无自定义 logo，签名与公证状态不变。

2026-10-04：版本 0.1.1（5）。设置中显示版本号；「即时渲染」开关统一控制已打开文档，移除工具栏和底部模式文字。12 项原生回归测试通过，Release 应用与 DMG 校验通过。构建应用改放隐藏的 `.build/package/` 目录，正式安装位置为 `/Applications/LocalMarkdown.app`。
