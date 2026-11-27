import { KnowledgeResult, LawCitation } from '@harmony/models/AppModels';
import type { WorkerRequest, WorkerResponse } from '../workers/knowledge.worker';

export type KnowledgeStatus = 'idle' | 'loading' | 'ready' | 'error';

export interface KnowledgeStateSnapshot {
  status: KnowledgeStatus;
  phase: 'downloading' | 'parsing' | 'ready' | 'error';
  percent: number;
  documentCount: number;
  searchableDocumentCount: number;
  error: string;
}

type Listener = (state: KnowledgeStateSnapshot) => void;

interface PendingCall {
  resolve: (value: unknown) => void;
  reject: (reason: Error) => void;
}

class KnowledgeClient {
  private worker: Worker | null = null;
  private nextId = 1;
  private pending = new Map<number, PendingCall>();
  private listeners = new Set<Listener>();
  private initPromise: Promise<void> | null = null;

  private state: KnowledgeStateSnapshot = {
    status: 'idle',
    phase: 'downloading',
    percent: 0,
    documentCount: 0,
    searchableDocumentCount: 0,
    error: '',
  };

  getState(): KnowledgeStateSnapshot {
    return { ...this.state };
  }

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    listener(this.getState());
    return () => {
      this.listeners.delete(listener);
    };
  }

  private emit(patch: Partial<KnowledgeStateSnapshot>): void {
    this.state = { ...this.state, ...patch };
    const snap = this.getState();
    this.listeners.forEach((l) => l(snap));
  }

  private ensureWorker(): Worker {
    if (this.worker) return this.worker;
    const w = new Worker(new URL('../workers/knowledge.worker.ts', import.meta.url), {
      type: 'module',
    });
    w.onmessage = (event: MessageEvent<WorkerResponse>) => {
      const msg = event.data;
      if (msg.type === 'progress') {
        this.emit({ status: 'loading', phase: msg.phase, percent: msg.percent });
        return;
      }
      const call = this.pending.get(msg.id);
      if (!call) return;
      this.pending.delete(msg.id);
      if (msg.type === 'error') {
        call.reject(new Error(msg.message));
      } else {
        call.resolve(msg);
      }
    };
    w.onerror = (ev) => {
      const msg = ev.message || '本地法规检索线程异常中断';
      this.emit({ status: 'error', phase: 'error', error: msg });
      this.pending.forEach((p) => p.reject(new Error(msg)));
      this.pending.clear();
      this.worker = null;
      this.initPromise = null;
    };
    this.worker = w;
    return w;
  }

  private send<T extends WorkerResponse>(req: Omit<WorkerRequest, 'id'>): Promise<T> {
    const worker = this.ensureWorker();
    const id = this.nextId++;
    return new Promise<T>((resolve, reject) => {
      this.pending.set(id, {
        resolve: (v) => resolve(v as T),
        reject,
      });
      worker.postMessage({ ...req, id });
    });
  }

  init(): Promise<void> {
    if (this.state.status === 'ready') return Promise.resolve();
    if (this.initPromise) return this.initPromise;

    this.emit({ status: 'loading', phase: 'downloading', percent: 2, error: '' });
    const url = new URL('/data/law_index.json', window.location.origin).toString();

    this.initPromise = this.send<Extract<WorkerResponse, { type: 'init_ok' }>>({
      type: 'init',
      url,
    })
      .then((res) => {
        this.emit({
          status: 'ready',
          phase: 'ready',
          percent: 100,
          documentCount: res.documentCount,
          searchableDocumentCount: res.searchableDocumentCount,
          error: '',
        });
      })
      .catch((err: unknown) => {
        const message = err instanceof Error ? err.message : '加载本地法规库失败';
        this.emit({ status: 'error', phase: 'error', error: message });
        this.initPromise = null;
      });

    return this.initPromise;
  }

  retry(): Promise<void> {
    if (this.worker) {
      this.worker.terminate();
      this.worker = null;
    }
    this.pending.clear();
    this.initPromise = null;
    return this.init();
  }

  async search(query: string, limit = 6): Promise<KnowledgeResult> {
    if (this.state.status !== 'ready') {
      await this.init();
    }
    if (this.state.status !== 'ready') {
      return new KnowledgeResult('', []);
    }
    try {
      const res = await this.send<Extract<WorkerResponse, { type: 'search_ok' }>>({
        type: 'search',
        query,
        limit,
      });
      return res.result;
    } catch {
      return new KnowledgeResult('', []);
    }
  }

  async articles(keys: string[]): Promise<LawCitation[]> {
    if (keys.length === 0) return [];
    if (this.state.status !== 'ready') {
      await this.init();
    }
    if (this.state.status !== 'ready') return [];
    try {
      const res = await this.send<Extract<WorkerResponse, { type: 'articles_ok' }>>({
        type: 'articles',
        keys,
      });
      return res.citations;
    } catch {
      return [];
    }
  }
}

export const knowledgeClient = new KnowledgeClient();
