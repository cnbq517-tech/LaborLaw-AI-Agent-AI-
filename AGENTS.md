# Repository guidance for coding agents

## Product

This repository contains two related clients:

- The original Python/NiceGUI desktop prototype at the repository root.
- The competition-oriented native HarmonyOS application in `harmony-app/`
  (HarmonyOS 7, target API 26, compatible API 23).

The HarmonyOS app is named 劳动法律 AI 智能体 (since 2026-11-09): the 普法 hero,
the onboarding brand page, the desktop card title, the copy footer,
`app_name` and `EntryAbility_label` (desktop icon label, share sheet) all use
it. The desktop truncates the icon label to 劳动法律 AI 智… on a phone; the
team accepted that. The icon image is unchanged. The 2×2 card title is 12vp with the tip chip reduced to ✦ so the
longer name fits on one line.

The HarmonyOS client runs without a project-owned server. It searches a bundled,
read-only legal index locally and calls an OpenAI-compatible API: a built-in
service shipped with the build (100 requests a day per device), or one the user
configures in 我的.
Evidence images are processed on the device with Core Vision Kit and Natural
Language Kit and never uploaded; only recognized text is sent to the model, and
only when the user asks.

## Important paths

- `harmony-app/entry/src/main/ets/pages/Index.ets`: main page. The floating tab
  bar has 普法, 维权 (梳理 · 卷宗 · 证据 pages) and 合同; 我的 (settings) is the
  round HdsTabs mini bar beside it and opens as a cover. Every section and 我的
  has its own system title bar (HdsNavigation); Index keeps the tabs, the one
  sheet host (citation, checklist, cases), routing, persistence and sending;
  the pages are components. Put new self-contained features in
  `components/` instead of growing it.
- `harmony-app/entry/src/main/ets/models/`: `AppEnv` (theme, model settings,
  keyboard; provided to components as `@Provide('env')`), `ChatSession` (one
  conversation: messages, input, streaming, layout, reading mode), `CaseState`
  (the current 维权 case), `DrawerState`, and `ChatState` (what is saved).
- `harmony-app/entry/src/main/ets/components/chat/`: `ChatViews.ets` holds the
  conversation pieces 普法, 维权 and the dossier report share (answer text with
  citation chips, actions, reasoning, streaming, pinned composer, jump button,
  the folded composer button); `Conversation.ets` is a whole conversation page
  with the reading mode. Components ask the page for things through small
  action classes (`ChatActions`, `ConversationEvents`, ...).
- `harmony-app/entry/src/main/ets/components/MinePage.ets`, `HistoryDrawer.ets`,
  `DossierPage.ets`: 我的, the 普法 history drawer, and 维权 · 卷宗.
- `harmony-app/entry/src/main/ets/components/BrandBar.ets`: the blue band
  (gradient and scale watermark) behind a title bar at the top of a page, and
  `SCROLLED_PAST`, how far a page scrolls before its bar turns to glass.
- `harmony-app/entry/src/main/ets/services/KnockShare.ets`: evidence between
  devices. 碰一碰 (Share Kit `knockShare` on the phone's evidence library,
  `dataReceive` sandbox receive on a tablet), the system share panel for
  华为分享, and reading images shared into the app.
- `harmony-app/entry/src/main/ets/components/Onboarding.ets` (welcome pages),
  `DemoGuide.ets` (引导式演示 step card, opening and summary), and
  `services/DemoScript.ets` (the five steps, sample inputs, backup loading),
  `DemoData.ets` (直接查看示例结果), `DataSpace.ets` (which directory records
  live in).
- `harmony-app/entry/src/main/ets/components/ContractReview.ets`: 合同体检
  (import, facts, report, clause view), embedded as the 合同 section.
- `harmony-app/entry/src/main/ets/components/EvidenceLibrary.ets`: 证据库
  (import, detail, compare slider, search, categories).
- `harmony-app/entry/src/main/ets/services/`:
  - `KnowledgeService.ets` / `KnowledgeEngine.ets` / `workers/KnowledgeWorker.ets`:
    local legal retrieval, running in a worker so the UI thread never parses the
    50MB index.
  - `AiApiClient.ets`: Chat Completions with SSE streaming and stop support.
  - `ChatStateStore.ets`: conversations, 普法 history and dossier on disk.
  - `CitationText.ets`: `[Kn]` citation chips, highlight, and copy text.
  - `ConversationPrompts.ets`, `ConversationText.ets`, `CaseArchive.ets`: prompts,
    history titles and grouping, case archiving; pure logic.
  - `ModelQuota.ets` (pure) and `ConfigStore.ets`: the built-in service's daily
    allowance and key encoding, and loading `rawfile/builtin_service.json`.
  - `ModelTuning.ets` (pure): sampling per request kind. DeepSeek requests carry
    no temperature (its thinking mode ignores it, and the app keeps thinking on
    to show reasoning); other services get 0.3 for answers, 0.1 for JSON.
