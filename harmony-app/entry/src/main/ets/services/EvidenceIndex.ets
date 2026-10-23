import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { textSearchImage } from '@kit.CoreVisionKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN: number = 0x1022;
const LOG_TAG: string = 'EvidenceIndex';
const MIN_API: number = 26;
// textSearchImage scope: letters and digits only, at most 32 characters.
const SCOPE: string = 'evidence';
// The capability was updated; the index must be cleared and rebuilt.
const CAPABILITY_UPDATED: number = 1013100003;
const MAX_RESULTS: number = 20;
// textSearchImage accepts images with 100px < side < 10000px.
const MIN_SIDE: number = 101;
const MAX_SIDE: number = 9999;

export class SemanticHit {
  path: string;
  similarity: number;

  constructor(path: string, similarity: number) {
    this.path = path;
    this.similarity = similarity;
  }
}

// Wraps the HarmonyOS 7 text-to-image search index. The same capability must
// not be called concurrently, so every call goes through one serial queue.
export class EvidenceIndex {
  private static queue: Promise<void> = Promise.resolve();
  private static ready: boolean = false;

  static supported(): boolean {
    return deviceInfo.sdkApiVersion >= MIN_API;
  }

  static fitsSize(width: number, height: number): boolean {
    return width >= MIN_SIDE && height >= MIN_SIDE && width <= MAX_SIDE && height <= MAX_SIDE;
  }

  static isCapabilityUpdated(error: Object): boolean {
    return (error as BusinessError).code === CAPABILITY_UPDATED;
  }

  static insert(path: string): Promise<void> {
    return EvidenceIndex.run(async (): Promise<void> => {
      const ok: boolean = await textSearchImage.insertImage(path, SCOPE);
      if (!ok) {
        throw new Error('insertImage returned false');
      }
    });
  }

  static remove(path: string): Promise<void> {
    return EvidenceIndex.run(async (): Promise<void> => {
      await textSearchImage.deleteImage(path, SCOPE);
    });
  }

  static clear(): Promise<void> {
    return EvidenceIndex.run(async (): Promise<void> => {
      await textSearchImage.clearData();
    });
  }

  static search(query: string): Promise<SemanticHit[]> {
    let hits: SemanticHit[] = [];
    return EvidenceIndex.run(async (): Promise<void> => {
      const results: textSearchImage.ImageObject[] =
        await textSearchImage.search(query.substring(0, 100), SCOPE, MAX_RESULTS);
      hits = results.map((result: textSearchImage.ImageObject) => new SemanticHit(result.imagePath, result.similarity));
      // Logged for threshold calibration on real devices.
      hits.forEach((hit: SemanticHit) => {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'search "%{public}s" %{public}s %{public}s', query,
          hit.path.substring(hit.path.lastIndexOf('/') + 1), hit.similarity.toFixed(4));
      });
    }).then(() => hits);
  }

  private static run(task: () => Promise<void>): Promise<void> {
    const next: Promise<void> = EvidenceIndex.queue
      .catch(() => {
        // A failed call must not block later ones.
      })
      .then(async (): Promise<void> => {
        if (!EvidenceIndex.ready) {
          EvidenceIndex.ready = await textSearchImage.init();
        }
        await task();
      });
    EvidenceIndex.queue = next;
    return next;
  }
}
