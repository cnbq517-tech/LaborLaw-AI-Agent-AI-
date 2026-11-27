import { ApiConfig, ChatMessage, LawCitation } from '@harmony/models/AppModels';
import { CaseRecord, ChatState, DossierState, QuickSession } from '@harmony/models/ChatState';

export type ThemePreference = 'system' | 'light' | 'dark';

export interface AppSettings {
  baseUrl: string;
  model: string;
  apiKey: string;
  theme: ThemePreference;
  showReasoning: boolean;
  autoExpandReasoning: boolean;
}

export interface SavedContractReport {
  id: string;
  name: string;
  text: string;
  city: string;
  position: string;
  confidential: string;
  signed: string;
  createdAt: number;
  redlineCount: number;
  totalCount: number;
  aiReviewed: boolean;
}

const KEYS = {
  SETTINGS: 'laborlaw_settings_v1',
  CHAT_STATE: 'laborlaw_chat_state_v1',
  QUICK_HISTORY: 'laborlaw_quick_history_v1',
  CASE_ARCHIVE: 'laborlaw_case_archive_v1',
  CONTRACT_HISTORY: 'laborlaw_contract_history_v1',
};

export const DEFAULT_SETTINGS: AppSettings = {
  baseUrl: 'https://api.deepseek.com/v1',
  model: 'deepseek-chat',
  apiKey: '',
  theme: 'system',
  showReasoning: true,
  autoExpandReasoning: true,
};

export function loadSettings(): AppSettings {
  try {
    const raw = localStorage.getItem(KEYS.SETTINGS);
    if (!raw) return { ...DEFAULT_SETTINGS };
    const parsed = JSON.parse(raw) as Partial<AppSettings>;
    return {
      baseUrl: typeof parsed.baseUrl === 'string' ? parsed.baseUrl : DEFAULT_SETTINGS.baseUrl,
      model: typeof parsed.model === 'string' ? parsed.model : DEFAULT_SETTINGS.model,
      apiKey: typeof parsed.apiKey === 'string' ? parsed.apiKey : '',
      theme:
        parsed.theme === 'light' || parsed.theme === 'dark' || parsed.theme === 'system'
          ? parsed.theme
          : 'system',
      showReasoning: typeof parsed.showReasoning === 'boolean' ? parsed.showReasoning : true,
      autoExpandReasoning:
        typeof parsed.autoExpandReasoning === 'boolean' ? parsed.autoExpandReasoning : true,
    };
  } catch {
    return { ...DEFAULT_SETTINGS };
  }
}

export function saveSettings(settings: AppSettings): void {
  try {
    localStorage.setItem(KEYS.SETTINGS, JSON.stringify(settings));
  } catch {
    // ignore storage quota errors
  }
}

export function toApiConfig(settings: AppSettings): ApiConfig {
  return new ApiConfig(settings.baseUrl, settings.model, settings.apiKey);
}

function hydrateCitations(raw: unknown): LawCitation[] {
  if (!Array.isArray(raw)) return [];
  return raw.map((c: Partial<LawCitation>) => {
    const item = new LawCitation(c.id ?? '', {
      id: '',
      documentId: c.documentId ?? '',
      title: c.title ?? '',
      article: c.article ?? '',
      category: c.category ?? '',
      subcategory: '',
      region: c.region ?? '全国',
      source: c.source ?? '',
      status: c.status ?? '',
      effectiveDate: c.effectiveDate ?? '',
      text: c.excerpt ?? '',
    });
    return item;
  });
}

function hydrateMessages(raw: unknown): ChatMessage[] {
  if (!Array.isArray(raw)) return [];
  return raw.map((m: Partial<ChatMessage>) => {
    const msg = new ChatMessage(
      m.role ?? 'user',
      m.content ?? '',
      hydrateCitations(m.citations),
      m.apiContent ?? m.content ?? ''
    );
    msg.reasoning = typeof m.reasoning === 'string' ? m.reasoning : '';
    msg.thinkMs = typeof m.thinkMs === 'number' ? m.thinkMs : 0;
    return msg;
  });
}

