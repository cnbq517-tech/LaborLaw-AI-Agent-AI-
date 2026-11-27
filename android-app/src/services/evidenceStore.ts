import { EvidenceItem, ExtractedField } from '@harmony/models/Evidence';

export interface LocalEvidence extends EvidenceItem {
  dataUrl: string;
}

const DB_NAME = 'laborlaw_evidence_db';
const STORE_NAME = 'items';
const DB_VERSION = 1;

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(STORE_NAME)) {
        db.createObjectStore(STORE_NAME, { keyPath: 'id' });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error ?? new Error('无法打开本地证据库'));
  });
}

function hydrateEvidence(raw: Partial<LocalEvidence>): LocalEvidence {
  const item = Object.assign(new EvidenceItem(), raw, {
    dataUrl: typeof raw.dataUrl === 'string' ? raw.dataUrl : '',
  }) as LocalEvidence;
  if (Array.isArray(raw.extracted)) {
    item.extracted = raw.extracted.map((e: Partial<ExtractedField>) => {
      const f = new ExtractedField();
      f.field = typeof e.field === 'number' ? e.field : 0;
      f.value = typeof e.value === 'string' ? e.value : '';
      f.source = typeof e.source === 'string' ? e.source : '';
      return f;
    });
  } else {
    item.extracted = [];
  }
  return item;
}

export async function loadAllEvidence(): Promise<LocalEvidence[]> {
  try {
    const db = await openDb();
    return await new Promise<LocalEvidence[]>((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, 'readonly');
      const store = tx.objectStore(STORE_NAME);
      const req = store.getAll();
      req.onsuccess = () => {
        const list = (Array.isArray(req.result) ? req.result : [])
          .map((r) => hydrateEvidence(r as Partial<LocalEvidence>))
          .sort((a, b) => b.createdAt - a.createdAt);
        resolve(list);
      };
      req.onerror = () => reject(req.error ?? new Error('读取证据库失败'));
    });
  } catch {
    return [];
  }
}

export async function saveEvidenceItem(item: LocalEvidence): Promise<void> {
  const db = await openDb();
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, 'readwrite');
    tx.objectStore(STORE_NAME).put({ ...item });
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error ?? new Error('保存证据失败'));
  });
}

export async function deleteEvidenceItem(id: string): Promise<void> {
  const db = await openDb();
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, 'readwrite');
    tx.objectStore(STORE_NAME).delete(id);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error ?? new Error('删除证据失败'));
  });
}

export async function clearAllEvidence(): Promise<void> {
  try {
    const db = await openDb();
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, 'readwrite');
      tx.objectStore(STORE_NAME).clear();
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error ?? new Error('清空证据库失败'));
    });
  } catch {
    // ignore
  }
}
