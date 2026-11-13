# BingZip 1.2

BingZip 是一款原生 macOS 压缩软件,界面与功能仿照经典 **7-Zip 文件管理器**,
核心压缩引擎直接编译自 7-Zip 26.05 官方 C++ 源码(完整格式支持版 `7zz`)。

> **版本 1.2** · 压缩引擎:7-Zip 26.05(`7zz`) · 制作者:谷谷 ·
> 个人网站:<https://bankok.pages.dev>

![BingZip](Resources/AppIcon.icns)

## 功能特性

### 界面(仿 7-Zip)
- **双面板文件管理器**:左右两个独立面板,可各自浏览文件夹或压缩包内容
- **工具栏**:打开、解压、新建、删除、测试(测试同时承担扫描:
  未选中压缩包时自动扫描当前文件夹中的全部压缩包)
- **智能地址栏**(重构版):
  - 面包屑导航:点击任意路径段直接跳转;层级过深时"…"菜单列出所有上层目录
  - 前进 / 后退 / 上一级按钮
  - ⭐ 常用位置菜单:主目录、桌面、下载、文稿、图片、音乐、影片、应用程序、iCloud Drive、宗卷、根目录、收藏夹
  - ✏️ 编辑完整路径:支持 `~` 展开和 `压缩包.7z//内部/路径` 语法
  - 压缩包内面包屑:点击压缩包名回根目录,点击子目录直接跳转
- **常用目录侧边栏**:每个面板左侧显示常用文件夹(主目录、桌面、下载、文稿、
  图片、音乐、影片、应用程序、iCloud Drive、宗卷、根目录)与收藏夹,
  单击即跳转;面板宽度不足 480pt 时**自动折叠**、拉宽后自动恢复;
  地址栏左侧的侧边栏按钮可手动折叠/展开,"查看 → 显示侧边栏"可全局切换
- **自适应折叠**:
  - 面包屑根据面板宽度自动减少显示段数(5→1 段),超出部分折叠为 `…` 菜单
  - 压缩对话框宽度不足 760pt 时,加密/分卷两列自动变为单列滚动布局
  - 所有对话框在缩小窗口时按钮始终固定可见
- **傻瓜式操作**:
  - 文件 → **快速压缩为 7z**(⌘⇧C):选中项一键压缩为同名 .7z,自动避免重名
  - 文件 → **快速解压到文件夹**(⌘⇧E):解压到同名文件夹,自动打开
  - **压缩完成后自动弹出 MD5 / SHA256**,可分别复制或一键复制全部
- **文件列表**:名称、大小、压缩大小、类型、修改时间、CRC、属性;点击列头排序
- **进度窗口**:实时进度条、百分比、速度、已用/剩余时间;
  **取消会真正终止引擎进程**,**后台运行**可隐藏窗口并从
  "工具 → 后台任务…"恢复查看;完成后提示并可查看结果
- **所有对话框可拉伸**:压缩/解压/关于等窗口均为
  "顶部标题 + 可滚动内容 + 固定底部按钮",小屏幕或拉伸时按钮永远不会被裁掉
- **状态栏**:对象数量与总大小
- **菜单栏**:文件 / 编辑 / 转到 / 查找 / 选项 / 视图 / 收藏夹 / 工具 / 帮助
- **收藏夹**:把常用文件夹加入收藏夹,菜单与地址栏⭐中一键跳转
- **右键菜单**:打开、添加、解压、测试、复制、粘贴、移动、删除、重命名、属性
- **触摸板手势**:文件列表与左侧目录树支持双指滚动;双指向右滑 = 后退,
  向左滑 = 前进;上下滚动保持系统自然滚动方向
- **键盘快捷键**(文件列表获得焦点时):Return / ⌘↓ 打开所选项目,
  ⌫ 上一级,⌘⌫ 移到废纸篓,F2 重命名;⌘[ / ⌘] 后退 / 前进,
  ⌘↑ 上一级;⌘⇧A 压缩,⌘E 解压,⌘T 测试,⌘⇧C 快速压缩,
  ⌘⇧E 快速解压;文本框编辑时 ⌘C / ⌘V / ⌘A / ⌘⌫
  自动回到文本操作,不会被文件操作抢占
- **版本信息窗口**:应用菜单 **关于 BingZip(版本信息)** 或
  **帮助 → 查看版本信息…**;包含版本、压缩引擎、个人网站、代码页设置、
  Finder 右键菜单状态与崩溃日志管理(不含制作者与长篇介绍)
