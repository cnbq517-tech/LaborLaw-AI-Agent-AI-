# Repository guidance for coding agents

## Product

This repository contains two related clients:

- The original Python/NiceGUI desktop prototype at the repository root.
- The competition-oriented native HarmonyOS application in `harmony-app/`
  (HarmonyOS 7, target API 26, compatible API 23).

The HarmonyOS client runs without a project-owned server. It searches a bundled,
read-only legal index locally and calls a user-configured OpenAI-compatible API.
Evidence images are processed on the device with Core Vision Kit and Natural
Language Kit and never uploaded; only recognized text is sent to the model, and
only when the user asks.

## Important paths

- `harmony-app/entry/src/main/ets/pages/Index.ets`: main page (普法, 案件, 卷宗,
  设置 tabs, history drawer, citation and checklist sheets). It is large; put new
  self-contained features in `components/` instead of growing it.
- `harmony-app/entry/src/main/ets/components/EvidenceLibrary.ets`: 证据库
  (import, detail, compare slider, search, categories).
- `harmony-app/entry/src/main/ets/services/`:
  - `KnowledgeService.ets` / `KnowledgeEngine.ets` / `workers/KnowledgeWorker.ets`:
    local legal retrieval, running in a worker so the UI thread never parses the
    50MB index.
  - `AiApiClient.ets`: Chat Completions with SSE streaming and stop support.
  - `ChatStateStore.ets`: conversations, 普法 history and dossier on disk.
  - `CitationText.ets`: `[Kn]` citation chips, highlight, and copy text.
  - `EvidenceStore.ets`, `EvidencePipeline.ets` (save → super-resolution → OCR →
    index), `EvidenceIndex.ets` (textSearchImage), `EvidenceSearch.ets` (text +
    semantic merge), `EvidenceExtractor.ets` (categories, table rows, dossier
    fields, 证据清单 parsing).
- `harmony-app/entry/src/main/resources/rawfile/law_index.json`: generated index.
- `tools/kb_builder/`: offline corpus converter.
- `docs/contest/harmonyos7-release-notes.md`: change log with on-device
  verification records. Add an entry for user-visible changes.

## Safety rules

- Never commit API keys, signing files, signing passwords, local SDK paths, user
  conversations, attachments, evidence images, or DevEco caches.
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
- Prefer small changes and run the narrowest relevant checks.
- Keep pure logic (parsing, ranking, extraction) free of `@kit` imports so it can
  be tested with Node, as `CitationText`, `EvidenceSearch` and
  `EvidenceExtractor` are.

## ArkTS and HarmonyOS pitfalls seen in this project

- `@Builder` parameters passed by value do not refresh. A builder whose inputs
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
