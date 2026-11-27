/// <reference lib="webworker" />

import { KnowledgeEngine } from '@harmony/services/KnowledgeEngine';
import type { KnowledgeResult, LawCitation } from '@harmony/models/AppModels';

export type WorkerRequest =
  | { id: number; type: 'init'; url: string }
  | { id: number; type: 'search'; query: string; limit?: number }
  | { id: number; type: 'articles'; keys: string[] };

export type WorkerResponse =
  | { id: number; type: 'progress'; phase: 'downloading' | 'parsing'; percent: number }
  | {
      id: number;
      type: 'init_ok';
      documentCount: number;
      searchableDocumentCount: number;
    }
  | { id: number; type: 'search_ok'; result: KnowledgeResult }
  | { id: number; type: 'articles_ok'; citations: LawCitation[] }
  | { id: number; type: 'error'; message: string };

const ctx: DedicatedWorkerGlobalScope = self as unknown as DedicatedWorkerGlobalScope;

async function handleInit(id: number, url: string): Promise<void> {
  ctx.postMessage({ id, type: 'progress', phase: 'downloading', percent: 5 } satisfies WorkerResponse);

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`无法读取本地法规库（HTTP ${response.status}）`);
  }

  let bytes: Uint8Array;
  const contentLength = Number(response.headers.get('content-length') || 0);
  if (response.body && contentLength > 0) {
    const reader = response.body.getReader();
    const chunks: Uint8Array[] = [];
    let received = 0;
    let lastPercent = 5;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (value) {
        chunks.push(value);
        received += value.byteLength;
        const pct = Math.min(75, Math.round(5 + (received / contentLength) * 70));
        if (pct - lastPercent >= 5) {
          lastPercent = pct;
          ctx.postMessage({ id, type: 'progress', phase: 'downloading', percent: pct } satisfies WorkerResponse);
        }
      }
    }
    bytes = new Uint8Array(received);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
  } else {
    const buf = await response.arrayBuffer();
    bytes = new Uint8Array(buf);
  }

  ctx.postMessage({ id, type: 'progress', phase: 'parsing', percent: 82 } satisfies WorkerResponse);
  const stats = KnowledgeEngine.loadFromBytes(bytes);
  ctx.postMessage({
    id,
    type: 'init_ok',
    documentCount: stats.documentCount,
    searchableDocumentCount: stats.searchableDocumentCount,
  } satisfies WorkerResponse);
}

ctx.onmessage = async (event: MessageEvent<WorkerRequest>) => {
  const req = event.data;
  try {
    if (req.type === 'init') {
      await handleInit(req.id, req.url);
    } else if (req.type === 'search') {
      const result = KnowledgeEngine.search(req.query, req.limit ?? 6);
      ctx.postMessage({ id: req.id, type: 'search_ok', result } satisfies WorkerResponse);
    } else if (req.type === 'articles') {
      const citations = KnowledgeEngine.articles(req.keys);
      ctx.postMessage({ id: req.id, type: 'articles_ok', citations } satisfies WorkerResponse);
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    ctx.postMessage({ id: req.id, type: 'error', message } satisfies WorkerResponse);
  }
};