- **Finder 右键扩展**:右键 →“压缩到压缩包”/“解压到…”只显示对应对话框,
  不打开主界面;“打开压缩包”才进入主界面浏览。
  启动时自动检查扩展是否启用(见下方 Finder 集成)

### 压缩(添加到压缩包)
- 格式:7z、Zip、Tar、GZip、XZ、BZip2、WIM;RAR(需安装 RARLAB 的 `rar` 工具)
- 压缩级别:存储、最快、快速、正常、最大、极限
- 压缩方法:LZMA2、LZMA、PPMd、BZip2、Deflate、Copy
- 字典大小、单词大小、CPU 线程数、固实压缩大小
- 内存使用估算显示
- 加密:密码 + 确认 + 加密文件名(7z);ZIP 自动使用 AES-256 强加密
- 分卷大小(字节/KB/MB/GB)
- 路径模式:相对 / 完整 / 绝对 / 无路径
- 排除通配符(`*.tmp; .DS_Store`)
- 压缩后删除源文件(-sdel)
- 存储符号链接(-snl)
- 自定义参数行(`-mqs -mcrc=on` 等)

> **RAR 压缩说明**:RAR 是专有格式,7-Zip 官方引擎只能解压、不能创建。
> 在“压缩”对话框选择 RAR 时,BingZip 会调用 RARLAB 官方的 `rar` 命令行工具
> (RAR5 格式)完成创建。可在 **设置 → RAR 压缩工具 → 选择 rar…** 指定工具路径,
> 或把它放到 `/usr/local/bin/rar`、`/opt/homebrew/bin/rar`,也可以设置
> `BINGZIP_RAR` 环境变量。未安装时会提示下载或一键改用 ZIP。

### 解压
- 解压到指定目录
- 路径模式:完整路径 / 无路径 / 移除前缀 / 按文件名附加
- 覆盖模式:覆盖 / 跳过 / 自动重命名解压文件 / 自动重命名已有文件
- 仅解压文件(不含目录结构,e 命令)
- 包含 / 排除通配符(`-i!*.txt`, `-x!*.tmp`)
- 密码输入
- 自定义参数

### 工具
- **测试**:校验压缩包完整性,完成后弹窗提示结果
- **基准测试**:可调字典大小与线程数,实时显示 7zz 评分输出
- **计算 CRC / 哈希**:CRC32、CRC64、SHA1、SHA256、BLAKE2sp、XXH64
- **属性对话框**:显示压缩包统计、条目大小/CRC/时间等
- **设置**:引擎信息、收藏夹管理

## 安全

### 加密能力(7-Zip 引擎)
- **7z**:AES-256 + 可选加密文件名(-mhe=on),隐藏压缩包内文件列表
- **ZIP**:WinZip 兼容的 AES-256(-mem=AES256),在对话框中输入密码即自动启用
- **完整性校验**:CRC32/CRC64、SHA-1/256/512、SHA3、BLAKE2、XXH64
- **压缩包测试**:`7zz t` 全量校验,发现损坏或密码错误立即提示

### 安全设计
- 密码仅保存在内存中,不写入磁盘、不显示在日志或错误信息里
- 解压使用 7-Zip 内置的路径清理逻辑,阻止 `../` 路径穿越写出目标目录
- 可选"存储符号链接"(-snl);默认跟随链接内容,避免还原出指向系统路径的链接
- "压缩后删除源文件"(-sdel)为显式可选,默认关闭
- 支持"排除模式",避免把 `.DS_Store`、临时文件或敏感文件打进包

### 已知限制
- 与 7-Zip 官方命令行一致,密码通过进程参数传递给引擎,同一用户的进程
  在压缩/解压瞬间可能看到参数值。对高敏感场景,建议压缩完成后清理终端
  历史与剪贴板,或使用加密文件名并妥善保管密码。
- RAR 创建依赖 RARLAB 的 `rar` 工具;该工具是独立软件,使用前请阅读并遵守
  RARLAB 的许可协议。BingZip 只在用户明确选择 RAR 格式时调用它。
- SFX 自解压模块是 Windows PE 格式(7z.sfx),macOS 版引擎无法生成可在
  Mac 上运行的 SFX;7z 压缩、分卷、加密在 macOS 上完整可用。

## 命令行工具

`dist/tools/` 下附带两个额外编译的引擎工具,它们也会被打包进
`BingZip.app/Contents/MacOS/tools/`,因此分享 App 时无需额外复制:

| 工具 | 说明 |
|------|------|
| `7zr` | 纯 7z 格式精简工具(创建/解压/测试 7z) |
| `lzma` | LZMA 压缩/解压转换工具 |

也可在 GUI 中使用 **工具 → 安装命令行工具…**,把完整引擎安装为
`~/.local/bin/bingzip`(即 7zz 的副本),然后:

```bash
bingzip a -t7z -mx=9 -pPASSWORD archive.7z files/
bingzip x archive.7z -o./out
bingzip l -slt archive.7z
```

## 日志与崩溃报告

- **运行日志**:`~/Library/Logs/BingZip/bingzip.log`
  记录每个压缩/解压/测试任务的启动参数、结果、耗时(密码自动脱敏为 `-p***`),
  文件超过 2MB 自动轮转
- **崩溃日志**:`~/Library/Logs/BingZip/crash-<会话>-*.log`
  捕获未处理的 Objective-C 异常与 `SIGSEGV/SIGABRT/SIGBUS/SIGILL/SIGFPE/SIGTRAP`
  致命信号,包含应用版本、macOS 版本、架构、引擎路径与调用栈
- **崩溃后自动报告**:上次运行崩溃时,下次启动会自动弹出崩溃报告窗口,
  说明崩溃类型并显示完整日志,可复制、导出或打开日志文件夹
- **查看**:应用菜单 **关于 BingZip(版本信息)** 或 **帮助 → 查看版本信息…**,
  可看到全部日志文件、大小和修改时间
- **导出日志**:在版本信息或设置页点“导出日志…”,选择保存位置后会生成
  一个 ZIP(内含完整日志文件夹),方便反馈问题
- **完全清除所有日志**:版本信息、设置页或 **帮助 → 完全清除所有日志…**,
  二次确认后会永久删除运行日志与全部崩溃日志,不可撤销
- **入口**:**帮助 → 打开日志文件夹**,或设置页中的“打开日志文件夹”
- **引擎启动自检**:每次启动验证 7zz 存在且可运行,失败时弹出明确错误提示

## 权限（一次性统一授权）

macOS 的 TCC 会分别询问“桌面 / 文稿 / 下载 / 外接磁盘 / 网络卷”的访问权限,
逐个授权很麻烦。BingZip 提供统一入口,但受系统限制,**应用不能自己授予敏感权限**,
需要用户在系统设置中手动开启一次:

- **启动提示**:启动时统一检查 Finder 右键菜单与完全磁盘访问,
  两项状态合并在同一个窗口中提示,不再分两次弹窗
- **完全磁盘访问**:一次开关覆盖桌面、文稿、下载、外接磁盘和网络卷,
  之后扫描、压缩、解压不会再逐文件夹询问
- **入口**:应用菜单 / 帮助 → **权限设置…**,或版本信息、设置页中的“权限设置…”按钮
- **操作**:打开系统设置 → 隐私与安全性 → 完全磁盘访问,
  点“+”选择 BingZip.app(或从 Finder 拖入),打开开关,
  **退出并重新启动 BingZip**
- **扫描前检查**:未开启完全磁盘访问时,扫描会先提示统一授权,
  可选择“打开权限设置 / 仍然扫描 / 取消”
- **Finder 右键菜单**:独立开关,可在权限设置中一键启用

> macOS 不允许任何 App 通过代码批量授予 TCC 权限,否则会形成安全绕过。
> 因此“一次性统一授权”在实现上等于:统一入口 + 一次完全磁盘访问开关。


- **Universal 2 构建**:GUI、7zz 引擎、7zr/lzma 工具同时包含 `arm64`(Apple Silicon)
  与 `x86_64`(Intel)两个架构,可直接在任意现代 Mac 上运行
- **最低系统**:macOS 11.0(Big Sur)及以上
- **基本无外部依赖**:7z/ZIP 等格式的引擎与工具全部内置,不需要安装 7-Zip 或 Homebrew;
  仅“创建 RAR”需要额外安装 RARLAB 的 `rar` 工具(解压 RAR 无需安装)
- **自包含分享**:`7zz`、`7zr`、`lzma` 与 Finder 右键扩展都在 App 包内,
  直接分享 `BingZip.app` 或构建生成的 ZIP/DMG 即可,不依赖项目目录
- **首次打开**:App 使用 ad-hoc 签名;若从网络传输后被 Gatekeeper 阻止,
  右键 → 打开,或执行 `xattr -dr com.apple.quarantine /path/to/BingZip.app`