- `harmony-app/entry/src/main/ets/theme/Material.ets`: 沉浸光感 in one place —
  support check (API 26 and the device), the material for sheets, dialogs,
  toasts and toggles, the HdsTabs level from 我的 → 光感强度, and the glass look
  for floating controls in the content area. `Light.ets` is the point light.
  光感强度 defaults to 强 (since 2026-11-09). On ALN-AL00, 自适应 picks a level
  that turns the title bar buttons a flat frosted white. The setting is stored
  under `light_level_v2`; the key was renamed so devices that had saved 自适应
  start at 强 once.
  - `EvidenceStore.ets`, `EvidencePipeline.ets` (save → super-resolution → OCR →
    index), `EvidenceIndex.ets` (textSearchImage), `EvidenceSearch.ets` (text +
    semantic merge), `EvidenceExtractor.ets` (categories, table rows, dossier
    fields, 证据清单 parsing).
- `harmony-app/entry/src/main/ets/contract/`: contract review engine, pure logic
  (no `@kit` imports): structure audit and anchors, red-line rules, model prompt
  and reply checks, privacy masking, law-name mapping, and the provincial
  minimum wage table (`MinimumWages.ets`; update it with its source date).
  `ContractDocument.ets` lays out the annotated contract text (highlights by
  finding offsets); `SampleContract.ets` is the built-in fictional contract,
  whose expected findings are pinned in the rule cases.
  `services/ContractReviewService.ets` adds file reading (DOCX, PDF with OCR for
  scanned pages), the AI pass and local storage.
- `harmony-app/entry/src/main/resources/rawfile/law_index.json`: generated index.
- `tools/kb_builder/`: offline corpus converter. `add_documents.py` appends the
  official texts listed in `supplements.json` without a full rebuild.
- `tools/harmony/contract-rules/`: contract rule cases, run with Node.
- `tools/harmony/logic-tests/`: cases for the pure conversation and case logic.
- `tools/harmony/builtin-service/set.sh`: writes the built-in service file from
  a key typed at a hidden prompt (`--remove` deletes it).
- `docs/contest/harmonyos7-release-notes.md`: change log with on-device
  verification records. Add an entry for user-visible changes.

## Safety rules

- Never commit API keys, signing files, signing passwords, local SDK paths, user
  conversations, attachments, evidence images, or DevEco caches.
- `harmony-app/entry/src/main/resources/rawfile/builtin_service.json` holds the
  built-in service's key. It is git-ignored; never commit it, copy it into
  another path, or print the decoded key. Its encoding only stops casual
  extraction from the package: use a key made for the app with a small balance
  and a spending alert. Builds without the file offer only the user's own
  service.
- Keep `build-profile.json5` free of machine-specific signing material. Local
  signing may live in a working copy only; check `git diff` before committing.
- Treat source corpora as read-only inputs; generated indexes belong under the
  HarmonyOS raw resources directory.
- Preserve source name, article, and status metadata for citations.
- Keep the visible legal disclaimer and the corpus-validity warning.
- Recognized evidence values are never written into the dossier automatically;
  the user confirms each one (OCR makes mistakes even on clear images).

## Engineering rules

- Preserve both quick consultation and case-analysis modes.
- Keep multi-turn context and validate model citation IDs before display.
- Handle missing configuration, timeouts, HTTP failures, malformed JSON, and
  large attachments without crashing.
- Do not add a project server unless a task explicitly changes the architecture.
- Every request to the built-in service goes through `takeModelRequest` (daily
  allowance and a 2-second gap) and gives it back with `returnModelRequest` when
  it fails before any answer; requests to the user's own service are not
  counted.
- Prefer small changes and run the narrowest relevant checks.
- Keep pure logic (parsing, ranking, extraction) free of `@kit` imports so it can
  be tested with Node, as `CitationText`, `EvidenceSearch` and
  `EvidenceExtractor` are.

