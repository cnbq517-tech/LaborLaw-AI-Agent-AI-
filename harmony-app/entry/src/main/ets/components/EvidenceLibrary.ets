import { common } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { DocType, DocumentScanner, DocumentScannerConfig, FilterId, SaveOption } from '@kit.VisionKit';
import {
  ENHANCE_DONE,
  ENHANCE_FAILED,
  EVIDENCE_DONE,
  EVIDENCE_ENHANCING,
  EVIDENCE_FAILED,
  EVIDENCE_INDEXING,
  EVIDENCE_PENDING,
  EVIDENCE_RECOGNIZING,
  EVIDENCE_SOURCE_PHOTO,
  EVIDENCE_SOURCE_SCAN,
  EvidenceItem,
  ExtractedField,
  INDEX_DONE,
  INDEX_FAILED,
  INDEX_NONE,
  INDEX_SKIPPED
} from '../models/Evidence';
import { EvidenceIndex, SemanticHit } from '../services/EvidenceIndex';
import { EvidencePipeline } from '../services/EvidencePipeline';
import { CAT_CHAT, CAT_OTHER, EVIDENCE_CATEGORIES, EvidenceExtractor } from '../services/EvidenceExtractor';
import { EvidenceSearch, SearchResult } from '../services/EvidenceSearch';
import { EvidenceStore } from '../services/EvidenceStore';
import { ThemeColors } from '../theme/Theme';

export const EVIDENCE_MODE_LIST: number = 0;
export const EVIDENCE_MODE_DETAIL: number = 1;
export const EVIDENCE_MODE_SCANNER: number = 2;

const MAX_PICK: number = 9;
const MAX_SHOTS: number = 10;
const SCAN_SUCCESS: number = 200;
const SEARCH_DELAY: number = 300;
const FIELD_LABELS: string[] = ['案件发生地', '单位名称', '平均月薪', '时间节点'];

function cloneItem(source: EvidenceItem): EvidenceItem {
  const item: EvidenceItem = new EvidenceItem();
  item.id = source.id;
  item.source = source.source;
  item.createdAt = source.createdAt;
  item.fileName = source.fileName;
  item.width = source.width;
  item.height = source.height;
  item.title = source.title;
  item.status = source.status;
  item.text = source.text;
  item.error = source.error;
  item.enhanceState = source.enhanceState;
  item.enhancedFileName = source.enhancedFileName;
  item.enhancedWidth = source.enhancedWidth;
  item.enhancedHeight = source.enhancedHeight;
  item.originalText = source.originalText;
  item.enhanceNote = source.enhanceNote;
  item.indexState = source.indexState;
  item.indexedFileName = source.indexedFileName;
  item.category = source.category;
  item.categoryManual = source.categoryManual;
  item.rowsText = source.rowsText;
  item.extracted = source.extracted.map((field: ExtractedField) => {
    const copy: ExtractedField = new ExtractedField();
    copy.field = field.field;
    copy.value = field.value;
    copy.source = field.source;
    return copy;
  });
  return item;
}

// 证据库: imports photos or paper scans, recognizes their text on the device
// and keeps everything in the app sandbox.
@Component
export struct EvidenceLibrary {
  @Prop cx: ThemeColors;
  @Prop isDark: boolean = false;
  @Link mode: number;
  onClose: () => void = () => {
  };
  onCountChange: (count: number) => void = (count: number) => {
  };
  // Current dossier values (地点, 单位, 月薪, 时间节点, ...) so extracted values
  // can show whether they are new, already filled or different.
  @Prop dossierValues: string[] = [];
  onFill: (field: number, value: string) => void = (field: number, value: string) => {
  };
  onAsk: (item: EvidenceItem) => void = (item: EvidenceItem) => {
  };
  // Optional starting state when opened from elsewhere (证据核对).
  @Prop initialQuery: string = '';
  @Prop initialCategory: string = '';
  @Prop initialImport: boolean = false;
  @State categoryFilter: string = '';
  @State items: EvidenceItem[] = [];
  @State selectedId: string = '';
  @State importSheet: boolean = false;
  @State importing: boolean = false;
  @State notice: string = '';
  @State compareSplit: number = 0.5;
  @State compareWidth: number = 0;
  @State compareZoom: number = 1;
  @State showOriginalText: boolean = false;
  @State query: string = '';
  @State results: SearchResult[] = [];
  @State searching: boolean = false;
  private searchTimer: number = -1;
  private searchSequence: number = 0;
  private rebuilding: boolean = false;
  private loaded: boolean = false;
  private scannerConfig: DocumentScannerConfig = new DocumentScannerConfig();

