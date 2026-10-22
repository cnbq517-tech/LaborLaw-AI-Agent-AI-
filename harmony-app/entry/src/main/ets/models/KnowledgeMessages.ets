import { LawCitation } from './AppModels';

export const KNOWLEDGE_LOAD: string = 'load';
export const KNOWLEDGE_SEARCH: string = 'search';

// Messages exchanged with KnowledgeWorker. They cross the thread boundary by
// structured clone, so they only carry plain data fields.
export class KnowledgeRequest {
  id: number;
  type: string;
  buffer: ArrayBuffer | undefined = undefined;
  query: string = '';
  limit: number = 6;

  constructor(id: number, type: string) {
    this.id = id;
    this.type = type;
  }
}

export class KnowledgeResponse {
  id: number;
  error: string = '';
  documentCount: number = 0;
  searchableDocumentCount: number = 0;
  context: string = '';
  citations: LawCitation[] = [];

  constructor(id: number) {
    this.id = id;
  }
}
