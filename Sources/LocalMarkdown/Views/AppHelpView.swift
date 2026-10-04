import SwiftUI

struct AppHelpView: View {
    @AppStorage("appearance") private var appearance: AppAppearance = .system

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("开始使用 LocalMarkdown").font(.title2.bold())
            Text("打开 .md 或 .markdown 文件，点击正文中的内容块即可编辑；离开该块后恢复排版。")
            Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 10) {
                GridRow { Text("新建 / 打开 / 保存"); Text("⌘N / ⌘O / ⌘S") }
                GridRow { Text("撤销 / 重做"); Text("⌘Z / ⇧⌘Z") }
                GridRow { Text("查找与替换"); Text("⌘F") }
                GridRow { Text("显示或隐藏大纲"); Text("⌥⌘1") }
                GridRow { Text("设置"); Text("⌘,") }
            }
            Text("标题：⌘1～6；正文：⌘0。也支持 Control + 0～6。\n更多格式操作见「格式」菜单；在「设置 → 快捷键与工具栏」中可更改组合键和显示按钮。")
                .font(.callout)
            Text("在「设置 → 编辑」中打开即时渲染可显示排版效果，关闭后显示全部 Markdown 源码。立即应用到所有文档，文件内容保持不变。")
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            Text("文件与保存").font(.headline)
            Text("新文档请先按 ⌘S 选择保存位置。已保存文档会自动保存，也可随时按 ⌘S。文件被其他应用修改后，保存时按系统提示选择保留哪个版本或另存为。")
            Text("在「设置 → 通用」中可将 LocalMarkdown 设为默认 Markdown 编辑器。相对路径图片以文档所在文件夹为基准。")
            Text("正文编辑与公式、图表渲染可离线使用；文档中的网络图片需要联网。")
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
        .preferredColorScheme(appearance.colorScheme)
    }
}
