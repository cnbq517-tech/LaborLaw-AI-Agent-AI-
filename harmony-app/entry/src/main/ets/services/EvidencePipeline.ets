import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { imageSuperResolution, textRecognition } from '@kit.CoreVisionKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { EntityType, textProcessing } from '@kit.NaturalLanguageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ENHANCE_DONE,
  ENHANCE_FAILED,
  ENHANCE_NONE,
  ENHANCE_SKIPPED,
  EVIDENCE_DONE,
  EVIDENCE_ENHANCING,
  EVIDENCE_FAILED,
  EVIDENCE_INDEXING,
  EVIDENCE_PENDING,
  EVIDENCE_RECOGNIZING,
  EVIDENCE_SOURCE_SCAN,
  EvidenceItem,
  ExtractedField,
  INDEX_DONE,
  INDEX_FAILED,
  INDEX_NONE,
  INDEX_SKIPPED
} from '../models/Evidence';
import { CAT_CHAT, CAT_OTHER, CAT_WAGE, EvidenceExtractor, FIELD_TIMELINE, LineBox } from './EvidenceExtractor';
import { EvidenceIndex, SemanticHit } from './EvidenceIndex';
import { EvidenceStore } from './EvidenceStore';

const LOG_DOMAIN: number = 0x1021;
const LOG_TAG: string = 'EvidencePipeline';
// Core Vision Kit OCR accepts 100px < side, width < 10000px, height < 15210px.
// Larger photos are scaled down; 4096px keeps text legible and memory modest.
const OCR_MAX_SIDE: number = 4096;
const OCR_MIN_SIDE: number = 101;
const MIN_TEXT_CHARS: number = 8;
// Image super-resolution (API 26) accepts 16px < side < 2048px and may time out
// above ~1024px. Only low-resolution images benefit, e.g. compressed chat
// screenshots, so full-size camera photos are skipped.
const SR_MIN_API: number = 26;
const SR_MAX_SIDE: number = 2048;
const SR_SHORT_SIDE_BELOW: number = 1080;
const SR_TIMEOUT_MS: number = 20000;
const TITLE_MAX_CHARS: number = 18;
const NLP_MAX_CHARS: number = 1500;
// textSearchImage query used to recognize chat screenshots, whose text rarely
// says what they are. On device it returned only the chat screenshots.
const CHAT_QUERY: string = '聊天记录';

class OcrOutput {
  text: string;
  lines: LineBox[];

  constructor(text: string, lines: LineBox[]) {
    this.text = text;
    this.lines = lines;
  }
}

class ImageSize {
  width: number;
  height: number;

  constructor(width: number, height: number) {
    this.width = width;
    this.height = height;
  }
}

// Imports evidence images into the sandbox and recognizes their text on the
// device. Core Vision Kit does not allow concurrent calls to the same
// capability, so every recognition runs through one serial queue.
export class EvidencePipeline {
  private static queue: Promise<void> = Promise.resolve();
  private static ocrReady: boolean = false;
  private static nlpReady: boolean = false;
  private static srAnalyzer: imageSuperResolution.ImageSRAnalyzer | undefined = undefined;

  static supportsEnhance(): boolean {
    return deviceInfo.sdkApiVersion >= SR_MIN_API;
  }

  // Whether super-resolution can run on this image at all (size limits).
  static canEnhance(item: EvidenceItem): boolean {
    return EvidencePipeline.supportsEnhance() && item.width > 16 && item.height > 16 &&
      item.width < SR_MAX_SIDE && item.height < SR_MAX_SIDE;
  }

  // Whether it should run automatically: only for low-resolution images.
  static shouldAutoEnhance(item: EvidenceItem): boolean {
    return EvidencePipeline.canEnhance(item) && Math.min(item.width, item.height) < SR_SHORT_SIDE_BELOW;
  }

  static async importUris(context: common.Context, uris: string[], source: string): Promise<EvidenceItem[]> {
    await EvidenceStore.ensureDirectory(context);
    const items: EvidenceItem[] = [];
    for (let index: number = 0; index < uris.length; index++) {
      try {
        items.push(await EvidencePipeline.importOne(context, uris[index], source, index));
      } catch (error) {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Import failed: %{public}s', EvidencePipeline.detail(error));
      }
    }
    return items;
  }