## ArkTS and HarmonyOS pitfalls seen in this project

- `@Builder` parameters passed by value do not refresh (seen again in the
  contract finding sheet's 上一处 / 下一处 and the 维权 segment labels). A builder whose inputs
  change with state (theme colors, for example) must take a single object
  literal so it is passed by reference, like `this.Icon({ res, size, color })`.
- Object literals cannot construct classes that declare constructors
  (`arkts-no-untyped-obj-literals`); use an `interface` for such parameters.
- Structural typing is not supported: cast explicitly, e.g.
  `bytes.buffer as ArrayBuffer`.
- `Span` supports only `onClick`/`onHover`; use `textBackgroundStyle` for chip
  backgrounds. Selection offsets reported by `Text` count rendered span text, so
  copy mapping must use the same chip label (`CitationText.chipLabel`).
- Core Vision Kit does not allow concurrent calls to the same capability; route
  OCR, super-resolution and textSearchImage through their serial queues.
- Core Vision Kit, Vision Kit and textSearchImage do not run on the emulator and
  only work in mainland China. Super-resolution needs 16px < side < 2048px;
  textSearchImage applies its own similarity threshold (about 0.31–0.34 on the
  test device) and returns error `1013100003` when its index must be rebuilt.
- Component-level `systemMaterial` rendered transparent on the test device
  (HarmonyOS 7.0.0.109); the light effects use HDS `hdsEffect.pointLight` and a
  self-drawn glow instead.
- Scroll containers center short content by default; add `.align(Alignment.Top)`.
- One component holds one bound sheet and one bound content cover: a second
  `bindSheet` or `bindContentCover` on the same component never opens. Merge
  sheets into one with a kind field, or bind the extra cover to a zero-size node.
- `@State`/`@Prop` names must not clash with base component members such as
  `position`.
- Hide the HdsTabs floating bar with `applyHideAnimation` /
  `applyShowAnimation` on the controller; `bindScroller` with a scroller from a
  child component did nothing on the test device.
- After a page or cover transition the first injected tap is often lost; tap
  again before concluding that a control does not work.
- Evidence moves between devices two ways. 碰一碰 (phone knocks a tablet)
  only works on device pairs the system supports; the test MatePad (MRO-W00)
  does not, in any app, though both sides register fine. Verified working
  between ALN-AL00 (phone) and WKI-W00 (MatePad); the gold ripple shows
  after the system's own white ring. 华为分享 works
  everywhere: the phone sends through the share panel, the tablet's gallery
  receives it, and the app is a share target for images (`sendData` skill
  with `general.image` in module.json5), so 分享 → 本应用 stores them in the
  evidence library. EntryAbility puts shared URIs in AppStorage
  (`sharedEvidence`); Index routes them, and items from 碰一碰 or a share are
  marked 来自手机 / 分享存入. Plain 华为分享 never reaches `dataReceive`.
- 新手引导: a user with no saved records sees the welcome pages once and the
  快速上手 card on the 普法 home (tasks tick off from real actions); 维权,
  证据 and 合同 show a one-time hint. Flags live in the `model_config`
  preferences (`onboarded`, `quickstart_tasks`, `quickstart_hidden`,
  `hints_seen`); 我的 → 新手引导 replays or resets them.
- 演示模式 keeps its records in `files/demo` (`DataSpace.root`, read once in
  `EntryAbility.onCreate`); switching restarts the app (`restartApp`) and
  leaving deletes that directory, so the user's records are never touched.
  Every store must build its paths from `DataSpace.root`, not `filesDir`.
  引导式演示 leaves sending to the presenter and calls the model for real;
  when nothing streams within 5 s (or the call fails) the step card offers a
  backup from `rawfile/demo/backups.json`. Those backups must come from real
  calls: run the demo on a device and pull `files/demo/*.json`; never write
  them by hand. Backups are marked 【备用结果 · 事先真实调用生成】.
  Step 3 shows 图像超分: the sample `rawfile/demo/payslip.jpg` is a 432×528
  compressed copy, so import enhances it automatically (short side under
  1080), and on device its original misreads amounts (2.600.00, 000元) that
  the enhanced image reads right. A replacement must be checked the same way
  on a device. The step card ticks off `DEMO_EVIDENCE_TASKS` (enhanced and
  recognized via `EvidenceLibrary.onRecognized`, slider tried via
  `onCompared`, 月薪 filled); only the last finishes the step.
- A `@Builder`'s primitive argument is a copy: a value changed elsewhere does
  not re-render it. Read state inside the builder (`DossierPage.fieldValue`),
  or make the piece a `@Component` with `@Prop`s (`DemoButton`). An overlay
  with `HitTestMode.Transparent` passes taps on its children through to the
  page below as well; place overlays with `.position` instead of padding.
- With several devices connected, pass `hdc -t <id>`. Debug signing is manual
  (AppGallery Connect certificate and a profile listing each device's UDID,
  `hdc shell bm get --udid`); add a device by adding it to the profile and
  replacing the `.p7b`, so installed copies update without an uninstall. The
  signing files and passwords stay out of the repo. After a reinstall the
  phone refuses `hdc file send -b` until the app has been launched once.
- The system material (`systemMaterial`) only takes effect on the Navigation
  title bar, a bottom TabBar, dialogs and sheets, toasts, Slider and Toggle; on
  any other component it renders transparent. The level is settable only for
  HDS components (`systemMaterialEffect.materialLevel`); for the rest the
  system picks it. Behind a floating HdsTabs bar, `gradientMask` and an opaque
  strip under the composer hide the glass entirely.
- Self-drawn glass: give `backgroundBlurStyle` the app's color mode
  (`Material.blurOptions`), or it follows the system and turns white when the
  app is dark and the system light. A point light on a small Button lights it
  up white in dark mode. A child with `width('100%')` plus side margins overflows
  the screen; put the side room on the parent as padding.
- Title bars are HdsNavigation over the content (`ignoreLayoutSafeArea` top,
  `avoidLayoutSafeArea` on the bar), bound with `bindToScrollable`. At the top
  of a page the bar is clear with white title and buttons over blue (普法's
  header, elsewhere a `BrandBar`); once the page scrolls it turns to the
  system's glass with dark ones, the band fades, and the status bar text turns
  dark (`syncStatusBar` in Index). 维权's page switch shows at the top only; the
  contract filters stay on the glass. The content runs under the bar: pages
  without 普法's header pad their top by status bar (read from the window) +
  title row (56) + any bottom area.
- The bar's glass state is shared by every scroller it is bound to and only
  changes on scroll events: bind only the scroller of the page shown (维权's
  tabs, the contract's modes and views) and track `scrolled` per page, or the
  bar keeps one page's glass on another. After replacing the content (back to
  the home), scroll the bound scroller to the top. Its visibility follows the
  page's immersive state (a tap), never scrolling. Do not put a color layer in
  `stackBuilder`: it covers the bar's buttons. ArkTS rejects a ternary between
  two untyped object literals here; build `backIcon` / `bottomBuilder` options
  in typed helpers.
- 普法 and 维权 · 梳理 keep the tab bar and composer while scrolling
  (`scrollToRead: false`); only a tap (immersive reading) hides them. The
  contract report still folds them on scroll.
- Tablets. `AppEnv.windowWidth` (vp, from the window) drives three things:
  `side()` centers content in a column of `CONTENT_MAX` (840), `wide()`
  (from 600) switches tablet details (four scenario cards per row, close
  buttons, centered sheets), `split()` (from 1000, a tablet held sideways)
  shows two panes: 普法 history docked left (`HistoryDrawer` `docked`), 维权
  梳理 with 卷宗 / 证据 beside it, the contract text with its findings beside
  it. Components that sit in a pane take a `side` override instead of
  `env.side()`. The docked history's blue header runs into the conversation's
  `BrandBar`: its gradient ends in `headerA`, where the `BrandBar` starts, and
  its right divider starts below the header, or a light seam shows between the
  panes. On a tablet `EntryAbility` draws everything 12% larger with
  `setCustomDensity` (following the system's display size). Phones are
  unchanged; check both after layout changes.
- HdsTabs on a wide window puts the bar at one edge and the mini bar (我的) at
  the other; equal `barSideMargin`s bring them together in the middle.
  `adaptToHandedness` pushes the bar to one side, so it is off on tablets.
- `bindSheet` with `onWillDismiss` closes only through `action.dismiss()`;
  without it a tablet's centered sheet stays as an empty frame. On a tablet a
  sheet defaults to a popup by the finger with no mask; use
  `SheetType.CENTER` with `showClose` there, and `Material.dialog(isDark,
  true)` so the page does not show through its text.
- Narrow phone windows: `Index.fittingBarWidth` caps each floating bar width
  at the available window width minus both side margins, the 64vp 我的 mini
  bar and a 12vp gap. Keep the original widths when they fit; keep the tablet
  layout unchanged. Use `AppEnv.windowWidth` in vp, not physical screen pixels
  or model-specific checks. Recheck narrow phones and wide/tablet layouts when
  changing the floating bar, and preserve keyboard hide/show behavior.
- HdsTabs floating style fields keep their last value when left out of a new
  style: the keyboard style sets `barOpacity: 0`, so the normal style must set
  `barOpacity: 1` or the bar stays invisible after the keyboard closes.
- A `floatView` (闪控窗, `ROUNDED_RECTANGLE`) gets a system bar drawn over the
  top of its window: collapse, app icon and name, close. `FloatChecklist`
  starts its content `FLOAT_SYSTEM_BAR` (36vp, measured on ALN-AL00) down and
  has no close button of its own. The six checklist items are a 2×3 grid of
  28vp tiles; nothing scrolls. `ChecklistFloatService` sizes the window to the
  content, 350 × 272vp with the system bar (`getFloatViewLimits` is in px),
  within the size and ratio limits: a phone's largest window (ALN-AL00, about
  349vp wide) is about that, a tablet's (MRO-W00, 622 × 467vp) left the
  content in white space.
- `Text` with `copyOption` keeps taps for itself (its parent's `onClick` does
  not fire), and a `Span` with `onClick` takes taps for the line around it.
  Give only tappable spans a handler, and route taps on selectable text through
  an explicit callback (`ChatActions.tapped`).
- AppGallery can block a debug-signed app on the device (`DisposedRule`, 「应用已
  过期」) while its certificate and profile are valid. A new signature needs an
  uninstall, which clears the app's data; back it up first with
  `hdc file recv -b com.laborlaw.aiassistant /data/storage/el2/base <dir>` (and
  `/data/storage/el2/database`) and send it back with `hdc file send -b` before
  the first launch. The Asset Store API key cannot be copied this way.
- Anything that changes a scroll area's size while it scrolls can feed back
  into the scroll. The header collapses by 88vp and the reading mode hides the
  composer, tab bar and 维权 bars; a page only a little taller than its viewport
  then fits, snaps back to the top and opens everything again. Both only engage
  when the content has room to spare (`headerProgressAt`, `trackReading`).
- `onDidScroll` reports `ScrollState.Idle` for scrolls made through a
  `Scroller`; use that to ignore the app's own scrolling. With
  `EdgeEffect.Spring`, a fling past the top springs back with downward deltas,
  so ignore deltas near the top; `onReachStart` also fires for programmatic
  scrolls.

## Verification

For HarmonyOS changes, build with DevEco Studio 26 (adjust the path if it is
installed elsewhere):

```bash
cd harmony-app && D=/Applications/DevEco-26/DevEco-Studio-26.app/Contents && JAVA_HOME=$D/jbr/Contents/Home DEVECO_SDK_HOME=$D/sdk PATH=$D/jbr/Contents/Home/bin:$D/tools/node/bin:$PATH $D/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

`./tools/harmony/build-debug.sh` builds an unsigned HAP. Installing on a device
needs local signing; then install with:

```bash
/Applications/DevEco-26/DevEco-Studio-26.app/Contents/sdk/default/openharmony/toolchains/hdc install -r harmony-app/entry/build/default/outputs/default/entry-default-signed.hap
```

For contract review rule changes, run the cases (Node 22.6+ runs the TypeScript
directly):

```bash
./tools/harmony/contract-rules/run.sh
```

The conversation and case logic has its own cases (the script falls back to the
Node bundled with DevEco Studio when the system Node cannot transform types):

```bash
./tools/harmony/logic-tests/run.sh
```

Compliant cases expect no findings, so they catch false positives; every law
reference a rule cites must resolve to an article in `law_index.json`.

1. Test the affected flow on a HarmonyOS 7 (API 26) device. Evidence features
   cannot be tested on the emulator.
2. `hdc shell uitest dumpLayout` and `snapshot_display` are useful for checking
   UI state; the system photo picker rejects injected taps, so imports need a
   person on the device.
3. Do not commit HAP files or signing material.
4. Record what was verified on device, and what was only compiled, in the
   release notes.

For Python changes:

1. Run the relevant test file or `python -m unittest discover -s tests`.
2. Keep generated corpus files and user data out of Git.
