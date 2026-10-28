import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { ChatMessage, LawCitation } from '../models/AppModels';
import {
  CaseRecord,
  ChatState,
  DossierState,
  MAX_ARCHIVED_CASES,
  MAX_QUICK_SESSIONS,
  QuickSession,
  STATE_VERSION
} from '../models/ChatState';

const STATE_FILE: string = 'chat_state.json';
const HISTORY_FILE: string = 'quick_history.json';
const CASES_FILE: string = 'case_history.json';
const CASES_VERSION: number = 1;
const HISTORY_VERSION: number = 1;
// Keeps the files small enough to rewrite quickly; older turns are dropped.
const MAX_MESSAGES: number = 100;
// Reasoning can be far longer than the answer; keep the saved files small.
const MAX_REASONING_CHARS: number = 8000;

class QuickHistoryFile {
  version: number = HISTORY_VERSION;
  sessions: QuickSession[] = [];
}

class CaseHistoryFile {
  version: number = CASES_VERSION;
  cases: CaseRecord[] = [];
}

// Saves conversations and the dossier to the app sandbox (el2, encrypted
// while the device is locked) so they survive the app being reclaimed.
export class ChatStateStore {
  private static writing: Promise<void> = Promise.resolve();

  static async load(context: common.UIAbilityContext): Promise<ChatState> {
    const path: string = ChatStateStore.path(context);
    if (!(await fileIo.access(path))) {
      return new ChatState();
    }
    const raw: string = await fileIo.readText(path);
    const parsed: ChatState = JSON.parse(raw) as ChatState;
    const state: ChatState = new ChatState();
    if (parsed.version !== STATE_VERSION) {
      return state;
    }
    state.quickMessages = ChatStateStore.messages(parsed.quickMessages);
    state.quickSessionId = ChatStateStore.text(parsed.quickSessionId);
    state.caseId = ChatStateStore.text(parsed.caseId);
    state.caseMessages = ChatStateStore.messages(parsed.caseMessages);
    state.dossier = ChatStateStore.dossier(parsed.dossier);
    return state;
  }

  private static dossier(value: DossierState): DossierState {
    const dossier: DossierState = new DossierState();
    if (value === undefined || value === null) {
      return dossier;
    }
    dossier.location = ChatStateStore.text(value.location);
    dossier.company = ChatStateStore.text(value.company);
    dossier.salary = ChatStateStore.text(value.salary);
    dossier.timeline = ChatStateStore.text(value.timeline);
    dossier.request = ChatStateStore.text(value.request);
    dossier.details = ChatStateStore.text(value.details);
    dossier.report = ChatStateStore.text(value.report);
    dossier.reportCitations = Array.isArray(value.reportCitations) ? value.reportCitations : [];
    return dossier;
  }

  static async loadCases(context: common.UIAbilityContext): Promise<CaseRecord[]> {
    const path: string = ChatStateStore.path(context, CASES_FILE);
    if (!(await fileIo.access(path))) {
      return [];
    }
    const parsed: CaseHistoryFile = JSON.parse(await fileIo.readText(path)) as CaseHistoryFile;
    if (parsed.version !== CASES_VERSION || !Array.isArray(parsed.cases)) {
      return [];
    }
    const cases: CaseRecord[] = [];
    parsed.cases.forEach((item: CaseRecord) => {
      if (item === null || typeof item.id !== 'string' || item.id.length === 0) {
        return;
      }
      const record: CaseRecord = new CaseRecord();
      record.id = item.id;
      record.title = ChatStateStore.text(item.title);
      record.updatedAt = typeof item.updatedAt === 'number' ? item.updatedAt : 0;
      record.messages = ChatStateStore.messages(item.messages);
      record.dossier = ChatStateStore.dossier(item.dossier);
      cases.push(record);
    });
    return cases.slice(0, MAX_ARCHIVED_CASES);
  }

  static saveCases(context: common.UIAbilityContext, cases: CaseRecord[]): Promise<void> {
    const file: CaseHistoryFile = new CaseHistoryFile();
    file.cases = cases.slice(0, MAX_ARCHIVED_CASES).map((item: CaseRecord) => {
      const record: CaseRecord = new CaseRecord();
      record.id = item.id;
      record.title = item.title;
      record.updatedAt = item.updatedAt;
      record.messages = ChatStateStore.capped(item.messages);
      record.dossier = item.dossier;
      return record;
    });
    return ChatStateStore.enqueueWrite(ChatStateStore.path(context, CASES_FILE), JSON.stringify(file));
  }