  // Queues recognition; `onUpdate` is called whenever the item changes state.
  // Queues enhancement (when useful) and recognition. `forceEnhance` runs
  // super-resolution even on images that skipped it automatically.
  static recognize(context: common.Context, item: EvidenceItem, onUpdate: (item: EvidenceItem) => void,
    forceEnhance: boolean = false): void {
    EvidencePipeline.queue = EvidencePipeline.queue
      .catch(() => {
        // Keep the queue alive after a failed item.
      })
      .then(() => EvidencePipeline.processNow(context, item, onUpdate, forceEnhance));
  }

  // Recognizes a rendered page, such as a scanned PDF page, through the same
  // serial queue. The caller keeps ownership of the pixel map.
  static recognizePixelMap(pixelMap: image.PixelMap): Promise<string> {
    const task: Promise<string> = EvidencePipeline.queue
      .catch(() => {
        // Keep the queue alive after a failed item.
      })
      .then(async (): Promise<string> => {
        if (!EvidencePipeline.ocrReady) {
          EvidencePipeline.ocrReady = await textRecognition.init();
        }
        const result: textRecognition.TextRecognitionResult = await textRecognition.recognizeText(
          { pixelMap: pixelMap }, { isDirectionDetectionSupported: true });
        return (result.value ?? '').trim();
      });
    EvidencePipeline.queue = task.then(() => {
    }, () => {
    });
    return task;
  }

  // Builds the semantic index for an item that was recognized before indexing
  // existed, or whose index was cleared for a rebuild.
  static ensureIndexed(context: common.Context, item: EvidenceItem, onUpdate: (item: EvidenceItem) => void): void {
    EvidencePipeline.queue = EvidencePipeline.queue
      .catch(() => {
        // Keep the queue alive after a failed item.
      })
      .then(async (): Promise<void> => {
        await EvidencePipeline.indexNow(context, item, onUpdate);
        onUpdate(item);
      });
  }

  // Called when textSearchImage reports that its capability was updated: the
  // whole index is cleared and every item is inserted again.
  static async rebuildIndex(context: common.Context, items: EvidenceItem[],
    onUpdate: (item: EvidenceItem) => void): Promise<void> {
    await EvidenceIndex.clear();
    items.forEach((item: EvidenceItem) => {
      item.indexState = INDEX_NONE;
      item.indexedFileName = '';
      EvidencePipeline.ensureIndexed(context, item, onUpdate);
    });
  }

  static async removeFromIndex(context: common.Context, item: EvidenceItem): Promise<void> {
    if (item.indexedFileName.length > 0 && EvidenceIndex.supported()) {
      await EvidenceIndex.remove(EvidenceStore.directory(context) + '/' + item.indexedFileName);
    }
  }

  // Step 4: insert the clearest version of the image into the semantic index.
  private static async indexNow(context: common.Context, item: EvidenceItem,
    onUpdate: (item: EvidenceItem) => void): Promise<void> {
    if (!EvidenceIndex.supported()) {
      item.indexState = INDEX_SKIPPED;
      return;
    }
    const useEnhanced: boolean = item.enhanceState === ENHANCE_DONE && item.enhancedFileName.length > 0;
    const fileName: string = useEnhanced ? item.enhancedFileName : item.fileName;
    const width: number = useEnhanced ? item.enhancedWidth : item.width;
    const height: number = useEnhanced ? item.enhancedHeight : item.height;
    if (!EvidenceIndex.fitsSize(width, height)) {
      item.indexState = INDEX_SKIPPED;
      return;
    }
    if (item.indexState === INDEX_DONE && item.indexedFileName === fileName) {
      return;
    }
    const finalStatus: string = item.status;
    item.status = EVIDENCE_INDEXING;
    onUpdate(item);
    try {
      if (item.indexedFileName.length > 0 && item.indexedFileName !== fileName) {
        await EvidenceIndex.remove(EvidenceStore.directory(context) + '/' + item.indexedFileName).catch(() => {
          // A stale entry only costs a duplicate search hit.
        });
      }
      await EvidenceIndex.insert(EvidenceStore.directory(context) + '/' + fileName);
      item.indexState = INDEX_DONE;
      item.indexedFileName = fileName;
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Indexing failed: %{public}s', EvidencePipeline.detail(error));
      item.indexState = INDEX_FAILED;
    } finally {
      item.status = finalStatus;
    }
  }

