# BingZip

**BingZip** 是一款原生 macOS 压缩软件，界面与操作参考经典 7-Zip，
压缩引擎直接编译自 **7-Zip 26.05** 官方 C++ 源码（完整格式支持版 `7zz`）。

A native macOS archiver GUI built on the 7-Zip 26.05 engine.

> 独立开源项目，非 7-Zip 官方产品。7-Zip 引擎的版权与许可证归 Igor Pavlov 所有。

## 下载（适合普通用户）

请打开 [**Releases**](https://github.com/fuziwenstudent/BingZip/releases/latest) 页面，下载最新的：

- `BingZip-1.2.dmg`（推荐）
- `BingZip-1.2-macos-x86_64-arm64.zip`

当前版本使用 ad-hoc 签名，没有 Apple Developer ID 公证，首次打开可能被 Gatekeeper 拦截：

1. 把 `BingZip.app` 拖到“应用程序”文件夹。
2. 如果提示“无法验证开发者”，在 Finder 中右键 BingZip.app → **打开** → 再确认“打开”。
3. 仍然无法打开时，在终端执行：

   ```bash
   xattr -dr com.apple.quarantine /Applications/BingZip.app
   ```

首次启动后，请在 **应用菜单 → 权限设置…** 中启用 Finder 右键菜单；
如需访问桌面、文稿、下载和外接磁盘，在“完全磁盘访问”中一次性授权。

## 功能概览

- **Finder 右键菜单**：压缩到压缩包、解压到…、打开压缩包
  - “压缩到压缩包”和“解压到…”只显示对应对话框，不会打开主界面
  - “打开压缩包”才进入主界面浏览
- **压缩格式**：7z、ZIP、Tar、GZip、XZ、BZip2、WIM；RAR 创建需另装 RARLAB `rar`
- **解压格式**：7z、ZIP、RAR、Tar、GZip、BZip2、XZ、WIM、ISO、DMG 等
- **加密**：7z AES-256 / 加密文件名；ZIP AES-256
- **文件管理器**：目录树、面包屑地址栏、收藏夹、列排序、筛选、批量测试/扫描
- **触摸板**：文件列表与目录树支持双指滑动；右滑后退、左滑前进
- **键盘快捷键**：Return 打开、⌘⌫ 删除、F2 重命名、⌘[ / ⌘] 后退/前进等
- **其他**：分卷压缩、压缩后删除源文件、CRC/哈希计算、基准测试、崩溃日志

详细功能说明见 [`BingZip/README.md`](BingZip/README.md)。

## 从源码构建

环境要求：

- macOS 11.0 或更高版本
- Xcode Command Line Tools（`xcode-select --install`）
- Swift 5.9+（Swift 6 工具链可直接构建）

```bash
cd BingZip
./build.sh release
```

构建脚本会：

1. 编译 7-Zip 引擎（arm64 + x86_64）
2. 编译 Swift GUI（Universal 2）
3. 编译 Finder Sync 右键扩展
4. 组装并 ad-hoc 签名 `BingZip.app`
5. 在 `BingZip/dist/` 生成 ZIP / DMG / SHA256SUMS.txt

如果只想调试 GUI，可以：

```bash
cd BingZip
swift build
swift run
```

> 构建产物（`BingZip/.build/`、`BingZip/dist/`、7-Zip 的 `b/m_*` 目录）已被
> `.gitignore` 忽略。发布版本通过 GitHub Releases 分发。

## 仓库结构

```text
.
├── BingZip/                 # macOS App（Swift + AppKit）
│   ├── Sources/BingZip/     # GUI、Core、UI
│   ├── FinderSync/          # Finder 右键扩展
│   ├── Resources/           # Info.plist、AppIcon
│   ├── tools/               # 图标生成脚本
│   ├── build.sh             # 一键构建 App / ZIP / DMG
│   └── README.md            # 详细功能与使用说明
├── C/ CPP/ Asm/ DOC/        # 7-Zip 26.05 引擎源码与许可证
├── LICENSE                  # BingZip 原创代码的 MIT 许可证
└── THIRD-PARTY-NOTICES.md   # 7-Zip / RARLAB 等第三方许可说明
```

## 许可证

- **BingZip 原创代码**（主要位于 `BingZip/`）采用 [MIT License](LICENSE)。
- **7-Zip 引擎源码**（`C/`、`CPP/`、`Asm/`、`DOC/`）采用 GNU LGPL；
  `CPP/7zip/Compress/Rar*` 另含 unRAR 限制。完整条款见
  [`DOC/License.txt`](DOC/License.txt)。
- RAR **创建**需要 RARLAB 的 `rar` 工具，该工具不随本项目分发。

使用或再分发前请阅读 [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md)。

## 致谢

- [7-Zip](https://7-zip.org) — Igor Pavlov
- [RARLAB](https://www.rarlab.com) — RAR 格式与 `rar` 工具
- Apple AppKit / FinderSync

## 反馈

欢迎提交 Issue 或 Pull Request。提交问题时请附上：

- macOS 版本与芯片架构（Apple Silicon / Intel）
- BingZip 版本
- 相关日志：`~/Library/Logs/BingZip/bingzip.log`

