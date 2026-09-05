# FalconMD 应用图标维护指引

当前图标采用「纸页成隼」：一个合并的纸页与隼的主轮廓，加上一个青色折角。主体由两条 SVG 路径构成，依靠翼尖、短钩喙和两翼之间的负空间识别。

![FalconMD 应用图标](../../FalconMD/Assets.xcassets/AppIcon.appiconset/AppIcon-256.png)

## 源文件和应用资源

- **编辑入口**：[falconmd-icon.svg](falconmd-icon.svg)。这是应用图标唯一的源文件。
- **应用资源**：[AppIcon.appiconset](../../FalconMD/Assets.xcassets/AppIcon.appiconset/)。其中的七个 PNG 均由源 SVG 导出。
- **导出工具**：[tools/app-icon](../../tools/app-icon/)。依赖通过 `package-lock.json` 固定，仅修改图标时需要 Node.js。

Xcode 的 Debug 和 Release 配置都使用 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`。当前项目通过资源目录打包图标，SVG 留在设计目录用于编辑，PNG 随应用构建。日常构建和发布直接使用仓库中的 PNG，无需运行导出工具。

## 修改 SVG

在矢量编辑器或文本编辑器中修改 `falconmd-icon.svg`，保持：

- `width="1024"`、`height="1024"` 和 `viewBox="0 0 256 256"`。
- 完全不透明的方形背景；主体留出足够边距。
- 两个清晰的纯色形状，以及两翼之间的空隙。避免增加纹理、阴影、复杂折面和细线。
- 矢量路径独立完整，不依赖外部图片或字体。

| 角色 | SVG 元素 | 色值 |
| --- | --- | --- |
| 深墨蓝背景 | `background` | `#0B1730` |
| 纸白主体 | `falcon` | `#F6F3EB` |
| 青色折角 | `fold` | `#4FD1D8` |

16 px 主要依靠整体轮廓，钩喙与折角在更大尺寸下更清楚。每次修改都应实际查看 16、32、64 和 128 px 的图片。

## 重新导出

需要 Node.js 20.9 或更新版本，以及 npm。以下命令均从仓库根目录运行：

```bash
npm ci --prefix tools/app-icon
npm run generate --prefix tools/app-icon
npm run check --prefix tools/app-icon
```

`generate` 根据现有 `Contents.json` 生成 16、32、64、128、256、512、1024 px 的不透明 RGB PNG，覆盖应用正在使用的文件；不修改资源配置。`check` 重新渲染 SVG，核对全部十项 macOS 1x / 2x 引用对应的图片尺寸、透明度和像素内容，且不会写文件。

修改后应一起提交 SVG 和重新生成的全部 PNG，避免单独编辑某一张尺寸图片。

## 构建验证

```bash
xcodebuild -project FalconMD.xcodeproj -scheme FalconMD \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData build
```

构建后的图标位于 `build/DerivedData/Build/Products/Debug/FalconMD.app/Contents/Resources/`，包括 `AppIcon.icns` 与 `Assets.car`。Xcode 会打包资源目录，无需手工替换构建产物中的图标。

如需单独核验图标资源编译：

```bash
mkdir -p build/AppIconValidation
xcrun actool FalconMD/Assets.xcassets \
  --compile build/AppIconValidation \
  --platform macosx --minimum-deployment-target 15.0 \
  --app-icon AppIcon \
  --output-partial-info-plist build/AppIconValidation/Info.plist
```

打开新构建的应用后查看 Dock 和 Finder 图标。如果仍看到旧图标，先退出旧应用实例，再从本次构建路径启动；必要时在 Xcode 清理构建目录后重新构建。