- **配置**(收藏夹、显示隐藏文件)保存在本机 UserDefaults,不会跨设备同步;
  压缩包本身为 7z/ZIP 等标准格式,在 Windows / Linux / macOS 之间通用
- 验证架构:`lipo -archs BingZip.app/Contents/MacOS/BingZip`
  应输出 `x86_64 arm64`

## Finder 集成(桌面右键)

BingZip 内置 **Finder Sync 扩展**,首次启动会自动检查右键菜单是否启用:

- **右键 → 压缩到压缩包**:只弹出压缩对话框(完整参数),确认后直接压缩,
  **不会打开主界面**
- **右键 → 解压到…**:只弹出解压对话框,可先调整目标目录 / 路径模式 /
  覆盖方式,再开始解压,**不会打开主界面**(单选一个压缩包时显示)
- **右键 → 打开压缩包**:在 BingZip 中浏览选中的压缩包(仅对压缩包显示),
  可继续解压;这是唯一会进入主界面的右键命令
- **启动自检**:每次启动检查扩展状态;未启用时会弹出说明,
  可“一键启用”或跳转到系统设置
- **手动检查**:**帮助 → 检查右键菜单状态…**,或版本信息 / 设置页中的
  “检查 / 启用…”按钮
- **关闭自检**:设置 → Finder 右键菜单 → 取消“启动时检查右键菜单”;
  启动提示中勾选“启动时不再检查”同样有效
- **手动启用**:系统设置 → 通用 → 登录项与扩展 → 访达扩展 →
  打开“BingZip 右键菜单”
- **拖拽**:把文件/文件夹拖到 BingZip 窗口任意面板 → 弹出压缩对话框;
  把压缩包拖入 → 直接在面板中浏览其内容
- **打开方式**:双击或"打开方式 → BingZip"打开压缩包

> 扩展随 App 一起构建并签名,位于 `BingZip.app/Contents/PlugIns/BingZipFinder.appex`。
> 首次启用后如 Finder 中未立即出现菜单,重新右键或重启 Finder 即可。
> 建议把 BingZip.app 放到“应用程序”文件夹后再启用右键菜单,避免移动 App 后失效。
>
> 通过右键“压缩到压缩包”或“解压到…”冷启动时,BingZip 只显示对应对话框;
> 关闭对话框后应用仍驻留 Dock,点击 Dock 图标即可打开主界面。

### 文件管理
- 新建文件夹、重命名、删除(废纸篓)
- 面板间复制 / 移动 / 粘贴
- 压缩包内条目:删除、重命名、复制(解压到目标面板)、双击打开(临时解压)

### 压缩包格式支持
- 压缩 / 解压:7z、XZ、BZIP2、GZIP、TAR、ZIP、WIM
- RAR:解压由内置 7-Zip 引擎直接支持;创建需安装 RARLAB `rar` 工具(见上方说明)
- 仅解压:AR、ARJ、CAB、CHM、CPIO、CramFS、DMG、EXT、FAT、GPT、HFS、
  IHEX、ISO、LZH、LZMA、MBR、MSI、NSIS、NTFS、QCOW2、RAR、RPM、SFX、
  SquashFS、UDF、UEFI、VDI、VHD、VMDK、XAR、Z 等

## 构建

要求:macOS 11+、Xcode Command Line Tools、GNU make。

```bash
cd BingZip
./build.sh release
open dist/BingZip.app
```

构建脚本会:
1. 若 `CPP/7zip/Bundles/Alone2/b/m_arm64/7zz` 不存在,先用官方 makefile 编译引擎
2. 编译 `7zr` 与 `lzma` 两个命令行工具
3. `swift build -c release` 编译 Swift/AppKit GUI
4. 用 `swiftc -application-extension` 编译 Finder Sync 右键菜单扩展
5. 组装自包含的 `dist/BingZip.app`:
   GUI、`Contents/MacOS/7zz`、`Contents/MacOS/tools/7zr`、
   `Contents/MacOS/tools/lzma`、Info.plist、图标与
   `Contents/PlugIns/BingZipFinder.appex`
6. 依次对 7zz、工具、扩展(带沙盒 entitlements)和 App 做 Ad-hoc 签名
7. 自动生成可直接分享的 ZIP / DMG 与校验和

## 分享与分发

每次执行 `./build.sh release` 后,`dist/` 会生成:

