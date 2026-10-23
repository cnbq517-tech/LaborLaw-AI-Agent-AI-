import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { ENHANCE_NONE, EVIDENCE_PENDING, EvidenceItem, ExtractedField, INDEX_NONE } from '../models/Evidence';

const INDEX_FILE: string = 'evidence_index.json';
const EVIDENCE_DIR: string = 'evidence';
const INDEX_VERSION: number = 1;

class EvidenceIndexFile {
  version: number = INDEX_VERSION;
  items: EvidenceItem[] = [];
}

// Persists the evidence list next to the images it describes. Writes are
// serialized and go through a temp file plus rename, like ChatStateStore.
export class EvidenceStore {
  private static writing: Promise<void> = Promise.resolve();

  static directory(context: common.Context): string {
    return context.filesDir + '/' + EVIDENCE_DIR;
  }

  static imagePath(context: common.Context, item: EvidenceItem): string {
    return EvidenceStore.directory(context) + '/' + item.fileName;
  }

  static enhancedPath(context: common.Context, item: EvidenceItem): string {
    return EvidenceStore.directory(context) + '/' + item.enhancedFileName;
  }

  static async ensureDirectory(context: common.Context): Promise<void> {
    const dir: string = EvidenceStore.directory(context);
    if (!(await fileIo.access(dir))) {
      await fileIo.mkdir(dir);
    }
  }

  static async load(context: common.Context): Promise<EvidenceItem[]> {
    const path: string = context.filesDir + '/' + INDEX_FILE;
    if (!(await fileIo.access(path))) {
      return [];
    }
    const parsed: EvidenceIndexFile = JSON.parse(await fileIo.readText(path)) as EvidenceIndexFile;
    if (parsed.version !== INDEX_VERSION || !Array.isArray(parsed.items)) {
      return [];
    }
    const items: EvidenceItem[] = [];
    parsed.items.forEach((raw: EvidenceItem) => {
      if (raw === null || typeof raw.id !== 'string' || typeof raw.fileName !== 'string') {
        return;
      }
      const item: EvidenceItem = new EvidenceItem();
      item.id = raw.id;
      item.source = typeof raw.source === 'string' ? raw.source : item.source;
      item.createdAt = typeof raw.createdAt === 'number' ? raw.createdAt : 0;
      item.fileName = raw.fileName;
      item.width = typeof raw.width === 'number' ? raw.width : 0;
      item.height = typeof raw.height === 'number' ? raw.height : 0;
      item.title = typeof raw.title === 'string' ? raw.title : '';
      item.status = typeof raw.status === 'string' ? raw.status : EVIDENCE_PENDING;
      item.text = typeof raw.text === 'string' ? raw.text : '';
      item.error = typeof raw.error === 'string' ? raw.error : '';
      item.enhanceState = typeof raw.enhanceState === 'string' ? raw.enhanceState : ENHANCE_NONE;
      item.enhancedFileName = typeof raw.enhancedFileName === 'string' ? raw.enhancedFileName : '';
      item.enhancedWidth = typeof raw.enhancedWidth === 'number' ? raw.enhancedWidth : 0;
      item.enhancedHeight = typeof raw.enhancedHeight === 'number' ? raw.enhancedHeight : 0;
      item.originalText = typeof raw.originalText === 'string' ? raw.originalText : '';
      item.enhanceNote = typeof raw.enhanceNote === 'string' ? raw.enhanceNote : '';
      item.indexState = typeof raw.indexState === 'string' ? raw.indexState : INDEX_NONE;
      item.indexedFileName = typeof raw.indexedFileName === 'string' ? raw.indexedFileName : '';
      item.category = typeof raw.category === 'string' ? raw.category : '';
      item.categoryManual = raw.categoryManual === true;
      item.rowsText = typeof raw.rowsText === 'string' ? raw.rowsText : '';
      item.extracted = Array.isArray(raw.extracted) ? raw.extracted.filter((field: ExtractedField) =>
        field !== null && typeof field.field === 'number' && typeof field.value === 'string') : [];
      items.push(item);
    });
    return items;
  }

  static save(context: common.Context, items: EvidenceItem[]): Promise<void> {
    const file: EvidenceIndexFile = new EvidenceIndexFile();
    file.items = items;
    const content: string = JSON.stringify(file);
    const path: string = context.filesDir + '/' + INDEX_FILE;
    const next: Promise<void> = EvidenceStore.writing
      .catch(() => {
        // A failed earlier write must not block later ones.
      })
      .then(() => EvidenceStore.writeAtomically(path, content));
    EvidenceStore.writing = next;
    return next;
  }

  static async deleteImage(context: common.Context, item: EvidenceItem): Promise<void> {
    const path: string = EvidenceStore.imagePath(context, item);
    if (await fileIo.access(path)) {
      await fileIo.unlink(path);
    }
    if (item.enhancedFileName.length > 0) {
      const enhanced: string = EvidenceStore.enhancedPath(context, item);
      if (await fileIo.access(enhanced)) {
        await fileIo.unlink(enhanced);
      }
    }
  }

  // Removes every image and the index; used by 清空本机记录.
  static async clearAll(context: common.Context): Promise<void> {
    await EvidenceStore.save(context, []);
    const dir: string = EvidenceStore.directory(context);
    if (await fileIo.access(dir)) {
      await fileIo.rmdir(dir);
    }
  }

  private static async writeAtomically(path: string, content: string): Promise<void> {
    const tempPath: string = path + '.tmp';
    const file: fileIo.File = await fileIo.open(tempPath,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, content);
      await fileIo.fsync(file.fd);
    } finally {
      await fileIo.close(file);
    }
    await fileIo.rename(tempPath, path);
  }
}
