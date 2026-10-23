export const EVIDENCE_PENDING: string = 'pending';
export const EVIDENCE_ENHANCING: string = 'enhancing';
export const EVIDENCE_RECOGNIZING: string = 'recognizing';
export const EVIDENCE_INDEXING: string = 'indexing';
export const EVIDENCE_DONE: string = 'done';
export const EVIDENCE_FAILED: string = 'failed';

// Super-resolution outcome for one item.
export const ENHANCE_NONE: string = 'none';
export const ENHANCE_SKIPPED: string = 'skipped';
export const ENHANCE_DONE: string = 'done';
export const ENHANCE_FAILED: string = 'failed';

// Semantic search index (textSearchImage, HarmonyOS 7) state for one item.
export const INDEX_NONE: string = 'none';
export const INDEX_DONE: string = 'indexed';
export const INDEX_FAILED: string = 'failed';
export const INDEX_SKIPPED: string = 'skipped';

export const EVIDENCE_SOURCE_SCAN: string = 'scan';
export const EVIDENCE_SOURCE_PHOTO: string = 'photo';

// A dossier value found in an evidence image; `field` is the dossier input
// index (0 地点, 1 单位, 2 月薪, 3 时间节点).
export class ExtractedField {
  field: number = 0;
  value: string = '';
  source: string = '';
}

// One piece of evidence the user imported. Images live in the app sandbox
// under files/evidence/; only the file name is stored so paths survive
// sandbox relocation.
export class EvidenceItem {
  id: string = '';
  source: string = EVIDENCE_SOURCE_PHOTO;
  createdAt: number = 0;
  fileName: string = '';
  width: number = 0;
  height: number = 0;
  title: string = '';
  status: string = EVIDENCE_PENDING;
  text: string = '';
  error: string = '';
  // Image super-resolution (HarmonyOS 7). When it runs, both the original and
  // the enhanced image are recognized so the user can compare the results.
  enhanceState: string = ENHANCE_NONE;
  enhancedFileName: string = '';
  enhancedWidth: number = 0;
  enhancedHeight: number = 0;
  originalText: string = '';
  enhanceNote: string = '';
  // File name of the image inserted into the semantic index, so it can be
  // removed again when the item is deleted or re-enhanced.
  indexState: string = INDEX_NONE;
  indexedFileName: string = '';
  // Category ('' until classified); a manual choice is never overwritten.
  category: string = '';
  categoryManual: boolean = false;
  // OCR lines regrouped into table rows, used for extraction and for the
  // text sent to the AI.
  rowsText: string = '';
  extracted: ExtractedField[] = [];
}