| 文件 | 说明 |
|------|------|
| `BingZip-1.2-macos-<arch>.zip` | 自包含 App(含引擎、工具、右键扩展) |
| `BingZip-1.2.dmg` | 带“应用程序”快捷方式与 `README-FIRST.txt` 的安装镜像 |
| `SHA256SUMS.txt` | 上述文件的 SHA-256 校验和 |
| `BingZip.app` | 本地直接运行 / 归档用 |

接收方只需要:
1. 打开 DMG,把 `BingZip.app` 拖到“应用程序”;
2. 首次打开如果提示“无法验证开发者”,右键 → **打开**;
   或执行 `xattr -dr com.apple.quarantine /Applications/BingZip.app`;
3. 首次启动按“权限设置…”完成 Finder 右键菜单与完全磁盘访问。

> 当前构建使用 **Ad-hoc 签名**(本机没有 Developer ID 证书),因此无法自动通过
> Gatekeeper 公证。要做到“下载后双击无提示”,需要 Developer ID Application
> 证书并对 App/DMG 做 notarization;这属于签名证书配置,不影响 App 内引擎与依赖的完整性。
> RAR 创建仍需 RARLAB 的 `rar` 工具,该工具许可证不允许随 App 分发。

## 目录结构

```
BingZip/
├── Package.swift              # SPM 工程
├── build.sh                   # 一键构建 + 打包 .app
├── Sources/BingZip/
│   ├── main.swift             # App 入口
│   ├── AppDelegate.swift      # 菜单栏与窗口管理
│   ├── Core/
│   │   ├── SevenZip.swift     # 7zz / 外部工具进程封装、列表解析、进度解析
│   │   ├── ArgsBuilder.swift  # 命令行参数构建、级别/方法/内存估算
│   │   ├── RarTool.swift      # RARLAB rar 工具定位与 RAR 创建参数
│   │   ├── AppInfo.swift      # 版本、网站等元数据
│   │   ├── AppLogger.swift    # 运行/崩溃日志、导出与清除
│   │   ├── CodePage.swift     # Zip 文件名编码代码页选项
│   │   ├── FinderIntegration.swift # Finder 右键菜单状态、注册与启用
│   │   ├── SystemPermissions.swift # 完全磁盘访问检测、统一授权与扫描前检查
│   │   └── Models.swift       # 条目模型、格式识别、大小格式化
│   └── UI/
│       ├── MainWindowController.swift  # 双面板主窗口 + 工具栏
│       ├── FilePanel*.swift            # 单面板(浏览/列表/操作)
│       ├── AddDialog*.swift            # 压缩对话框
│       ├── ExtractDialog.swift         # 解压对话框
│       ├── ProgressWindow.swift        # 进度窗口
│       ├── OperationRunner.swift       # 异步操作调度
│       ├── BenchDialog.swift           # 基准测试
│       ├── HashDialog.swift            # CRC/哈希
│       ├── InfoDialog.swift            # 属性
│       ├── SettingsDialog.swift        # 设置(引擎、RAR、日志、权限、收藏夹)
│       ├── PermissionsDialog.swift     # 一次性统一权限设置窗口
│       ├── TextInputDialog.swift       # 通用输入框
│       ├── LogActions.swift            # 日志导出 / 完全清除
│       ├── CrashReportDialog.swift     # 下次启动自动显示崩溃报告
│       └── AboutDialog.swift           # 版本信息、代码页、右键菜单状态与崩溃日志
├── FinderSync/
│   ├── FinderSync.swift       # Finder Sync 扩展(压缩到压缩包 / 打开压缩包)
│   ├── Info.plist             # 扩展声明(com.apple.FinderSync)
│   └── BingZipFinder.entitlements # 扩展沙盒权限
├── Resources/
│   ├── Info.plist             # Bundle 配置(显示名 BingZip)
│   ├── AppIcon.icns           # 应用图标
│   └── AppIcon.iconset/       # 图标源文件
└── tools/gen_icon.swift       # 图标生成脚本
```

## 引擎

`7zz` 由本仓库 7-Zip 26.05 源码编译:

```bash
cd CPP/7zip/Bundles/Alone2
make -f ../../cmpl_mac_arm64.mak -j8
```

## 许可

压缩引擎为 7-Zip(Igor Pavlov),遵循 GNU LGPL 与 unRAR 许可限制。
GUI 外壳代码由 BingZip 项目提供,制作者:谷谷。
RAR 创建功能调用 RARLAB 的 `rar` 工具,该工具由 RARLAB 单独授权,不随本应用分发。
