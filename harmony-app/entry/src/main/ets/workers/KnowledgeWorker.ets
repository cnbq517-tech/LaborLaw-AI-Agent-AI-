import { MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import { KnowledgeResult } from '../models/AppModels';
import {
  KNOWLEDGE_ARTICLES,
  KNOWLEDGE_LOAD,
  KnowledgeRequest,
  KnowledgeResponse
} from '../models/KnowledgeMessages';
import { KnowledgeEngine, KnowledgeLoadStats } from '../services/KnowledgeEngine';

const workerPort: ThreadWorkerGlobalScope = worker.workerPort;

workerPort.onmessage = (event: MessageEvents): void => {
  const request: KnowledgeRequest = event.data as KnowledgeRequest;
  const response: KnowledgeResponse = new KnowledgeResponse(request.id);
  try {
    if (request.type === KNOWLEDGE_LOAD) {
      if (request.buffer === undefined) {
        throw new Error('本地法律索引读取失败');
      }
      const stats: KnowledgeLoadStats = KnowledgeEngine.loadFromBytes(new Uint8Array(request.buffer));
      response.documentCount = stats.documentCount;
      response.searchableDocumentCount = stats.searchableDocumentCount;
    } else if (request.type === KNOWLEDGE_ARTICLES) {
      response.citations = KnowledgeEngine.articles(request.articleKeys);
    } else {
      const result: KnowledgeResult = KnowledgeEngine.search(request.query, request.limit);
      response.context = result.context;
      response.citations = result.citations;
    }
  } catch (error) {
    response.error = error instanceof Error && error.message.length > 0 ?
      error.message : '本地法律资料处理失败';
  }
  workerPort.postMessage(response);
};
