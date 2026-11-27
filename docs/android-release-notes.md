# Android 版更新说明

## 2026-11-27 更新：发布「劳动法律 AI 智能体」Android 初版（v0.1.0-android）

全部新增代码位于 `android-app/`，文档更新位于 `AGENTS.md` 与 `docs/android-release-notes.md`；**未改动 `harmony-app/` 中的任何现有文件**。

### 架构与核心复用

- **技术路线**：Capacitor 6 + Vite + React 19 + TypeScript（`compileSdk 35` / `targetSdk 35` / `minSdk 24`）。
- **纯 TypeScript 逻辑零改动复用**：通过 `android-app/vite.config.ts` 的 `@harmony/*` 别名与 `src/shims/arkts-util.ts`（6 行 `TextDecoder` 垫片），直接编译复用 `harmony-app/entry/src/main/ets/` 中的无 `@kit` 核心模块：
  - 本地法规检索：`KnowledgeEngine`、`CitationText`、`ConversationPrompts`、`ConversationText`、`CaseArchive`、`ModelTuning`、`ThinkTagParser`；
  - 合同体检引擎：`ets/contract/` 全套 9 个文件（23 条红线规则 `R001–R023`、结构切分、省级最低工资表、`ContractPrivacy` 隐私脱敏、`ContractDocument` 高亮分段、`SampleContract`）；
  - 证据理解引擎：`Evidence.ets`、`EvidenceExtractor.ets`（表格行重组、自动分类、卷宗要素提取）。
- **零自建服务器 + 防跨域原生 SSE**：
  - 新增 `NativeStreamPlugin.java`（基于 `HttpURLConnection` 后台线程逐行推送 SSE 并支持中断），彻底绕过 Android WebView 调用 DeepSeek 等 OpenAI 兼容接口时的 CORS 限制；
  - 不打包 `builtin_service.json`，仅提供「我的」页自定义 API 配置（Base URL / Model / API Key 仅保存在本机）。
- **52MB 法规索引后台加载与兜底**：
  - `scripts/sync-assets.mjs` 构建前同步 `law_index.json` 至被 git 忽略的 `public/data/` 并压缩打包进 APK；
  - `src/workers/knowledge.worker.ts` 在独立 Web Worker 中加载与检索，首页「本地法规库」卡片实时显示进度与收录数量，失败时支持一键重试且不阻塞合同本地规则。

### 视觉复刻进度（对照鸿蒙 7 真机截图）

- **桌面图标与原版 SVG**：使用 `docs/contest/assets/laborlaw-ai-app-icon-source.png` 按 Android 自适应图标 108dp/72dp 安全区规范生成全部 `mipmap-*` 图标（暖米底 `#FEF7EE` 无裁切居中）；通过 `@harmony-media/*` 直接复用鸿蒙原版全部 `ic_*.svg` 图标。
- **全局导航与双主题**：完整复刻 `Theme.ets` 的「正义蓝 × 鎏金」浅色/深色双主题、118° 蓝金渐变天平头图（滚动 >16px 变毛玻璃）、底部 64px 悬浮毛玻璃胶囊导航 + 右侧独立圆形「我的」按钮。
- **四大核心页面**：
  - **普法**：首页「先把情况告诉我」圆角输入卡、常见问题 2×2 蓝金卡片、本地法规库状态卡、免责提示；对话页平铺正文、鎏金奶油底 `[Kn]` 引用芯片与原文高亮弹窗、思考过程折叠、`复制 / 复制含依据 / 依据 N 条` 胶囊、悬浮毛玻璃追问框；**左侧滑出式「历史咨询」抽屉**（支持主区域右滑避开系统侧滑返回、搜索分组与左滑删除）。
  - **维权**：蓝金头图内置三段切换（梳理 / 卷宗 % / 证据 N）、54px 环形卷宗完整度卡与六项要素胶囊、六项卷宗编辑与一键生成带引用维权报告。
  - **合同体检**：首页三入口卡与本地持久化审查记录；报告页顶部红线/高/中筛选与原文/清单切换、三色风险比例条、原文高亮点击弹窗、脱敏 AI 深度复核与底部「就这份合同继续问…」带入维权。
  - **我的**：全屏覆盖页（左上返回）、模型服务（预设/自动保存/连通性测试）、思考过程双开关、外观三段切换、本地法规库与本机记录统计及清空。

### 阶段 2 端侧能力

- **端侧离线中文 OCR 证据库**：集成 Google ML Kit 打包版中文识别（`com.google.mlkit:text-recognition-chinese:16.0.1`）与 IndexedDB 本地图片存储，原图永不上传；识别出的要素需用户逐项点击「填入卷宗」确认后才写入卷宗。
- **PDF（含扫描件）端侧识别**：基于 Android `PdfRenderer` 逐页渲染 + ML Kit 中文 OCR，合同体检已支持 `.docx`、`.pdf`（含扫描件）、`.txt` 以及「用证据库里的合同照片」。
- **系统分享接收图片**：`AndroidManifest.xml` 注册 `ACTION_SEND` / `ACTION_SEND_MULTIPLE`（`image/*`），从相册或聊天软件分享图片到本应用即可自动存入证据库并触发离线 OCR。

### 验证记录

- **编译与打包**：
  - `cd android-app && npm run build && npx cap copy android` 通过，Vite 打包与 Web Worker 构建正常。
  - `cd android-app/android && ./gradlew assembleDebug --no-daemon --console=plain`（OpenJDK 21 + Android SDK 35 + 阿里云 Maven 镜像）构建成功，产物为 `android-app/android/app/build/outputs/apk/debug/app-debug.apk`（含 `law_index.json` 与 `libmlkit_google_ocr_pipeline.so`，不含 `builtin_service.json`）。
- **真机安装与界面验收（OPPO / OnePlus `PKH110`，设备号 `7ee7eb32`）**：
  - 多轮增量版本均通过 `adb install -r` 覆盖安装并拉起成功。
  - 用户已在真机验收自适应桌面图标（修复安全区裁切后确认满意）、第 1 轮普法首页/底部毛玻璃导航、第 2 轮维权/合同体检/我的界面，以及左侧历史抽屉避开系统边缘返回手势的右滑交互。
- **未单独验证**：
  - 尚未在真机上完成全部端侧 OCR 复杂样张（模糊工资条、多页扫描 PDF 合同）的识别准确率回归测试、多机型/深色模式全页面交互回归测试，以及通过微信/相册多图系统分享的边界场景压测；安装与启动成功不等同于这些流程已全部验收。
  - 本次提交不包含 APK 安装包、密钥、签名文件或用户数据；Debug APK 作为 GitHub Release 附件单独提供。