  // Writes are serialized and go through a temp file plus rename, so a crash
  // mid-write never leaves a truncated state file behind.
  static save(context: common.UIAbilityContext, state: ChatState): Promise<void> {
    const snapshot: ChatState = new ChatState();
    snapshot.quickMessages = ChatStateStore.capped(state.quickMessages);
    snapshot.quickSessionId = state.quickSessionId;
    snapshot.caseId = state.caseId;
    snapshot.caseMessages = ChatStateStore.capped(state.caseMessages);
    snapshot.dossier = state.dossier;
    return ChatStateStore.enqueueWrite(ChatStateStore.path(context, STATE_FILE), JSON.stringify(snapshot));
  }

  static async loadHistory(context: common.UIAbilityContext): Promise<QuickSession[]> {
    const path: string = ChatStateStore.path(context, HISTORY_FILE);
    if (!(await fileIo.access(path))) {
      return [];
    }
    const parsed: QuickHistoryFile = JSON.parse(await fileIo.readText(path)) as QuickHistoryFile;
    if (parsed.version !== HISTORY_VERSION || !Array.isArray(parsed.sessions)) {
      return [];
    }
    const sessions: QuickSession[] = [];
    parsed.sessions.forEach((item: QuickSession) => {
      if (item === null || typeof item.id !== 'string' || item.id.length === 0) {
        return;
      }
      const messages: ChatMessage[] = ChatStateStore.messages(item.messages);
      if (messages.length === 0) {
        return;
      }
      sessions.push(new QuickSession(item.id, ChatStateStore.text(item.title),
        typeof item.updatedAt === 'number' ? item.updatedAt : 0, messages));
    });
    return sessions.slice(0, MAX_QUICK_SESSIONS);
  }

  static saveHistory(context: common.UIAbilityContext, sessions: QuickSession[]): Promise<void> {
    const file: QuickHistoryFile = new QuickHistoryFile();
    file.sessions = sessions.slice(0, MAX_QUICK_SESSIONS).map((session: QuickSession) =>
      new QuickSession(session.id, session.title, session.updatedAt, ChatStateStore.capped(session.messages)));
    return ChatStateStore.enqueueWrite(ChatStateStore.path(context, HISTORY_FILE), JSON.stringify(file));
  }

  private static enqueueWrite(path: string, content: string): Promise<void> {
    const next: Promise<void> = ChatStateStore.writing
      .catch(() => {
        // A failed earlier write must not block later ones.
      })
      .then(() => ChatStateStore.writeAtomically(path, content));
    ChatStateStore.writing = next;
    return next;
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

  private static path(context: common.UIAbilityContext, name: string = STATE_FILE): string {
    return context.filesDir + '/' + name;
  }

  private static messages(value: ChatMessage[]): ChatMessage[] {
    if (!Array.isArray(value)) {
      return [];
    }
    const result: ChatMessage[] = [];
    value.forEach((item: ChatMessage) => {
      if (item === null || typeof item.role !== 'string' || typeof item.content !== 'string') {
        return;
      }
      const citations: LawCitation[] = Array.isArray(item.citations) ? item.citations : [];
      const apiContent: string = typeof item.apiContent === 'string' ? item.apiContent : '';
      const message: ChatMessage = new ChatMessage(item.role, item.content, citations, apiContent);
      message.reasoning = typeof item.reasoning === 'string' ? item.reasoning : '';
      message.thinkMs = typeof item.thinkMs === 'number' ? item.thinkMs : 0;
      result.push(message);
    });
    return result.slice(-MAX_MESSAGES);
  }

  // Last MAX_MESSAGES messages, with long reasoning truncated for storage.
  private static capped(messages: ChatMessage[]): ChatMessage[] {
    return messages.slice(-MAX_MESSAGES).map((message: ChatMessage) => {
      if (message.reasoning.length <= MAX_REASONING_CHARS) {
        return message;
      }
      const copy: ChatMessage = new ChatMessage(message.role, message.content, message.citations, message.apiContent);
      copy.reasoning = message.reasoning.substring(0, MAX_REASONING_CHARS) + '…';
      copy.thinkMs = message.thinkMs;
      return copy;
    });
  }

  private static text(value: string): string {
    return typeof value === 'string' ? value : '';
  }
}