  aboutToAppear(): void {
    this.scannerConfig.supportType = [DocType.DOC];
    this.scannerConfig.maxShotCount = MAX_SHOTS;
    this.scannerConfig.isGallerySupported = false;
    this.scannerConfig.isShareable = false;
    this.scannerConfig.defaultFilterId = FilterId.STRENGTHEN;
    this.scannerConfig.saveOptions = [SaveOption.JPG];
    this.categoryFilter = this.initialCategory;
    this.importSheet = this.initialImport;
    this.loadItems().then(() => {
      if (this.initialQuery.length > 0) {
        this.setQuery(this.initialQuery);
      }
    });
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async loadItems(): Promise<void> {
    try {
      this.items = await EvidenceStore.load(this.context());
    } catch (error) {
      this.items = [];
    }
    this.loaded = true;
    this.reclassify();
    this.onCountChange(this.items.length);
    // Resume anything interrupted, e.g. the app was closed mid-recognition.
    this.items.forEach((item: EvidenceItem) => {
      if (item.status === EVIDENCE_PENDING || item.status === EVIDENCE_RECOGNIZING ||
        item.status === EVIDENCE_ENHANCING || item.status === EVIDENCE_INDEXING) {
        this.startRecognition(item);
      } else if (item.rowsText.length === 0 && item.status === EVIDENCE_DONE) {
        // Recognized before classification existed: recognize again to rebuild
        // table rows, the category and the extracted dossier values.
        this.startRecognition(item);
      } else if (item.indexState === INDEX_NONE) {
        // Items added before the search index existed are indexed in the background.
        EvidencePipeline.ensureIndexed(this.context(), cloneItem(item), (updated: EvidenceItem) => {
          this.applyUpdate(updated);
        });
      }
    });
  }

  // Re-applies the current rules to stored text, so rule improvements reach
  // items recognized earlier. Manual choices and chat (found by image) stay.
  private reclassify(): void {
    let changed: boolean = false;
    this.items = this.items.map((item: EvidenceItem) => {
      if (item.categoryManual || item.rowsText.length === 0) {
        return item;
      }
      const ruled: string = EvidenceExtractor.classify(item.title + '\n' + item.rowsText);
      const next: string = ruled.length > 0 ? ruled :
        (item.category === CAT_CHAT ? CAT_CHAT : CAT_OTHER);
      if (next === item.category) {
        return item;
      }
      const updated: EvidenceItem = cloneItem(item);
      updated.category = next;
      updated.extracted = EvidenceExtractor.extract(item.rowsText.split('\n'), next, [], []);
      changed = true;
      return updated;
    });
    if (changed) {
      this.persist();
    }
  }

  private applyUpdate(updated: EvidenceItem): void {
    const snapshot: EvidenceItem = cloneItem(updated);
    this.items = this.items.map((entry: EvidenceItem) => entry.id === snapshot.id ? snapshot : entry);
    if (snapshot.status === EVIDENCE_DONE || snapshot.status === EVIDENCE_FAILED) {
      this.persist();
    }
  }

  private scheduleSearch(): void {
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer);
    }
    this.searchTimer = setTimeout(() => {
      this.searchTimer = -1;
      this.runSearch();
    }, SEARCH_DELAY);
  }

  private setQuery(value: string): void {
    this.query = value;
    if (value.trim().length === 0) {
      this.searchSequence++;
      this.results = [];
      this.searching = false;
      return;
    }
    this.scheduleSearch();
  }

  // Text matches show immediately; semantic hits from textSearchImage are
  // merged in when they arrive. Stale responses are dropped.
  private async runSearch(): Promise<void> {
    const query: string = this.query.trim();
    if (query.length === 0) {
      return;
    }
    const sequence: number = ++this.searchSequence;
    this.results = EvidenceSearch.merge(this.items, query, new Map<string, number>());
    if (!EvidenceIndex.supported()) {
      return;
    }
    this.searching = true;
    try {
      const hits: SemanticHit[] = await EvidenceIndex.search(query);
      if (sequence !== this.searchSequence) {
        return;
      }
      const similarity: Map<string, number> = new Map<string, number>();
      hits.forEach((hit: SemanticHit) => {
        similarity.set(hit.path.substring(hit.path.lastIndexOf('/') + 1), hit.similarity);
      });
      this.results = EvidenceSearch.merge(this.items, query, similarity);
    } catch (error) {
      if (EvidenceIndex.isCapabilityUpdated(error) && !this.rebuilding) {
        this.rebuilding = true;
        this.notice = '系统检索能力已更新，正在重建索引，稍后再搜一次';
        EvidencePipeline.rebuildIndex(this.context(), this.items.map((item: EvidenceItem) => cloneItem(item)),
          (updated: EvidenceItem) => {
            this.applyUpdate(updated);
          }).finally(() => {
          this.rebuilding = false;
        });
      }
    } finally {
      if (sequence === this.searchSequence) {
        this.searching = false;
      }
    }
  }

  private filteredItems(): EvidenceItem[] {
    return this.categoryFilter.length === 0 ? this.items :
      this.items.filter((item: EvidenceItem) => item.category === this.categoryFilter);
  }

  private categoryCount(category: string): number {
    return this.items.filter((item: EvidenceItem) => item.category === category).length;
  }

  private usedCategories(): string[] {
    return EVIDENCE_CATEGORIES.filter((category: string) => this.categoryCount(category) > 0);
  }

  private currentValue(field: number): string {
    return field < this.dossierValues.length ? this.dossierValues[field].trim() : '';
  }

  // 0 new, 1 already filled with this value, 2 different value present
  private fillState(field: ExtractedField): number {
    const current: string = this.currentValue(field.field);
    if (current.length === 0) {
      return 0;
    }
    return current.replace(/\s/g, '') === field.value.replace(/\s/g, '') ? 1 : 2;
  }

  private confirmFill(field: ExtractedField): void {
    if (this.fillState(field) === 2) {
      this.getUIContext().showAlertDialog({
        title: '替换卷宗里的' + FIELD_LABELS[field.field],
        message: '当前：' + this.currentValue(field.field) + '\n替换为：' + field.value + '\n来源：' + field.source,
        autoCancel: true,
        primaryButton: {
          value: '取消',
          action: () => {
          }
        },
        secondaryButton: {
          value: '替换',
          action: () => {
            this.onFill(field.field, field.value);
          }
        }
      });
      return;
    }
    this.onFill(field.field, field.value);
  }

  private changeCategory(item: EvidenceItem): void {
    this.getUIContext().showActionSheet({
      title: '修改类别',
      message: '手动选择后不会再被自动分类覆盖',
      autoCancel: true,
      confirm: {
        value: '取消',
        action: () => {
        }
      },
      sheets: EVIDENCE_CATEGORIES.map((category: string) => {
        const sheet: SheetInfo = {
          title: category,
          action: () => {
            this.items = this.items.map((entry: EvidenceItem) => {
              if (entry.id !== item.id) {
                return entry;
              }
              const updated: EvidenceItem = cloneItem(entry);
              updated.category = category;
              updated.categoryManual = true;
              return updated;
            });
            this.persist();
          }
        };
        return sheet;
      })
    });
  }

  private indexingCount(): number {
    if (!EvidenceIndex.supported()) {
      return 0;
    }
    return this.items.filter((item: EvidenceItem) => item.indexState === INDEX_NONE ||
      item.status === EVIDENCE_INDEXING).length;
  }

  private primaryUri(item: EvidenceItem): string {
    return item.enhanceState === ENHANCE_DONE && item.enhancedFileName.length > 0 ?
      this.enhancedUri(item) : this.imageUri(item);
  }

  private persist(): void {
    if (!this.loaded) {
      return;
    }
    EvidenceStore.save(this.context(), this.items).catch(() => {
      this.notice = '保存证据列表失败，请重试';
    });
    this.onCountChange(this.items.length);
  }

  private startRecognition(item: EvidenceItem, forceEnhance: boolean = false): void {
    EvidencePipeline.recognize(this.context(), cloneItem(item), (updated: EvidenceItem) => {
      this.applyUpdate(updated);
    }, forceEnhance);
  }

  private async addFromUris(uris: string[], source: string): Promise<void> {
    if (uris.length === 0) {
      return;
    }
    this.importing = true;
    this.notice = '';
    try {
      const added: EvidenceItem[] = await EvidencePipeline.importUris(this.context(), uris, source);
      if (added.length < uris.length) {
        this.notice = (uris.length - added.length).toString() + ' 张图片无法读取，已跳过';
      }
      this.items = added.concat(this.items);
      this.persist();
      added.forEach((item: EvidenceItem) => {
        this.startRecognition(item);
      });
    } catch (error) {
      this.notice = '导入失败，请重试';
    } finally {
      this.importing = false;
    }
  }

  private async pickPhotos(): Promise<void> {
    this.importSheet = false;
    try {
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = MAX_PICK;
      const result: photoAccessHelper.PhotoSelectResult =
        await new photoAccessHelper.PhotoViewPicker().select(options);
      await this.addFromUris(result.photoUris, EVIDENCE_SOURCE_PHOTO);
    } catch (error) {
      this.notice = '没有打开相册，请重试';
    }
  }

  private openScanner(): void {
    this.importSheet = false;
    this.mode = EVIDENCE_MODE_SCANNER;
  }

  private selected(): EvidenceItem | undefined {
    return this.items.find((item: EvidenceItem) => item.id === this.selectedId);
  }

  private openDetail(item: EvidenceItem): void {
    this.selectedId = item.id;
    this.compareSplit = 0.5;
    this.compareZoom = 1;
    this.showOriginalText = false;
    this.mode = EVIDENCE_MODE_DETAIL;
  }

  private goBack(): void {
    if (this.mode !== EVIDENCE_MODE_LIST) {
      this.mode = EVIDENCE_MODE_LIST;
      return;
    }
    this.onClose();
  }

  private confirmDelete(item: EvidenceItem): void {
    this.getUIContext().showAlertDialog({
      title: '删除这份材料',
      message: '图片和识别出的文字都会从本机删除，无法恢复。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: this.cx.danger,
        action: () => {
          EvidencePipeline.removeFromIndex(this.context(), item).catch(() => {
            // A stale index entry no longer maps to an item and is ignored.
          });
          EvidenceStore.deleteImage(this.context(), item).catch(() => {
            // The index entry is removed even if the file is already gone.
          });
          this.results = this.results.filter((result: SearchResult) => result.item.id !== item.id);
          this.items = this.items.filter((entry: EvidenceItem) => entry.id !== item.id);
          this.persist();
          this.mode = EVIDENCE_MODE_LIST;
        }
      }
    });
  }

  private imageUri(item: EvidenceItem): string {
    return fileUri.getUriFromPath(EvidenceStore.imagePath(this.context(), item));
  }

  private enhancedUri(item: EvidenceItem): string {
    return fileUri.getUriFromPath(EvidenceStore.enhancedPath(this.context(), item));
  }

  private isProcessing(item: EvidenceItem): boolean {
    return item.status === EVIDENCE_PENDING || item.status === EVIDENCE_ENHANCING ||
      item.status === EVIDENCE_RECOGNIZING || item.status === EVIDENCE_INDEXING;
  }

  private hasEnhanced(item: EvidenceItem): boolean {
    return item.enhanceState === ENHANCE_DONE && item.enhancedFileName.length > 0;
  }

  // Lines recognized from the enhanced image that differ from the original's.
  private changedLines(item: EvidenceItem): number {
    if (item.originalText.length === 0) {
      return 0;
    }
    const before: Set<string> = new Set<string>(item.originalText.split('\n').map((line: string) => line.trim()));
    return item.text.split('\n').filter((line: string) => line.trim().length > 0 && !before.has(line.trim())).length;
  }

  private stageState(item: EvidenceItem, stage: number): number {
    // 0 waiting, 1 running, 2 done, 3 skipped, 4 failed
    if (stage === 3) {
      if (item.status === EVIDENCE_INDEXING) {
        return 1;
      }
      if (item.indexState === INDEX_DONE) {
        return 2;
      }
      if (item.indexState === INDEX_FAILED) {
        return 4;
      }
      return item.indexState === INDEX_SKIPPED ? 3 : 0;
    }
    if (stage === 0) {
      return 2;
    }
    if (stage === 1) {
      if (item.status === EVIDENCE_ENHANCING) {
        return 1;
      }
      if (item.enhanceState === ENHANCE_DONE) {
        return 2;
      }
      return item.status === EVIDENCE_PENDING ? 0 : 3;
    }
    if (item.status === EVIDENCE_RECOGNIZING) {
      return 1;
    }
    return item.status === EVIDENCE_DONE || item.status === EVIDENCE_FAILED || item.status === EVIDENCE_INDEXING ?
      2 : 0;
  }

  private statusLabel(item: EvidenceItem): string {
    if (item.status === EVIDENCE_DONE) {
      return item.text.length > 0 ? '已识别 ' + item.text.replace(/\s/g, '').length.toString() + ' 字' : '未识别到文字';
    }
    if (item.status === EVIDENCE_FAILED) {
      return '识别失败';
    }
    if (item.status === EVIDENCE_INDEXING) {
      return '建立索引中…';
    }
    return item.status === EVIDENCE_ENHANCING ? '超分增强中…' : '识别中…';
  }

  private statusColor(item: EvidenceItem): ResourceColor {
    if (item.status === EVIDENCE_DONE) {
      return item.error.length > 0 ? this.cx.warn : this.cx.ok;
    }
    return item.status === EVIDENCE_FAILED ? this.cx.danger : this.cx.gold;
  }

  private statusBg(item: EvidenceItem): ResourceColor {
    if (item.status === EVIDENCE_DONE) {
      return item.error.length > 0 ? this.chipGold() : this.cx.okBg;
    }
    return item.status === EVIDENCE_FAILED ? this.cx.dangerBg : this.chipGold();
  }

  private chipGold(): string {
    return this.isDark ? '#2A2416' : '#F6EAD2';
  }

  private shortDate(time: number): string {
    const date: Date = new Date(time);
    return (date.getMonth() + 1).toString() + '月' + date.getDate().toString() + '日';
  }

  private dateLabel(time: number): string {
    const date: Date = new Date(time);
    const pad = (value: number): string => value < 10 ? '0' + value.toString() : value.toString();
    return (date.getMonth() + 1).toString() + '月' + date.getDate().toString() + '日 '
      + pad(date.getHours()) + ':' + pad(date.getMinutes());
  }

  private shownText(item: EvidenceItem): string {
    return this.showOriginalText && item.originalText.length > 0 ? item.originalText : item.text;
  }

  // Offer manual super-resolution for images that skipped it but fit its limits.
  private offerEnhance(item: EvidenceItem): boolean {
    return !this.hasEnhanced(item) && EvidencePipeline.canEnhance(item);
  }

  @Builder
  private StageRow(label: string, state: number) {
    Row({ space: 10 }) {
      Text(state === 2 ? '✓' : (state === 3 ? '–' : ''))
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(state === 2 ? this.cx.onBrand : this.cx.faint)
        .textAlign(TextAlign.Center)
        .width(22)
        .height(22)
        .backgroundColor(state === 2 ? this.cx.brand : this.cx.surface2)
        .borderRadius(11)
      Text(label)
        .fontSize(13)
        .fontColor(state === 0 ? this.cx.muted : this.cx.text)
        .layoutWeight(1)
      if (state === 1) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(this.cx.gold)
      } else if (state === 3 || state === 4) {
        Text(state === 3 ? '已跳过' : '失败')
          .fontSize(11)
          .fontColor(state === 3 ? this.cx.faint : this.cx.danger)
      }
    }
    .width('100%')
  }

  @Builder
  private TextToggle(label: string, original: boolean) {
    Text(label)
      .fontSize(11)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.showOriginalText === original ? this.cx.onBrand : this.cx.muted)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .backgroundColor(this.showOriginalText === original ? this.cx.brand : Color.Transparent)
      .borderRadius(8)
      .onClick(() => {
        this.showOriginalText = original;
      })
  }

  // Before/after slider: the original is drawn over the enhanced image and
  // clipped at the divider, so dragging reveals the super-resolution result.
  // When zoomed, both layers scale around the divider, so the magnified spot
  // follows it and each side shows the same region before and after.
  @Builder
  private CompareView(item: EvidenceItem) {
    Stack({ alignContent: Alignment.TopStart }) {
      Image(this.enhancedUri(item))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
        .scale({ x: this.compareZoom, y: this.compareZoom, centerX: this.compareWidth * this.compareSplit })
        .draggable(false)
      Column() {
        // Same size and transform as the enhanced layer, so zooming keeps the
        // two images aligned.
        Image(this.imageUri(item))
          .width(this.compareWidth)
          .height('100%')
          .objectFit(ImageFit.Contain)
          .scale({ x: this.compareZoom, y: this.compareZoom, centerX: this.compareWidth * this.compareSplit })
          .draggable(false)
      }
      .width(this.compareWidth * this.compareSplit)
      .height('100%')
      // Keep the original pinned to the left edge so it lines up with the
      // enhanced image underneath as the clip narrows.
      .alignItems(HorizontalAlign.Start)
      .clip(true)
      Column()
        .width(2)
        .height('100%')
        .backgroundColor(this.cx.gold)
        .position({ x: this.compareWidth * this.compareSplit - 1, y: 0 })
      Text('⇔')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.cx.onGold)
        .textAlign(TextAlign.Center)
        .width(32)
        .height(32)
        .backgroundColor(this.cx.gold)
        .borderRadius(16)
        .position({ x: this.compareWidth * this.compareSplit - 16, y: 144 })
      Text('原图')
        .fontSize(11)
        .fontColor(this.cx.text)
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .backgroundColor(this.cx.surface)
        .borderRadius(999)
        .position({ x: 10, y: 286 })
      Text('超分增强')
        .fontSize(11)
        .fontColor(this.cx.onGold)
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .backgroundColor(this.cx.gold)
        .borderRadius(999)
        .position({ x: Math.max(0, this.compareWidth - 74), y: 286 })
    }
    .width('100%')
    .height(320)
    .backgroundColor(this.cx.surface2)
    .borderRadius(16)
    .clip(true)
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.compareWidth = Number(newArea.width);
    })
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: 1 })
        .onActionUpdate((event: GestureEvent) => {
          if (this.compareWidth > 0 && event.fingerList.length > 0) {
            this.compareSplit = Math.max(0.02, Math.min(0.98, event.fingerList[0].localX / this.compareWidth));
          }
        })
    )
    .onClick((event: ClickEvent) => {
      if (this.compareWidth > 0) {
        this.compareSplit = Math.max(0.02, Math.min(0.98, event.x / this.compareWidth));
      }
    })
  }

  @Builder
  private Header() {
    Row({ space: 12 }) {
      Text('‹')
        .fontSize(24)
        .fontColor(this.cx.gold)
        .textAlign(TextAlign.Center)
        .width(40)
        .height(40)
        .backgroundColor(this.cx.tint)
        .borderRadius(20)
        .accessibilityText('返回')
        .onClick(() => {
          this.goBack();
        })
      Column({ space: 3 }) {
        Text(this.mode === EVIDENCE_MODE_DETAIL && this.selected() !== undefined ? this.selected()!.title : '证据库')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.cx.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.mode === EVIDENCE_MODE_DETAIL ? '识别结果 · 仅保存在本机' :
          (this.indexingCount() > 0 ?
            this.items.length.toString() + ' 份材料 · 正在建立检索索引 '
              + (this.items.length - this.indexingCount()).toString() + '/' + this.items.length.toString() :
            this.items.length.toString() + ' 份材料 · 仅保存在本机'))
          .fontSize(11.5)
          .fontColor(this.cx.muted)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (this.mode === EVIDENCE_MODE_LIST) {
        Text('+')
          .fontSize(24)
          .fontColor(this.cx.onGold)
          .textAlign(TextAlign.Center)
          .width(40)
          .height(40)
          .backgroundColor(this.cx.gold)
          .borderRadius(20)
          .accessibilityText('添加证据材料')
          .enabled(!this.importing)
          .onClick(() => {
            this.importSheet = true;
          })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 52, bottom: 12 })
  }

  @Builder
  private ImportOption(title: string, subtitle: string, isScan: boolean) {
    Row({ space: 12 }) {
      Column() {
        Image(isScan ? $r('app.media.ic_scan') : $r('app.media.ic_photo'))
          .width(20)
          .height(20)
          .fillColor(isScan ? this.cx.gold : this.cx.brand)
          .draggable(false)
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(isScan ? this.chipGold() : this.cx.tint)
      .borderRadius(12)
      Column({ space: 3 }) {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.cx.text)
        Text(subtitle)
          .fontSize(11.5)
          .fontColor(this.cx.muted)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›')
        .fontSize(18)
        .fontColor(this.cx.faint)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.cx.surface)
    .borderRadius(16)
    .border({ width: 1, color: this.cx.line })
    .onClick(() => {
      if (isScan) {
        this.openScanner();
      } else {
        this.pickPhotos();
      }
    })
  }

  @Builder
  private ImportSheet() {
    Column({ space: 12 }) {
      Text('添加证据材料')
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.cx.text)
        .width('100%')
      this.ImportOption('扫描纸质材料', '劳动合同、工资条、解除通知书，自动矫正', true)
      this.ImportOption('从相册选择', '聊天截图、考勤截图，一次最多 9 张', false)
      Text('图片只保存在本机，文字识别在手机上完成，不会上传。')
        .fontSize(11)
        .lineHeight(17)
        .fontColor(this.cx.muted)
        .width('100%')
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 20, bottom: 24 })
  }

  @Builder
  private EmptyState() {
    Column({ space: 10 }) {
      Column() {
        Image($r('app.media.ic_folder'))
          .width(28)
          .height(28)
          .fillColor(this.cx.gold)
          .draggable(false)
      }
      .width(64)
      .height(64)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.chipGold())
      .borderRadius(20)
      Text('还没有证据材料')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.cx.text)
      Text('拍下工资条、劳动合同，或从相册选择聊天截图。\n文字会在手机上自动识别，方便检索和整理案件。')
        .fontSize(12)
        .lineHeight(19)
        .fontColor(this.cx.muted)
        .textAlign(TextAlign.Center)
      Column({ space: 10 }) {
        this.ImportOption('扫描纸质材料', '自动矫正、增强', true)
        this.ImportOption('从相册选择', '一次最多 9 张', false)
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 40 })
  }

  @Builder
  private EvidenceCard(item: EvidenceItem) {
    Column() {
      Image(this.imageUri(item))
        .width('100%')
        .height(132)
        .objectFit(ImageFit.Cover)
        .backgroundColor(this.cx.surface2)
        .borderRadius({ topLeft: 14, topRight: 14 })
        .draggable(false)
      Column({ space: 6 }) {
        Text(item.title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.cx.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row({ space: 6 }) {
          if (item.category.length > 0) {
            Text(item.category)
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(item.category === CAT_OTHER ? this.cx.muted : this.cx.gold)
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .backgroundColor(item.category === CAT_OTHER ? this.cx.tint : this.chipGold())
              .borderRadius(999)
          }
          Text(this.statusLabel(item))
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.statusColor(item))
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .backgroundColor(this.statusBg(item))
            .borderRadius(999)
          Blank()
          if (item.category.length === 0) {
            Text(this.shortDate(item.createdAt))
              .fontSize(10)
              .fontColor(this.cx.faint)
          }
        }
        .width('100%')
      }
      .padding(10)
    }
    .backgroundColor(this.cx.surface)
    .borderRadius(14)
    .border({ width: 1, color: this.cx.line })
    .clip(true)
    .onClick(() => {
      this.openDetail(item);
    })
  }

  @Builder
  private ListView() {
    if (this.items.length === 0) {
      this.EmptyState()
    } else {
      this.SearchBar()
      if (this.query.trim().length > 0) {
        this.ResultsView()
      } else {
        Scroll() {
          Column({ space: 12 }) {
            if (this.importing) {
              Row({ space: 8 }) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color(this.cx.gold)
                Text('正在导入…')
                  .fontSize(12)
                  .fontColor(this.cx.muted)
              }
              .width('100%')
            }
            Grid() {
              ForEach(this.filteredItems(), (item: EvidenceItem) => {
                GridItem() {
                  this.EvidenceCard(item)
                }
              }, (item: EvidenceItem) => item.id + '_' + item.status + '_' + item.title + '_' + item.category)
            }
            .columnsTemplate('1fr 1fr')
            .columnsGap(12)
            .rowsGap(12)
            .width('100%')
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 40 })
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
  }

  @Builder
  private CategoryChip(category: string, label: string) {
    Text(label)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.categoryFilter === category ? this.cx.onGold : this.cx.muted)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.categoryFilter === category ? this.cx.gold : this.cx.tint)
      .borderRadius(999)
      .onClick(() => {
        this.categoryFilter = category;
      })
  }

  @Builder
  private ExtractedCard(item: EvidenceItem) {
    Column({ space: 10 }) {
      Text('识别到可填入卷宗的信息')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.cx.text)
        .width('100%')
      ForEach(item.extracted, (field: ExtractedField) => {
        Row({ space: 10 }) {
          Column({ space: 3 }) {
            Text(FIELD_LABELS[field.field] ?? '')
              .fontSize(11.5)
              .fontColor(this.cx.muted)
            Text(field.value)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.cx.gold)
            Text((this.fillState(field) === 2 ? '当前 ' + this.currentValue(field.field) + ' · ' : '')
              + '来自' + field.source)
              .fontSize(10.5)
              .fontColor(this.cx.faint)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text(this.fillState(field) === 1 ? '已填' : (this.fillState(field) === 2 ? '替换' : '填入'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.fillState(field) === 1 ? this.cx.ok : (this.fillState(field) === 2 ? this.cx.gold : this.cx.onGold))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(this.fillState(field) === 1 ? this.cx.okBg :
              (this.fillState(field) === 2 ? this.chipGold() : this.cx.gold))
            .borderRadius(999)
            .enabled(this.fillState(field) !== 1)
            .onClick(() => {
              this.confirmFill(field);
            })
        }
        .width('100%')
      }, (field: ExtractedField) => field.field.toString() + '_' + field.value)
      Text('识别结果可能有误，填入前请核对原图。')
        .fontSize(10.5)
        .fontColor(this.cx.faint)
        .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.cx.surface)
    .borderRadius(16)
    .border({ width: 1, color: this.cx.line })
  }

  @Builder
  private SearchBar() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Image($r('app.media.ic_search'))
          .width(16)
          .height(16)
          .fillColor(this.cx.faint)
          .draggable(false)
        TextInput({ text: this.query, placeholder: '搜文字或描述画面，如「打卡记录」' })
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontColor(this.cx.text)
          .placeholderColor(this.cx.placeholder)
          .caretColor(this.cx.gold)
          .backgroundColor(Color.Transparent)
          .padding({ left: 0, right: 0 })
          .maxLength(100)
          .onChange((value: string) => {
            this.setQuery(value);
          })
        if (this.query.length > 0) {
          Text('✕')
            .fontSize(14)
            .fontColor(this.cx.faint)
            .padding(6)
            .accessibilityText('清除搜索')
            .onClick(() => {
              this.setQuery('');
            })
        }
      }
      .height(42)
      .padding({ left: 13, right: 8 })
      .backgroundColor(this.cx.inputBg)
      .borderRadius(21)
      .border({ width: 1, color: this.cx.line })
      if (this.query.trim().length === 0 && this.usedCategories().length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            this.CategoryChip('', '全部 ' + this.items.length.toString())
            ForEach(this.usedCategories(), (category: string) => {
              this.CategoryChip(category, category + ' ' + this.categoryCount(category).toString())
            }, (category: string) => category + '_' + this.categoryCount(category).toString())
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 12 })
  }

  @Builder
  private ResultsView() {
    Scroll() {
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          Text(this.results.length > 0 ? '找到 ' + this.results.length.toString() + ' 份 · 文字 '
            + this.results.filter((r: SearchResult) => r.textHit).length.toString() + ' · 画面 '
            + this.results.filter((r: SearchResult) => r.semanticHit).length.toString() :
            (this.searching ? '正在检索…' : '没有找到相关材料'))
            .fontSize(12)
            .fontColor(this.cx.muted)
          if (this.searching) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(this.cx.gold)
          }
        }
        .width('100%')
        ForEach(this.results, (result: SearchResult) => {
          this.ResultRow(result)
        }, (result: SearchResult) => result.item.id + '_' + result.score.toFixed(3) + '_' + result.item.status)
        if (this.results.length === 0 && !this.searching) {
          Text('换个说法试试，比如「打卡」「工资条」「聊天截图」；\n或者点右上角「+」导入更多材料。')
            .fontSize(12)
            .lineHeight(19)
            .fontColor(this.cx.faint)
            .width('100%')
        }
        if (!EvidenceIndex.supported()) {
          Text('画面相似检索需要鸿蒙 7（API 26）及以上，当前只按文字检索。')
            .fontSize(11)
            .fontColor(this.cx.faint)
            .width('100%')
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 40 })
    }
    .layoutWeight(1)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  private ResultRow(result: SearchResult) {
    Row({ space: 12 }) {
      Image(this.primaryUri(result.item))
        .width(56)
        .height(68)
        .objectFit(ImageFit.Cover)
        .backgroundColor(this.cx.surface2)
        .borderRadius(10)
        .draggable(false)
      Column({ space: 5 }) {
        Text(result.item.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.cx.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row({ space: 5 }) {
          if (result.textHit) {
            Text('文字命中')
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.cx.gold)
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .backgroundColor(this.chipGold())
              .borderRadius(999)
          }
          if (result.semanticHit) {
            Text('画面相似')
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.cx.brand)
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .backgroundColor(this.cx.tint)
              .borderRadius(999)
          }
        }
        if (result.textHit && result.snippet.length > 0) {
          Text() {
            Span(this.snippetBefore(result))
            Span(this.snippetMatch(result))
              .fontColor(this.cx.text)
              .fontWeight(FontWeight.Medium)
              .textBackgroundStyle({ color: this.isDark ? '#47E0B45C' : '#40C0842A', radius: 3 })
            Span(this.snippetAfter(result))
          }
          .fontSize(11.5)
          .fontColor(this.cx.muted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        } else {
          Text('图片内容与「' + this.query.trim() + '」相关')
            .fontSize(11.5)
            .fontColor(this.cx.faint)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(10)
    .backgroundColor(this.cx.surface)
    .borderRadius(14)
    .border({ width: 1, color: this.cx.line })
    .onClick(() => {
      this.openDetail(result.item);
    })
  }

  private matchIndex(result: SearchResult): number {
    return result.snippet.toLowerCase().indexOf(result.term);
  }

  private snippetBefore(result: SearchResult): string {
    const index: number = this.matchIndex(result);
    return index < 0 ? result.snippet : result.snippet.substring(0, index);
  }

  private snippetMatch(result: SearchResult): string {
    const index: number = this.matchIndex(result);
    return index < 0 ? '' : result.snippet.substring(index, index + result.term.length);
  }

  private snippetAfter(result: SearchResult): string {
    const index: number = this.matchIndex(result);
    return index < 0 ? '' : result.snippet.substring(index + result.term.length);
  }

  @Builder
  private DetailView() {
    if (this.selected() !== undefined) {
      Scroll() {
        Column({ space: 14 }) {
          if (this.hasEnhanced(this.selected()!)) {
            this.CompareView(this.selected()!)
          } else {
            Image(this.imageUri(this.selected()!))
              .width('100%')
              .height(320)
              .objectFit(ImageFit.Contain)
              .backgroundColor(this.cx.surface2)
              .borderRadius(16)
              .draggable(false)
          }
          if (this.isProcessing(this.selected()!)) {
            Column({ space: 9 }) {
              this.StageRow('保存到本机', this.stageState(this.selected()!, 0))
              this.StageRow('图像超分（鸿蒙 7）', this.stageState(this.selected()!, 1))
              this.StageRow('文字识别', this.stageState(this.selected()!, 2))
              this.StageRow('建立检索索引（鸿蒙 7）', this.stageState(this.selected()!, 3))
            }
            .width('100%')
            .padding(14)
            .backgroundColor(this.cx.surface)
            .borderRadius(16)
            .border({ width: 1, color: this.cx.line })
          }
          if (this.hasEnhanced(this.selected()!)) {
            Row({ space: 8 }) {
              Text('图像超分')
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.cx.gold)
                .padding({ left: 9, right: 9, top: 3, bottom: 3 })
                .backgroundColor(this.chipGold())
                .borderRadius(999)
              Text(this.selected()!.width.toString() + '×' + this.selected()!.height.toString() + ' → '
                + this.selected()!.enhancedWidth.toString() + '×' + this.selected()!.enhancedHeight.toString())
                .fontSize(12)
                .fontColor(this.cx.text)
              Blank()
              Text(this.compareZoom > 1 ? '还原' : '放大 3×')
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.cx.brand)
                .padding({ left: 9, right: 9, top: 3, bottom: 3 })
                .backgroundColor(this.cx.tint)
                .borderRadius(999)
                .onClick(() => {
                  this.getUIContext().animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, () => {
                    this.compareZoom = this.compareZoom > 1 ? 1 : 3;
                  });
                })
            }
            .width('100%')
          } else if (this.selected()!.enhanceNote.length > 0 && !this.isProcessing(this.selected()!)) {
            Text(this.selected()!.enhanceNote)
              .fontSize(11.5)
              .fontColor(this.selected()!.enhanceState === ENHANCE_FAILED ? this.cx.warn : this.cx.faint)
              .width('100%')
          }
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
            Text((this.selected()!.category.length > 0 ? this.selected()!.category : '未分类') + ' ▾')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.cx.gold)
              .padding({ left: 9, right: 9, top: 3, bottom: 3 })
              .backgroundColor(this.chipGold())
              .borderRadius(999)
              .margin({ right: 6, top: 6 })
              .accessibilityText('修改类别')
              .onClick(() => {
                this.changeCategory(this.selected()!);
              })
            Text(this.statusLabel(this.selected()!))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.statusColor(this.selected()!))
              .padding({ left: 9, right: 9, top: 3, bottom: 3 })
              .backgroundColor(this.statusBg(this.selected()!))
              .borderRadius(999)
              .margin({ right: 6, top: 6 })
            if (this.selected()!.indexState === INDEX_DONE) {
              Text('已建索引')
                .fontSize(11)
                .fontColor(this.cx.muted)
                .padding({ left: 9, right: 9, top: 3, bottom: 3 })
                .backgroundColor(this.cx.tint)
                .borderRadius(999)
              .margin({ right: 6, top: 6 })
            }
            Text(this.selected()!.source === EVIDENCE_SOURCE_SCAN ? '扫描件' : '相册图片')
              .fontSize(11)
              .fontColor(this.cx.muted)
              .padding({ left: 9, right: 9, top: 3, bottom: 3 })
              .backgroundColor(this.cx.tint)
              .borderRadius(999)
              .margin({ right: 6, top: 6 })
            Text(this.selected()!.width.toString() + '×' + this.selected()!.height.toString())
              .fontSize(11)
              .fontColor(this.cx.muted)
              .padding({ left: 9, right: 9, top: 3, bottom: 3 })
              .backgroundColor(this.cx.tint)
              .borderRadius(999)
              .margin({ right: 6, top: 6 })
            Text(this.dateLabel(this.selected()!.createdAt))
              .fontSize(11)
              .fontColor(this.cx.faint)
              .margin({ top: 6 })
          }
          .width('100%')
          if (this.selected()!.error.length > 0) {
            Text(this.selected()!.error)
              .fontSize(12)
              .lineHeight(18)
              .fontColor(this.selected()!.status === EVIDENCE_FAILED ? this.cx.danger : this.cx.warn)
              .width('100%')
              .padding(10)
              .backgroundColor(this.selected()!.status === EVIDENCE_FAILED ? this.cx.dangerBg : this.chipGold())
              .borderRadius(12)
          }
          if (!this.isProcessing(this.selected()!) && this.selected()!.extracted.length > 0) {
            this.ExtractedCard(this.selected()!)
          }
          if (!this.isProcessing(this.selected()!) && this.selected()!.text.length > 0) {
            Column({ space: 6 }) {
              Button('带着这份材料去问 AI')
                .width('100%')
                .height(46)
                .fontSize(15)
                .fontColor(this.cx.onBrand)
                .backgroundColor(this.cx.brand)
                .borderRadius(14)
                .onClick(() => {
                  this.onAsk(this.selected()!);
                })
              Text('只会附上识别出的文字，图片不会上传')
                .fontSize(10.5)
                .fontColor(this.cx.faint)
            }
            .width('100%')
          }
          Column({ space: 8 }) {
            Row() {
              Text('识别出的文字')
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.cx.text)
              Blank()
              if (this.selected()!.originalText.length > 0 && !this.isProcessing(this.selected()!)) {
                Row() {
                  this.TextToggle('增强后', false)
                  this.TextToggle('原图', true)
                }
                .padding(2)
                .backgroundColor(this.cx.surface2)
                .borderRadius(10)
              }
            }
            .width('100%')
            if (this.selected()!.originalText.length > 0 && !this.isProcessing(this.selected()!)) {
              Text(this.changedLines(this.selected()!) > 0 ?
                '超分后有 ' + this.changedLines(this.selected()!).toString() + ' 行识别结果与原图不同，可切换对比' :
                '超分前后识别结果一致')
                .fontSize(11)
                .fontColor(this.cx.muted)
                .width('100%')
            }
            if (this.isProcessing(this.selected()!)) {
              Row({ space: 8 }) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color(this.cx.gold)
                Text('正在手机上识别文字…')
                  .fontSize(12)
                  .fontColor(this.cx.muted)
              }
              .width('100%')
            } else {
              Text(this.shownText(this.selected()!).length > 0 ? this.shownText(this.selected()!) : '没有识别到文字')
                .fontSize(14)
                .lineHeight(22)
                .fontColor(this.shownText(this.selected()!).length > 0 ? this.cx.text : this.cx.faint)
                .width('100%')
                .copyOption(CopyOptions.LocalDevice)
                .selectedBackgroundColor(this.cx.selection)
                .caretColor(this.cx.gold)
            }
          }
          .width('100%')
          .padding(14)
          .backgroundColor(this.cx.surface)
          .borderRadius(16)
          .border({ width: 1, color: this.cx.line })
          Row({ space: 10 }) {
            Button(this.offerEnhance(this.selected()!) ? '增强清晰度' : '重新识别')
              .layoutWeight(1)
              .height(44)
              .fontSize(14)
              .fontColor(this.offerEnhance(this.selected()!) ? this.cx.onGold : this.cx.brand)
              .backgroundColor(this.offerEnhance(this.selected()!) ? this.cx.gold : this.cx.tint)
              .borderRadius(14)
              .enabled(!this.isProcessing(this.selected()!))
              .onClick(() => {
                this.showOriginalText = false;
                this.startRecognition(this.selected()!, this.offerEnhance(this.selected()!));
              })
            Button('删除')
              .layoutWeight(1)
              .height(44)
              .fontSize(14)
              .fontColor(this.cx.danger)
              .backgroundColor(this.cx.dangerBg)
              .borderRadius(14)
              .onClick(() => {
                this.confirmDelete(this.selected()!);
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 40 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
  }

  build() {
    Column() {
      if (this.mode === EVIDENCE_MODE_SCANNER) {
        DocumentScanner({
          scannerConfig: this.scannerConfig,
          onResult: (code: number, saveType: SaveOption, uris: string[]) => {
            this.mode = EVIDENCE_MODE_LIST;
            if (code === SCAN_SUCCESS) {
              this.addFromUris(uris, EVIDENCE_SOURCE_SCAN);
            }
          }
        })
          .width('100%')
          .height('100%')
      } else {
        this.Header()
        if (this.notice.length > 0) {
          Text(this.notice)
            .fontSize(12)
            .fontColor(this.cx.warn)
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 8 })
            .onClick(() => {
              this.notice = '';
            })
        }
        if (this.mode === EVIDENCE_MODE_DETAIL) {
          this.DetailView()
        } else {
          this.ListView()
        }
      }
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 180,
      colors: [[this.cx.bgTop, 0.0], [this.cx.bgBottom, 1.0]]
    })
    .bindSheet(this.importSheet, this.ImportSheet(), {
      height: 330,
      dragBar: true,
      showClose: false,
      maskColor: this.isDark ? '#88040B18' : '#66404A5A',
      onWillDismiss: () => {
        this.importSheet = false;
      }
    })
  }
}
