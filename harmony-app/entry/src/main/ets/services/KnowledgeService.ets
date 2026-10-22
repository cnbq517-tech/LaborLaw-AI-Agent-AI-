import { common } from '@kit.AbilityKit';
import { ErrorEvent, MessageEvents, worker } from '@kit.ArkTS';
import { KnowledgeResult, LawCitation } from '../models/AppModels';
import {
  KNOWLEDGE_LOAD,
  KNOWLEDGE_SEARCH,
  KnowledgeRequest,
  KnowledgeResponse
} from '../models/KnowledgeMessages';
import { KnowledgeEngine } from './KnowledgeEngine';

const WORKER_URL: string = 'entry/ets/workers/KnowledgeWorker.ets';

class PendingRequest {
  resolve: (response: KnowledgeResponse) => void;
  reject: (error: Error) => void;

  constructor(resolve: (response: KnowledgeResponse) => void, reject: (error: Error) => void) {
    this.resolve = resolve;
    this.reject = reject;
  }
}

// Main-thread facade. The index lives in KnowledgeWorker; this class only
// forwards requests, so loading and searching never block the UI thread.
export class KnowledgeService {
  private static thread: worker.ThreadWorker | undefined = undefined;
  private static pending: Map<number, PendingRequest> = new Map<number, PendingRequest>();
  private static nextId: number = 1;
  private static loading: Promise<number> | undefined = undefined;
  private static ready: boolean = false;
  private static searchableDocumentCount: number = 0;

  static load(context: common.UIAbilityContext): Promise<number> {
    if (KnowledgeService.loading === undefined) {
      KnowledgeService.loading = KnowledgeService.loadIndex(context);
      KnowledgeService.loading.catch(() => {
        // Allow a later call to retry after a failed load.
        KnowledgeService.loading = undefined;
      });
    }
    return KnowledgeService.loading;
  }

  static isReady(): boolean {
    return KnowledgeService.ready;
  }

  static getSearchableDocumentCount(): number {
    return KnowledgeService.searchableDocumentCount;
  }

  static async search(query: string, limit: number = 6): Promise<KnowledgeResult> {
    if (!KnowledgeService.ready) {
      throw new Error('本地法律资料尚未加载完成');
    }
    const request: KnowledgeRequest = new KnowledgeRequest(KnowledgeService.nextId++, KNOWLEDGE_SEARCH);
    request.query = query;
    request.limit = limit;
    const response: KnowledgeResponse = await KnowledgeService.post(request, []);
    return new KnowledgeResult(response.context, response.citations);
  }

  static validateAnswer(answer: string, citations: LawCitation[]): string {
    return KnowledgeEngine.validateAnswer(answer, citations);
  }

  private static async loadIndex(context: common.UIAbilityContext): Promise<number> {
    let bytes: Uint8Array;
    try {
      bytes = await context.resourceManager.getRawFileContent('law_index.json');
    } catch (error) {
      throw new Error('本地法律索引读取失败');
    }
    // Hand the raw bytes to the worker without copying; it decodes and parses.
    const source: ArrayBuffer = bytes.buffer as ArrayBuffer;
    const buffer: ArrayBuffer = bytes.byteOffset === 0 && bytes.byteLength === source.byteLength ?
      source : source.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    const request: KnowledgeRequest = new KnowledgeRequest(KnowledgeService.nextId++, KNOWLEDGE_LOAD);
    request.buffer = buffer;
    const response: KnowledgeResponse = await KnowledgeService.post(request, [buffer]);
    KnowledgeService.searchableDocumentCount = response.searchableDocumentCount;
    KnowledgeService.ready = true;
    return response.documentCount;
  }

  private static post(request: KnowledgeRequest, transfer: ArrayBuffer[]): Promise<KnowledgeResponse> {
    return new Promise<KnowledgeResponse>((resolve, reject) => {
      let thread: worker.ThreadWorker;
      try {
        thread = KnowledgeService.ensureWorker();
      } catch (error) {
        reject(new Error('无法启动本地检索线程'));
        return;
      }
      KnowledgeService.pending.set(request.id, new PendingRequest(resolve, reject));
      try {
        if (transfer.length > 0) {
          thread.postMessage(request, transfer);
        } else {
          thread.postMessage(request);
        }
      } catch (error) {
        KnowledgeService.pending.delete(request.id);
        reject(new Error('本地检索请求发送失败'));
      }
    });
  }

  private static ensureWorker(): worker.ThreadWorker {
    if (KnowledgeService.thread !== undefined) {
      return KnowledgeService.thread;
    }
    const thread: worker.ThreadWorker = new worker.ThreadWorker(WORKER_URL);
    thread.onmessage = (event: MessageEvents): void => {
      const response: KnowledgeResponse = event.data as KnowledgeResponse;
      const pending: PendingRequest | undefined = KnowledgeService.pending.get(response.id);
      if (pending === undefined) {
        return;
      }
      KnowledgeService.pending.delete(response.id);
      if (response.error.length > 0) {
        pending.reject(new Error(response.error));
      } else {
        pending.resolve(response);
      }
    };
    thread.onerror = (event: ErrorEvent): void => {
      KnowledgeService.failAll(event.message);
    };
    thread.onexit = (): void => {
      // The worker owns the parsed index; if it exits, start over on next load.
      KnowledgeService.thread = undefined;
      KnowledgeService.ready = false;
      KnowledgeService.loading = undefined;
      KnowledgeService.failAll('本地检索线程已退出');
    };
    KnowledgeService.thread = thread;
    return thread;
  }

  private static failAll(message: string): void {
    const pending: PendingRequest[] = Array.from(KnowledgeService.pending.values());
    KnowledgeService.pending.clear();
    pending.forEach((item: PendingRequest) => {
      item.reject(new Error(message.length > 0 ? message : '本地检索失败'));
    });
  }
}