function hydrateDossier(raw: unknown): DossierState {
  const d = new DossierState();
  if (!raw || typeof raw !== 'object') return d;
  const r = raw as Partial<DossierState>;
  d.location = r.location ?? '';
  d.company = r.company ?? '';
  d.salary = r.salary ?? '';
  d.timeline = r.timeline ?? '';
  d.request = r.request ?? '';
  d.details = r.details ?? '';
  d.report = r.report ?? '';
  d.reportCitations = hydrateCitations(r.reportCitations);
  return d;
}

export function loadChatState(): ChatState {
  const fallback = new ChatState();
  try {
    const raw = localStorage.getItem(KEYS.CHAT_STATE);
    if (!raw) return fallback;
    const parsed = JSON.parse(raw) as Partial<ChatState>;
    fallback.quickMessages = hydrateMessages(parsed.quickMessages);
    fallback.quickSessionId = typeof parsed.quickSessionId === 'string' ? parsed.quickSessionId : '';
    fallback.caseId = typeof parsed.caseId === 'string' ? parsed.caseId : '';
    fallback.caseMessages = hydrateMessages(parsed.caseMessages);
    fallback.dossier = hydrateDossier(parsed.dossier);
    return fallback;
  } catch {
    return fallback;
  }
}

export function saveChatState(state: ChatState): void {
  try {
    localStorage.setItem(KEYS.CHAT_STATE, JSON.stringify(state));
  } catch {
    // ignore
  }
}

export function loadQuickHistory(): QuickSession[] {
  try {
    const raw = localStorage.getItem(KEYS.QUICK_HISTORY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as Array<Partial<QuickSession>>;
    if (!Array.isArray(parsed)) return [];
    return parsed.map(
      (s) =>
        new QuickSession(
          s.id ?? '',
          s.title ?? '普法咨询',
          typeof s.updatedAt === 'number' ? s.updatedAt : Date.now(),
          hydrateMessages(s.messages)
        )
    );
  } catch {
    return [];
  }
}

export function saveQuickHistory(sessions: QuickSession[]): void {
  try {
    localStorage.setItem(KEYS.QUICK_HISTORY, JSON.stringify(sessions.slice(0, 50)));
  } catch {
    // ignore
  }
}

export function loadCaseArchive(): CaseRecord[] {
  try {
    const raw = localStorage.getItem(KEYS.CASE_ARCHIVE);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as Array<Partial<CaseRecord>>;
    if (!Array.isArray(parsed)) return [];
    return parsed.map((c) => {
      const rec = new CaseRecord();
      rec.id = c.id ?? '';
      rec.title = c.title ?? '未命名案件';
      rec.updatedAt = typeof c.updatedAt === 'number' ? c.updatedAt : Date.now();
      rec.messages = hydrateMessages(c.messages);
      rec.dossier = hydrateDossier(c.dossier);
      return rec;
    });
  } catch {
    return [];
  }
}

export function saveCaseArchive(records: CaseRecord[]): void {
  try {
    localStorage.setItem(KEYS.CASE_ARCHIVE, JSON.stringify(records.slice(0, 20)));
  } catch {
    // ignore
  }
}

export function loadContractHistory(): SavedContractReport[] {
  try {
    const raw = localStorage.getItem(KEYS.CONTRACT_HISTORY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as SavedContractReport[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

export function saveContractHistory(records: SavedContractReport[]): void {
  try {
    localStorage.setItem(KEYS.CONTRACT_HISTORY, JSON.stringify(records.slice(0, 20)));
  } catch {
    // ignore
  }
}

export function clearAllConversationData(): void {
  localStorage.removeItem(KEYS.CHAT_STATE);
  localStorage.removeItem(KEYS.QUICK_HISTORY);
  localStorage.removeItem(KEYS.CASE_ARCHIVE);
  localStorage.removeItem(KEYS.CONTRACT_HISTORY);
}
