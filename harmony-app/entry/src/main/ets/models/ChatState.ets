import { ChatMessage, LawCitation } from './AppModels';

// Saved conversation and case data. Kept free of @kit imports, so the logic
// built on it can be tested with Node; ChatStateStore reads and writes it.

export const STATE_VERSION: number = 1;
export const MAX_QUICK_SESSIONS: number = 50;
export const MAX_ARCHIVED_CASES: number = 20;

// One archived 普法 consultation. The newest session comes first in the list.
export class QuickSession {
  id: string;
  title: string;
  updatedAt: number;
  messages: ChatMessage[];

  constructor(id: string, title: string, updatedAt: number, messages: ChatMessage[]) {
    this.id = id;
    this.title = title;
    this.updatedAt = updatedAt;
    this.messages = messages;
  }
}

export class DossierState {
  location: string = '';
  company: string = '';
  salary: string = '';
  timeline: string = '';
  request: string = '';
  details: string = '';
  report: string = '';
  reportCitations: LawCitation[] = [];
}

// One archived 维权 case: its conversation and dossier. The current case
// lives in ChatState; the newest archived case comes first.
export class CaseRecord {
  id: string = '';
  title: string = '';
  updatedAt: number = 0;
  messages: ChatMessage[] = [];
  dossier: DossierState = new DossierState();
}

export class ChatState {
  version: number = STATE_VERSION;
  quickMessages: ChatMessage[] = [];
  quickSessionId: string = '';
  caseId: string = '';
  caseMessages: ChatMessage[] = [];
  dossier: DossierState = new DossierState();
}