  private static async importOne(context: common.Context, uri: string, source: string,
    index: number): Promise<EvidenceItem> {
    const item: EvidenceItem = new EvidenceItem();
    const now: number = Date.now();
    item.id = now.toString(36) + index.toString(36) + Math.floor(Math.random() * 46656).toString(36);
    item.source = source;
    item.createdAt = now;
    item.fileName = item.id + EvidencePipeline.extension(uri);
    item.title = source === EVIDENCE_SOURCE_SCAN ? '扫描材料' : '图片材料';
    item.status = EVIDENCE_PENDING;
    const target: string = EvidenceStore.imagePath(context, item);
    const file: fileIo.File = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      await fileIo.copyFile(file.fd, target);
    } finally {
      await fileIo.close(file);
    }
    const size: ImageSize = await EvidencePipeline.imageSize(target);
    item.width = size.width;
    item.height = size.height;
    return item;
  }

  private static async processNow(context: common.Context, item: EvidenceItem,
    onUpdate: (item: EvidenceItem) => void, forceEnhance: boolean): Promise<void> {
    item.error = '';
    const wantsEnhance: boolean = forceEnhance ? EvidencePipeline.canEnhance(item) :
      (item.enhanceState === ENHANCE_NONE && EvidencePipeline.shouldAutoEnhance(item));
    if (wantsEnhance) {
      item.status = EVIDENCE_ENHANCING;
      onUpdate(item);
      await EvidencePipeline.enhance(context, item);
    } else if (item.enhanceState === ENHANCE_NONE) {
      item.enhanceState = ENHANCE_SKIPPED;
      item.enhanceNote = !EvidencePipeline.supportsEnhance() ? '当前系统版本不支持图像超分' :
        (EvidencePipeline.canEnhance(item) ? '图片已足够清晰，未做超分' : '图片尺寸超过超分上限，未做超分');
    }
    item.status = EVIDENCE_RECOGNIZING;
    onUpdate(item);
    try {
      const hasEnhanced: boolean = item.enhanceState === ENHANCE_DONE && item.enhancedFileName.length > 0;
      const primaryPath: string = hasEnhanced ? EvidenceStore.enhancedPath(context, item) :
        EvidenceStore.imagePath(context, item);
      const primary: OcrOutput = await EvidencePipeline.recognizeFile(primaryPath);
      const text: string = primary.text;
      // Recognize the original as well so the detail page can show what
      // super-resolution changed.
      item.originalText = hasEnhanced ?
        (await EvidencePipeline.recognizeFile(EvidenceStore.imagePath(context, item))).text : '';
      item.text = text;
      item.title = EvidencePipeline.titleFrom(text, item.title);
      await EvidencePipeline.understand(item, primary.lines);
      item.status = EVIDENCE_DONE;
      if (text.replace(/\s/g, '').length < MIN_TEXT_CHARS) {
        item.error = '识别到的文字很少，可能是手写或太模糊，建议重新拍摄';
      }
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Recognition failed: %{public}s', EvidencePipeline.detail(error));
      item.status = EVIDENCE_FAILED;
      item.error = error instanceof Error && error.message.length > 0 && !error.message.startsWith('{') ?
        error.message : '文字识别失败，请重试';
    }
    // Index even when recognition failed: 画面相似 search still works.
    await EvidencePipeline.indexNow(context, item, onUpdate);
    await EvidencePipeline.detectChat(item);
    onUpdate(item);
  }

  // Rebuilds table rows, classifies the document and extracts dossier values.
  private static async understand(item: EvidenceItem, lines: LineBox[]): Promise<void> {
    const rows: string[] = EvidenceExtractor.rows(lines);
    item.rowsText = rows.length > 0 ? rows.join('\n') : item.text;
    if (!item.categoryManual) {
      item.category = EvidenceExtractor.classify(item.title + '\n' + item.rowsText);
    }
    const places: string[] = [];
    const dates: string[] = [];
    try {
      if (!EvidencePipeline.nlpReady) {
        EvidencePipeline.nlpReady = await textProcessing.init();
      }
      const entities: textProcessing.Entity[] = await textProcessing.getEntity(
        item.rowsText.substring(0, NLP_MAX_CHARS),
        { entityTypes: [EntityType.LOCATION, EntityType.DATETIME] });
      entities.forEach((entity: textProcessing.Entity) => {
        if (entity.type === EntityType.LOCATION) {
          places.push(entity.text);
        } else {
          dates.push(entity.text);
        }
      });
    } catch (error) {
      // Rules still extract most fields without Natural Language Kit.
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Entity extraction unavailable: %{public}s', EvidencePipeline.detail(error));
    }
    item.extracted = EvidenceExtractor.extract(rows.length > 0 ? rows : item.text.split('\n'),
      item.category, places, dates);
    if (item.category === CAT_WAGE) {
      const month: string | undefined = item.extracted.find((field: ExtractedField) => field.field === FIELD_TIMELINE)?.value;
      if (month !== undefined && month.endsWith('工资')) {
        item.title = month.replace(/\s*工资$/, '') + '工资条';
      }
    }
  }

  // Chat screenshots rarely contain words that say so; ask the semantic index
  // whether this image looks like a chat record.
  private static async detectChat(item: EvidenceItem): Promise<void> {
    if (item.categoryManual || item.category.length > 0) {
      return;
    }
    item.category = CAT_OTHER;
    if (item.indexState !== INDEX_DONE) {
      return;
    }
    try {
      const hits: SemanticHit[] = await EvidenceIndex.search(CHAT_QUERY);
      if (hits.some((hit: SemanticHit) => hit.path.endsWith('/' + item.indexedFileName))) {
        item.category = CAT_CHAT;
        const rows: string[] = item.rowsText.split('\n');
        item.extracted = EvidenceExtractor.extract(rows, CAT_CHAT, [], []);
      }
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Chat detection failed: %{public}s', EvidencePipeline.detail(error));
    }
  }

  private static async enhance(context: common.Context, item: EvidenceItem): Promise<void> {
    let original: image.PixelMap | undefined = undefined;
    let enhanced: image.PixelMap | undefined = undefined;
    try {
      if (EvidencePipeline.srAnalyzer === undefined) {
        EvidencePipeline.srAnalyzer = await imageSuperResolution.ImageSRAnalyzer.create();
      }
      const source: image.ImageSource = image.createImageSource(EvidenceStore.imagePath(context, item));
      try {
        original = await source.createPixelMap();
      } finally {
        source.release();
      }
      const response: imageSuperResolution.ISPResponse = await EvidencePipeline.withTimeout(
        EvidencePipeline.srAnalyzer.process({ inputData: { pixelMap: original } }), SR_TIMEOUT_MS);
      enhanced = response.pixelMap;
      const info: image.ImageInfo = await enhanced.getImageInfo();
      const fileName: string = item.id + '_sr.jpg';
      const packer: image.ImagePacker = image.createImagePacker();
      let data: ArrayBuffer;
      try {
        data = await packer.packToData(enhanced, { format: 'image/jpeg', quality: 95 });
      } finally {
        packer.release();
      }
      const file: fileIo.File = await fileIo.open(EvidenceStore.directory(context) + '/' + fileName,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try {
        await fileIo.write(file.fd, data);
      } finally {
        await fileIo.close(file);
      }
      item.enhancedFileName = fileName;
      item.enhancedWidth = info.size.width;
      item.enhancedHeight = info.size.height;
      item.enhanceState = ENHANCE_DONE;
      item.enhanceNote = '';
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Super-resolution %{public}dx%{public}d -> %{public}dx%{public}d',
        item.width, item.height, item.enhancedWidth, item.enhancedHeight);
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Super-resolution failed: %{public}s', EvidencePipeline.detail(error));
      item.enhanceState = ENHANCE_FAILED;
      item.enhanceNote = '图像超分没有完成，已用原图识别';
    } finally {
      if (original !== undefined) {
        original.release();
      }
      if (enhanced !== undefined) {
        enhanced.release();
      }
    }
  }

  private static async recognizeFile(path: string): Promise<OcrOutput> {
    if (!EvidencePipeline.ocrReady) {
      EvidencePipeline.ocrReady = await textRecognition.init();
    }
    const pixelMap: image.PixelMap = await EvidencePipeline.decodeForOcr(path);
    try {
      const result: textRecognition.TextRecognitionResult = await textRecognition.recognizeText(
        { pixelMap: pixelMap }, { isDirectionDetectionSupported: true });
      const lines: LineBox[] = [];
      (result.blocks ?? []).forEach((block: textRecognition.TextBlock) => {
        (block.lines ?? []).forEach((line: textRecognition.TextLine) => {
          const points: textRecognition.PixelPoint[] = line.cornerPoints ?? [];
          if (points.length === 0) {
            return;
          }
          const ys: number[] = points.map((point: textRecognition.PixelPoint) => point.y);
          const xs: number[] = points.map((point: textRecognition.PixelPoint) => point.x);
          const top: number = Math.min(...ys);
          const bottom: number = Math.max(...ys);
          lines.push(new LineBox(line.value, Math.min(...xs), (top + bottom) / 2, bottom - top));
        });
      });
      return new OcrOutput((result.value ?? '').trim(), lines);
    } finally {
      pixelMap.release();
    }
  }

  private static withTimeout<T>(task: Promise<T>, ms: number): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      const timer: number = setTimeout(() => {
        reject(new Error('处理超时'));
      }, ms);
      task.then((value: T) => {
        clearTimeout(timer);
        resolve(value);
      }).catch((error: Error) => {
        clearTimeout(timer);
        reject(error);
      });
    });
  }

  private static async decodeForOcr(path: string): Promise<image.PixelMap> {
    const source: image.ImageSource = image.createImageSource(path);
    try {
      const info: image.ImageInfo = await source.getImageInfo();
      const width: number = info.size.width;
      const height: number = info.size.height;
      if (width < OCR_MIN_SIDE || height < OCR_MIN_SIDE) {
        throw new Error('图片太小，无法识别文字');
      }
      const scale: number = Math.min(1, OCR_MAX_SIDE / Math.max(width, height));
      const options: image.DecodingOptions = {
        desiredSize: { width: Math.round(width * scale), height: Math.round(height * scale) }
      };
      return await source.createPixelMap(options);
    } finally {
      source.release();
    }
  }

  private static async imageSize(path: string): Promise<ImageSize> {
    const source: image.ImageSource = image.createImageSource(path);
    try {
      const info: image.ImageInfo = await source.getImageInfo();
      return new ImageSize(info.size.width, info.size.height);
    } catch (error) {
      throw new Error('无法读取图片，请选择 JPG 或 PNG');
    } finally {
      source.release();
    }
  }

  // Uses the first meaningful line of recognized text as the card title.
  private static titleFrom(text: string, fallback: string): string {
    const lines: string[] = text.split('\n');
    for (let index: number = 0; index < lines.length; index++) {
      const line: string = lines[index].replace(/\s/g, '');
      if (line.length >= 3 && /[一-龥]/.test(line)) {
        return line.length > TITLE_MAX_CHARS ? line.substring(0, TITLE_MAX_CHARS) + '…' : line;
      }
    }
    return fallback;
  }

  private static extension(uri: string): string {
    const lower: string = uri.toLowerCase();
    if (lower.endsWith('.png')) {
      return '.png';
    }
    return '.jpg';
  }

  private static detail(error: Object): string {
    try {
      return JSON.stringify(error);
    } catch (stringifyError) {
      return 'unknown';
    }
  }
}
