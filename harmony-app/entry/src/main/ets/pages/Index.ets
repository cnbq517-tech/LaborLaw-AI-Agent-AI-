import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { KeyboardAvoidMode, mediaquery, uiMaterial, window } from '@kit.ArkUI';
import {
  DividerMode,
  HdsAnimationMode,
  HdsBarStyle,
  HdsTabs,
  HdsTabsController,
  HdsTabsFloatingStyle,
  HdsNavigation,
  HdsNavigationMenuItemOptions,
  HdsNavigationTitleMode,
  ScrollEffectType
} from '@kit.UIDesignKit';
import {
  ApiConfig,
  AppSection,
  CaseFieldInfo,
  ChatMessage,
  ChatRole,
  FileAttachment,
  KnowledgeResult,
  LawCitation,
  PromptSuggestion
} from '../models/AppModels';
import { AiApiClient, StreamHandle, StreamResult } from '../services/AiApiClient';
import { AttachmentService } from '../services/AttachmentService';
import { CaseRecord, ChatState, DossierState, MAX_QUICK_SESSIONS, QuickSession } from '../models/ChatState';
import { CaseArchive } from '../services/CaseArchive';
import { ChatStateStore } from '../services/ChatStateStore';
import { ConversationPrompts } from '../services/ConversationPrompts';
import { CONFIG_HINT, ConversationText, QUOTA_ERROR } from '../services/ConversationText';
import { MIN_INTERVAL_MS, ModelQuota } from '../services/ModelQuota';
import { ConfigStore, QuotaRecord } from '../services/ConfigStore';
import { ChecklistFloatService } from '../services/ChecklistFloatService';
import { CitationText, HighlightRange } from '../services/CitationText';
import { KnowledgeService } from '../services/KnowledgeService';
import { LawCardStateService } from '../services/LawCardStateService';
import { DARK, LIGHT, ThemeColors } from '../theme/Theme';
import { AppEnv } from '../models/AppEnv';
import { CaseState } from '../models/CaseState';
import { ChatSession } from '../models/ChatSession';
import {
  CONTRACT_MODE_CLAUSE,
  CONTRACT_MODE_HOME,
  CONTRACT_MODE_REPORT,
  ContractReview
} from '../components/ContractReview';
import { EVIDENCE_MODE_LIST, EvidenceLibrary } from '../components/EvidenceLibrary';
import { EvidenceItem } from '../models/Evidence';
import { ChecklistItem, EvidenceExtractor } from '../services/EvidenceExtractor';
import { EvidenceSearch, SearchResult } from '../services/EvidenceSearch';
import { EvidenceIndex } from '../services/EvidenceIndex';
import { ContractReport, ContractReviewService } from '../services/ContractReviewService';
import { EvidenceStore } from '../services/EvidenceStore';
import { MineActions, MinePage } from '../components/MinePage';
import { DrawerActions, HistoryDrawer } from '../components/HistoryDrawer';
import { Conversation, ConversationEvents } from '../components/chat/Conversation';
import { DossierActions, DossierPage, ProgressRing } from '../components/DossierPage';
import { DrawerState } from '../models/DrawerState';
import { LIGHT_BUTTON, pointLight } from '../theme/Light';
import { LIGHT_ADAPTIVE, Material } from '../theme/Material';
import {
  AnswerActionsView,
  AnswerText,
  AttachmentErrorRow,
  AttachmentRow,
  ChatActions,
  ChatIcon,
  CitationKey,
  ErrorNotice,
  TAB_BAR_CLEARANCE
} from '../components/chat/ChatViews';

const QUICK_SCROLL_ID: string = 'quickScroll';
const QUICK_TURN_ID: string = 'quickLastTurn';
const CASE_SCROLL_ID: string = 'caseScroll';
const CASE_TURN_ID: string = 'caseLastTurn';
// Pages of the 维权 section.
const RIGHTS_CHAT: number = 0;
const RIGHTS_DOSSIER: number = 1;
const RIGHTS_EVIDENCE: number = 2;
// The header is HEADER_HEIGHT tall on a page at its top and collapses by
// HEADER_SHRINK over the first HEADER_SCROLL of scrolling.
const HEADER_HEIGHT: number = 188;
const HEADER_SHRINK: number = 88;
const HEADER_SCROLL: number = 132;
// The 维权 case bar and page switch, folded away while reading.
const RIGHTS_BAR_HEIGHT: number = 86;
const STREAM_QUICK: number = 0;
const STREAM_CASE: number = 1;
const STREAM_REPORT: number = 2;
// Batches streamed tokens so the UI re-renders a few times per second at most.
const STREAM_RENDER_INTERVAL: number = 80;
const PERSIST_DELAY: number = 600;
const STOPPED_SUFFIX: string = '\n\n（已停止生成）';
const SHEET_CITATION: number = 6;
const SHEET_CHECKLIST: number = 7;
const SHEET_CASES: number = 8;
const EVIDENCE_TEXT_LIMIT: number = 16000;

// One row of 证据核对: a checklist item from an AI answer and what the
// evidence library holds for it.
class ChecklistRow {
  item: ChecklistItem;
  // Items whose category satisfies the checklist item.
  matched: EvidenceItem[] = [];
  // Items that only mention one of its terms in their text.
  related: EvidenceItem[] = [];

  constructor(item: ChecklistItem) {
    this.item = item;
  }
}

class StreamOutcome {
  text: string;
  stopped: boolean;
  reasoning: string = '';
  thinkMs: number = 0;

  constructor(text: string, stopped: boolean) {
    this.text = text;
    this.stopped = stopped;
  }
}

const SHOW_REASONING_KEY: string = 'show_reasoning';
const USE_BUILTIN_KEY: string = 'use_builtin';
const LIGHT_LEVEL_KEY: string = 'light_level';
const EXPAND_REASONING_KEY: string = 'expand_reasoning';

@Entry
@Component
struct Index {
  @StorageLink('cardScenario') cardScenario: string = '';
  @StorageLink('cardScenarioSequence')
  @Watch('onCardScenarioChanged')
  cardScenarioSequence: number = 0;
  @StorageLink('checklistFloatActive') checklistFloatActive: boolean = false;
  @State currentSection: AppSection = AppSection.QUICK;
  @Provide('env') env: AppEnv = new AppEnv();
  @State @Watch('applyReading') quick: ChatSession = new ChatSession();
  @State @Watch('applyReading') caseChat: ChatSession = new ChatSession();
  // The dossier report's request; only its streaming fields are used.
  @State reportRun: ChatSession = new ChatSession();
  @State caseState: CaseState = new CaseState();
  @State connectionState: string = '尚未测试';
  @State configBusy: boolean = false;
  @State checklistFloatError: string = '';
  @State checklistFloatBusy: boolean = false;
  @State reportStage: number = 0;
  @State knowledgeState: string = '正在加载本地法律资料…';
  @State knowledgeDocumentCount: number = 0;
  @State knowledgeSearchableCount: number = 0;
  @State isAttachmentPicking: boolean = false;
  // Layout of the 普法 conversation, for the pinned composer, the latest turn's
  // minimum height and the jump-to-latest button.
  // True after sending in this conversation: the latest turn fills the
  // viewport so the question can sit at the top while the answer streams.
  // The same layout state for the 维权 conversation.
  @State headerProgress: number = 0;
  @State @Watch('syncActiveCitation') sheetKind: number = 0;
  @State sheetCitations: LawCitation[] = [];
  @State quickHistory: QuickSession[] = [];
  @State drawer: DrawerState = new DrawerState();
  @State detailCitations: LawCitation[] = [];
  @State @Watch('syncActiveCitation') detailIndex: number = 0;
  @State @Watch('syncActiveCitation') detailContent: string = '';
  // The citation the detail sheet shows, so its chip stands out in the answer.
  @Provide('activeCitation') activeCitation: string = '';
  @State evidenceMode: number = EVIDENCE_MODE_LIST;
  @State rightsTab: number = RIGHTS_CHAT;
  // The current 维权 case is caseMessages plus the dossier fields; caseHistory
  // holds the archived ones.
  @State mineOpen: boolean = false;
  @State contractMode: number = CONTRACT_MODE_HOME;
  @State contractReportCount: number = 0;
  // Bumped when local records are cleared, so the 合同 section reloads.
  @State localDataVersion: number = 0;
  @State evidenceCount: number = 0;
  @State evidenceQuery: string = '';
  @State evidenceCategory: string = '';
  @State evidenceImport: boolean = false;
  @State checklistRows: ChecklistRow[] = [];

  private hdsTabsController: HdsTabsController = new HdsTabsController();
  private tabBarHidden: boolean = false;
  private quickScroller: Scroller = new Scroller();
  private caseScroller: Scroller = new Scroller();
  private dossierScroller: Scroller = new Scroller();
  private quickQuestionController: TextAreaController = new TextAreaController();
  private caseMessageController: TextAreaController = new TextAreaController();
  private detailsController: TextAreaController = new TextAreaController();
  private fieldControllers: TextInputController[] = [
    new TextInputController(),
    new TextInputController(),
    new TextInputController(),
    new TextInputController(),
    new TextInputController()
  ];
  private mainWindow: window.Window | undefined = undefined;
  private streamHandles: (StreamHandle | undefined)[] = [undefined, undefined, undefined];
  private persistTimer: number = -1;
  private stateRestored: boolean = false;
  private quickSessionId: string = '';
  private detailLeads: string[] = [];
  private detailReturnSheet: number = 0;
  private textSelecting: boolean = false;
  private quotaDay: string = '';
  private lastModelRequest: number = 0;
  private chatActions: ChatActions = new ChatActions();
  private mineActions: MineActions = new MineActions();
  private drawerActions: DrawerActions = new DrawerActions();
  private quickEvents: ConversationEvents = new ConversationEvents();
  private caseEvents: ConversationEvents = new ConversationEvents();
  private dossierActions: DossierActions = new DossierActions();
  private darkListener: mediaquery.MediaQueryListener | undefined = undefined;
  private keyboardHeightCallback: Callback<number> = (height: number): void => {
    this.env.keyboardVisible = height > 0;
  };
  private darkChangeCallback: Callback<mediaquery.MediaQueryResult> =
    (result: mediaquery.MediaQueryResult): void => {
      this.env.isDark = result.matches;
      this.env.cx = result.matches ? DARK : LIGHT;
      ChecklistFloatService.setDarkTheme(result.matches);
      this.applySystemBar();
    };

  private suggestions: PromptSuggestion[] = [
    new PromptSuggestion('工资拖欠', '追索工资与补偿', '公司拖欠工资，我应该如何维权？'),
    new PromptSuggestion('被公司辞退', '判断解除程序风险', '公司突然辞退我，可以要求哪些补偿？'),
    new PromptSuggestion('没有劳动合同', '双倍工资与举证', '入职后一直没有签劳动合同怎么办？'),
    new PromptSuggestion('加班费争议', '计算方式与证据', '怎样证明加班并主张加班费？')
  ];

  private caseFields: CaseFieldInfo[] = [
    new CaseFieldInfo('案件发生地', '省 / 市'),
    new CaseFieldInfo('单位名称', '公司或用人单位'),
    new CaseFieldInfo('平均月薪', '税前月平均工资'),
    new CaseFieldInfo('时间节点', '入职、争议发生时间'),
    new CaseFieldInfo('核心诉求', '希望解决的问题'),
    new CaseFieldInfo('详细经过', '按时间顺序描述事实')
  ];

  aboutToAppear(): void {
    this.bindActions();
    AppStorage.setOrCreate('checklistFloatActive', ChecklistFloatService.isOpen());
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE_WITH_CARET);
    this.observeTheme();
    this.observeKeyboard();
    this.applyCardScenario();
    this.loadConfig();
    this.loadReasoningFlags();
    this.loadKnowledge();
    this.restoreState();
    EvidenceStore.load(this.abilityContext()).then((items: EvidenceItem[]) => {
      this.evidenceCount = items.length;
    }).catch(() => {
      this.evidenceCount = 0;
    });
    ContractReviewService.load(this.abilityContext()).then((reports: ContractReport[]) => {
      this.contractReportCount = reports.length;
    });
  }

  aboutToDisappear(): void {
    this.streamHandles.forEach((handle: StreamHandle | undefined) => {
      handle?.cancel();
    });
    if (this.persistTimer !== -1) {
      clearTimeout(this.persistTimer);
      this.persistTimer = -1;
      this.persistNow();
    }
    if (this.mainWindow !== undefined) {
      this.mainWindow.off('keyboardHeightChange', this.keyboardHeightCallback);
      this.mainWindow = undefined;
    }
    if (this.darkListener !== undefined) {
      this.darkListener.off('change', this.darkChangeCallback);
      this.darkListener = undefined;
    }
  }

  onBackPress(): boolean {
    if (this.drawer.visible) {
      this.closeHistoryDrawer();
      return true;
    }
    // Back steps out of a contract report or an evidence detail before
    // leaving the app.
    if (this.currentSection === AppSection.CONTRACT && this.contractMode !== CONTRACT_MODE_HOME) {
      this.contractMode = this.contractMode === CONTRACT_MODE_CLAUSE ? CONTRACT_MODE_REPORT : CONTRACT_MODE_HOME;
      return true;
    }
    if (this.currentSection === AppSection.CASE && this.rightsTab === RIGHTS_EVIDENCE &&
      this.evidenceMode !== EVIDENCE_MODE_LIST) {
      this.evidenceMode = EVIDENCE_MODE_LIST;
      return true;
    }
    return false;
  }

  private openHistoryDrawer(): void {
    if (this.drawer.visible) {
      return;
    }
    this.quickQuestionController.stopEditing();
    this.drawer.show(this.getUIContext(), this.env.reduceMotion);
  }

  private closeHistoryDrawer(): void {
    this.drawer.hide(this.getUIContext(), this.env.reduceMotion);
  }

  // Swiping right on the 普法 page pulls the drawer out under the finger.
  // The very screen edge belongs to the system back gesture, so this works
  // anywhere on the page instead of relying on an edge swipe.
  private beginDrawerSwipe(): void {
    // Dragging a selection handle must not pull the drawer out.
    if (this.drawer.visible || this.sheetKind !== 0 || this.textSelecting) {
      return;
    }
    this.quickQuestionController.stopEditing();
    this.drawer.beginSwipe();
  }

  private startNewConsultation(): void {
    if (this.quick.sending) {
      return;
    }
    this.returnToQuickHome();
    this.currentSection = AppSection.QUICK;
    this.closeHistoryDrawer();
  }

  private openSessionFromDrawer(session: QuickSession): void {
    if (this.quick.sending) {
      return;
    }
    this.openQuickSession(session);
    this.closeHistoryDrawer();
  }

  private observeTheme(): void {
    try {
      const listener: mediaquery.MediaQueryListener =
        this.getUIContext().getMediaQuery().matchMediaSync('(dark-mode: true)');
      this.darkListener = listener;
      this.env.isDark = listener.matches;
      this.env.cx = listener.matches ? DARK : LIGHT;
      ChecklistFloatService.setDarkTheme(listener.matches);
      listener.on('change', this.darkChangeCallback);
    } catch (error) {
      this.env.isDark = false;
      this.env.cx = LIGHT;
      ChecklistFloatService.setDarkTheme(false);
    }
  }

  private applySystemBar(): void {
    if (this.mainWindow === undefined) {
      return;
    }
    const contentColor: string = this.env.isDark ? '#EAF0FA' : '#12315E';
    try {
      this.mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: contentColor,
        navigationBarColor: '#00000000',
        navigationBarContentColor: contentColor
      }).catch(() => {
        // 系统栏样式调整失败不影响主要功能。
      });
    } catch (error) {
      // 部分设备可能不支持动态系统栏配置。
    }
  }

  private setThemeMode(mode: number): void {
    this.env.themeMode = mode;
    let target: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (mode === 1) {
      target = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    } else if (mode === 2) {
      target = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    try {
      this.abilityContext().getApplicationContext().setColorMode(target);
      ChecklistFloatService.setDarkTheme(mode === 2 ? true : mode === 1 ? false :
        (this.darkListener !== undefined ? this.darkListener.matches : this.env.isDark));
    } catch (error) {
      // 主题切换失败时保持当前外观。
    }
  }

  private async observeKeyboard(): Promise<void> {
    try {
      const mainWindow: window.Window = await window.getLastWindow(this.abilityContext());
      this.mainWindow = mainWindow;
      mainWindow.on('keyboardHeightChange', this.keyboardHeightCallback);
      this.applySystemBar();
    } catch (error) {
      this.env.keyboardVisible = false;
    }
  }

  private async loadKnowledge(): Promise<void> {
    try {
      this.knowledgeDocumentCount = await KnowledgeService.load(this.abilityContext());
      this.knowledgeSearchableCount = KnowledgeService.getSearchableDocumentCount();
      this.knowledgeState = '本地法律资料已就绪';
      LawCardStateService.updateKnowledge(
        this.abilityContext(),
        this.knowledgeDocumentCount,
        this.knowledgeSearchableCount
      ).catch(() => {
        // 卡片状态刷新失败不影响本地知识库使用。
      });
    } catch (error) {
      this.knowledgeState = '本地法律资料加载失败';
    }
  }

  private async restoreState(): Promise<void> {
    try {
      const state: ChatState = await ChatStateStore.load(this.abilityContext());
      // Anything the user started before the file finished loading wins.
      if (this.quick.messages.length === 0) {
        this.quick.messages = state.quickMessages;
        this.quickSessionId = state.quickSessionId;
      }
      if (this.caseChat.messages.length === 0) {
        this.caseChat.messages = state.caseMessages;
        this.caseState.id = state.caseId;
      }
      const dossier: DossierState = state.dossier;
      // Anything the user typed before the file finished loading wins.
      if (!CaseArchive.hasDossierInput(this.currentDossier())) {
        const report: string = this.caseState.report;
        const citations: LawCitation[] = this.caseState.reportCitations;
        this.caseState.setDossier(dossier);
        if (report.length > 0) {
          this.caseState.report = report;
          this.caseState.reportCitations = citations;
        }
      } else if (this.caseState.report.length === 0) {
        this.caseState.report = dossier.report;
        this.caseState.reportCitations = dossier.reportCitations;
      }
      this.updateProgress();
    } catch (error) {
      // A damaged state file only costs the saved history; start fresh.
    }
    try {
      const sessions: QuickSession[] = await ChatStateStore.loadHistory(this.abilityContext());
      // Keep sessions recorded before loading finished at the top.
      const seen: Set<string> = new Set<string>();
      this.quickHistory.forEach((session: QuickSession) => {
        seen.add(session.id);
      });
      this.quickHistory = this.quickHistory
        .concat(sessions.filter((session: QuickSession) => !seen.has(session.id)))
        .slice(0, MAX_QUICK_SESSIONS);
    } catch (error) {
      // A damaged history file only costs the archived consultations.
    }
    try {
      this.caseState.history = await ChatStateStore.loadCases(this.abilityContext());
    } catch (error) {
      // A damaged case archive only costs the archived cases.
    } finally {
      this.stateRestored = true;
    }
  }

  // Archives the current 普法 conversation after each exchange, so going back
  // to the home page never loses it.
  private recordQuickSession(): void {
    if (this.quick.messages.length === 0) {
      return;
    }
    if (this.quickSessionId.length === 0) {
      this.quickSessionId = Date.now().toString(36) + Math.floor(Math.random() * 1679616).toString(36);
    }
    // A session's time is when its last message was sent. Switching sessions or
    // going home archives the open one, but must not bump an unchanged session.
    const archived: QuickSession | undefined =
      this.quickHistory.find((item: QuickSession) => item.id === this.quickSessionId);
    if (archived !== undefined && archived.messages.length === this.quick.messages.length) {
      return;
    }
    const session: QuickSession = new QuickSession(this.quickSessionId,
      ConversationText.sessionTitle(this.quick.messages), Date.now(), this.quick.messages);
    this.quickHistory = [session]
      .concat(this.quickHistory.filter((item: QuickSession) => item.id !== session.id))
      .slice(0, MAX_QUICK_SESSIONS);
    this.saveQuickHistory();
  }

  private saveQuickHistory(): void {
    try {
      ChatStateStore.saveHistory(this.abilityContext(), this.quickHistory).catch(() => {
        // Archiving is best effort; the current conversation is unaffected.
      });
    } catch (error) {
      // The page may already be detached from its ability context.
    }
  }

  private openQuickSession(session: QuickSession): void {
    if (this.quick.sending) {
      return;
    }
    if (this.quickSessionId !== session.id) {
      this.recordQuickSession();
    }
    this.sheetKind = 0;
    this.quickQuestionController.stopEditing();
    this.quickSessionId = session.id;
    this.quick.messages = session.messages;
    this.quick.anchorTurn = false;
    this.quick.error = '';
    this.currentSection = AppSection.QUICK;
    this.scrollConversationToBottom(this.quickScroller);
    this.schedulePersist();
  }

  private deleteQuickSession(id: string): void {
    this.quickHistory = this.quickHistory.filter((session: QuickSession) => session.id !== id);
    if (this.quickSessionId === id) {
      // Keep the open conversation but archive it as a new session next time.
      this.quickSessionId = '';
      this.schedulePersist();
    }
    this.saveQuickHistory();
  }

  private hasCaseContent(): boolean {
    return CaseArchive.hasContent(this.caseChat.messages, this.currentDossier());
  }

  private currentDossier(): DossierState {
    return this.caseState.dossier();
  }

  private currentCaseTitle(): string {
    return this.caseState.title(this.caseChat.messages);
  }

  private caseBusy(): boolean {
    return this.caseChat.sending || this.reportRun.sending;
  }

  // Moves the current case to the top of the archive, if it has anything.
  private archiveCurrentCase(): void {
    this.caseState.history = CaseArchive.archive(this.caseState.history, this.caseState.id, this.caseChat.messages, this.currentDossier());
  }

  private loadCase(record: CaseRecord | undefined): void {
    const dossier: DossierState = record !== undefined ? record.dossier : new DossierState();
    this.caseState.id = record !== undefined ? record.id : '';
    this.caseChat.messages = record !== undefined ? record.messages : [];
    this.caseState.setDossier(dossier);
    this.caseChat.input = '';
    this.caseChat.attachment = new FileAttachment();
    this.caseChat.attachmentError = '';
    this.caseChat.error = '';
    this.reportRun.error = '';
    this.reportStage = 0;
    this.caseChat.anchorTurn = false;
    this.caseChat.showJump = false;
    this.updateProgress();
    this.showRights(RIGHTS_CHAT);
    this.schedulePersist();
    this.saveCaseHistory();
  }

  // Archives the current case and starts an empty one.
  private startNewCase(): void {
    if (this.caseBusy()) {
      return;
    }
    const hadContent: boolean = this.hasCaseContent();
    const title: string = this.currentCaseTitle();
    this.archiveCurrentCase();
    this.sheetKind = 0;
    this.loadCase(undefined);
    if (hadContent) {
      this.getUIContext().getPromptAction().showToast({ systemMaterial: Material.popup(), message: '已存档「' + title + '」', duration: 1800 });
    }
  }

  // Archives the current case and continues an archived one.
  private openCase(id: string): void {
    const record: CaseRecord | undefined = this.caseState.history.find((c: CaseRecord) => c.id === id);
    if (record === undefined || this.caseBusy()) {
      return;
    }
    this.archiveCurrentCase();
    this.caseState.history = this.caseState.history.filter((c: CaseRecord) => c.id !== id);
    this.sheetKind = 0;
    this.loadCase(record);
  }

  private deleteCase(record: CaseRecord): void {
    this.getUIContext().showAlertDialog({
      systemMaterial: Material.popup(),
      title: '删除这个案件',
      message: '「' + record.title + '」的对话、卷宗和分析报告都会从本机删除，无法恢复。证据库不受影响。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: this.env.cx.danger,
        action: () => {
          this.caseState.history = this.caseState.history.filter((c: CaseRecord) => c.id !== record.id);
          this.saveCaseHistory();
        }
      }
    });
  }

  private saveCaseHistory(): void {
    try {
      ChatStateStore.saveCases(this.abilityContext(), this.caseState.history).catch(() => {
        // Saving the archive is best effort; the current case is unaffected.
      });
    } catch (error) {
      // The page may already be detached from its ability context.
    }
  }

  private schedulePersist(): void {
    if (this.persistTimer !== -1) {
      clearTimeout(this.persistTimer);
    }
    this.persistTimer = setTimeout(() => {
      this.persistTimer = -1;
      this.persistNow();
    }, PERSIST_DELAY);
  }

  private persistNow(): void {
    if (!this.stateRestored) {
      // Saving before the restore finishes would overwrite the stored history.
      this.schedulePersist();
      return;
    }
    const state: ChatState = new ChatState();
    state.quickMessages = this.quick.messages;
    state.quickSessionId = this.quickSessionId;
    state.caseId = this.caseState.id;
    state.caseMessages = this.caseChat.messages;
    state.dossier.location = this.caseState.location;
    state.dossier.company = this.caseState.company;
    state.dossier.salary = this.caseState.salary;
    state.dossier.timeline = this.caseState.timeline;
    state.dossier.request = this.caseState.request;
    state.dossier.details = this.caseState.details;
    state.dossier.report = this.caseState.report;
    state.dossier.reportCitations = this.caseState.reportCitations;
    try {
      ChatStateStore.save(this.abilityContext(), state).catch(() => {
        // Saving history is best effort; the conversation itself is unaffected.
      });
    } catch (error) {
      // The page may already be detached from its ability context.
    }
  }

  private clearLocalRecords(): void {
    this.getUIContext().showAlertDialog({
      systemMaterial: Material.popup(),
      title: '清空本机记录',
      message: '将删除普法咨询及其历史记录、全部维权案件（对话、卷宗和分析报告）、证据库和合同审查报告。此操作无法撤销。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清空',
        fontColor: this.env.cx.danger,
        action: () => {
          this.streamHandles.forEach((handle: StreamHandle | undefined) => {
            handle?.cancel();
          });
          this.quick.messages = [];
          this.quickSessionId = '';
          this.quickHistory = [];
          this.saveQuickHistory();
          this.caseChat.messages = [];
          this.caseChat.anchorTurn = false;
          this.caseState.id = '';
          this.caseState.history = [];
          this.saveCaseHistory();
          this.quick.error = '';
          this.caseChat.error = '';
          this.caseState.setDossier(new DossierState());
          this.reportRun.error = '';
          this.reportStage = 0;
          this.updateProgress();
          EvidenceIndex.clear().catch(() => {
            // Without a search index there is nothing to clear.
          });
          EvidenceStore.clearAll(this.abilityContext()).then(() => {
            this.evidenceCount = 0;
          }).catch(() => {
            // Evidence files that fail to delete stay listed until next launch.
          });
          // Contract reports keep the contract text, so they go too.
          ContractReviewService.save(this.abilityContext(), []).then(() => {
            this.contractReportCount = 0;
            this.localDataVersion++;
          }).catch(() => {
            this.getUIContext().getPromptAction().showToast({ systemMaterial: Material.popup(), message: '合同审查报告未能删除，请重试', duration: 1800 });
          });
          this.schedulePersist();
        }
      }
    });
  }

  private beginStream(kind: number): StreamHandle {
    const handle: StreamHandle = new StreamHandle();
    this.streamHandles[kind] = handle;
    return handle;
  }

  private stopStream(kind: number): void {
    this.streamHandles[kind]?.cancel();
  }

  // The conversation a stream kind writes to.
  private session(kind: number): ChatSession {
    return kind === STREAM_CASE ? this.caseChat : kind === STREAM_REPORT ? this.reportRun : this.quick;
  }

  private setStreamingText(kind: number, text: string): void {
    this.session(kind).streaming = text;
  }

  private async runStream(
    kind: number,
    handle: StreamHandle,
    messages: ChatMessage[],
    citations: LawCitation[],
    scroller: Scroller | undefined
  ): Promise<StreamOutcome> {
    this.session(kind).streamCitations = citations;
    let latest: string = '';
    let latestReasoning: string = '';
    let timer: number = -1;
    let firstRender: boolean = true;
    const startedAt: number = Date.now();
    let answerAt: number = 0;
    // Ticks the 正在思考 · N 秒 counter until the first answer text arrives.
    const ticker: number = setInterval(() => {
      if (answerAt === 0) {
        this.setThinkSeconds(kind, Math.round((Date.now() - startedAt) / 1000));
      }
    }, 1000);
    try {
      const result: StreamResult = await AiApiClient.stream(this.env.config(), messages,
        (partial: string, reasoning: string): void => {
          latest = partial;
          latestReasoning = reasoning;
          if (answerAt === 0 && partial.trim().length > 0) {
            answerAt = Date.now();
            this.setThinkSeconds(kind, Math.round((answerAt - startedAt) / 1000));
          }
          if (timer !== -1) {
            return;
          }
          timer = setTimeout(() => {
            timer = -1;
            if (handle.cancelled) {
              return;
            }
            let follow: boolean = false;
            if (scroller !== undefined) {
              try {
                follow = firstRender || scroller.isAtEnd();
              } catch (error) {
                follow = false;
              }
            }
            firstRender = false;
            this.setStreamingReasoning(kind, latestReasoning);
            this.setStreamingText(kind, KnowledgeService.validateAnswer(latest, citations));
            if (follow && scroller !== undefined) {
              this.scrollConversationToBottom(scroller);
            }
          }, STREAM_RENDER_INTERVAL);
        }, handle);
      const outcome: StreamOutcome = new StreamOutcome(result.answer, handle.cancelled);
      outcome.reasoning = result.reasoning;
      outcome.thinkMs = result.reasoning.length > 0 ? (answerAt > 0 ? answerAt : Date.now()) - startedAt : 0;
      return outcome;
    } finally {
      clearInterval(ticker);
      if (timer !== -1) {
        clearTimeout(timer);
      }
      this.setStreamingText(kind, '');
      this.setStreamingReasoning(kind, '');
      this.setThinkSeconds(kind, 0);
      if (this.streamHandles[kind] === handle) {
        this.streamHandles[kind] = undefined;
      }
    }
  }

  private setStreamingReasoning(kind: number, text: string): void {
    this.session(kind).reasoning = text;
  }

  private setThinkSeconds(kind: number, seconds: number): void {
    this.session(kind).thinkSeconds = seconds;
  }

  private assistantMessage(outcome: StreamOutcome, citations: LawCitation[]): ChatMessage {
    const message: ChatMessage = new ChatMessage(ChatRole.ASSISTANT, this.finalAnswer(outcome, citations), citations);
    message.reasoning = outcome.reasoning;
    message.thinkMs = outcome.thinkMs;
    return message;
  }

  private async loadReasoningFlags(): Promise<void> {
    this.env.showReasoning = await ConfigStore.loadFlag(this.abilityContext(), SHOW_REASONING_KEY, true);
    this.env.autoExpandReasoning = await ConfigStore.loadFlag(this.abilityContext(), EXPAND_REASONING_KEY, true);
    this.env.lightLevel = await ConfigStore.loadNumber(this.abilityContext(), LIGHT_LEVEL_KEY, LIGHT_ADAPTIVE);
  }

  private saveReasoningFlag(key: string, value: boolean): void {
    ConfigStore.saveFlag(this.abilityContext(), key, value).catch(() => {
      // The toggle still applies for this session.
    });
  }

  private finalAnswer(outcome: StreamOutcome, citations: LawCitation[]): string {
    const answer: string = KnowledgeService.validateAnswer(outcome.text, citations);
    return outcome.stopped ? (answer + STOPPED_SUFFIX).trim() : answer;
  }

  private onCardScenarioChanged(): void {
    this.applyCardScenario();
  }

  private applyCardScenario(): void {
    const prompt: string = ConversationPrompts.cardScenario(this.cardScenario);
    if (prompt.length === 0) {
      return;
    }
    this.currentSection = AppSection.QUICK;
    this.quick.input = prompt;
  }

  private abilityContext(): common.UIAbilityContext {
    const hostContext: Context | undefined = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      throw new Error('无法获取应用上下文');
    }
    return hostContext as common.UIAbilityContext;
  }

  private async loadConfig(): Promise<void> {
    let customReady: boolean = false;
    try {
      const config: ApiConfig = await ConfigStore.load(this.abilityContext());
      this.env.baseUrl = config.baseUrl;
      this.env.modelName = config.model;
      this.env.apiKey = config.apiKey;
      customReady = config.apiKey.length > 0 && config.model.length > 0;
      if (customReady) {
        this.connectionState = '已载入本机配置';
      }
    } catch (error) {
      this.connectionState = '读取本机配置失败';
    }
    this.env.builtin = await ConfigStore.loadBuiltin(this.abilityContext());
    if (this.env.builtin !== undefined) {
      // Until the user picks, the built-in service is used unless they had
      // already set up their own.
      const chosen: boolean = await ConfigStore.hasFlag(this.abilityContext(), USE_BUILTIN_KEY);
      this.env.useBuiltin = chosen ? await ConfigStore.loadFlag(this.abilityContext(), USE_BUILTIN_KEY, true) :
        !customReady;
      const record: QuotaRecord = await ConfigStore.loadQuota(this.abilityContext());
      this.quotaDay = ModelQuota.day(new Date());
      this.env.quotaUsed = ModelQuota.usedToday(record.day, record.used, this.quotaDay);
    }
  }

  private setUseBuiltin(value: boolean): void {
    this.env.useBuiltin = value;
    this.saveReasoningFlag(USE_BUILTIN_KEY, value);
  }

  // Counts a request on the built-in service, or returns why it cannot be
  // made. Requests on the user's own service are not counted.
  private takeModelRequest(): string {
    if (!this.env.usingBuiltin()) {
      return '';
    }
    const today: string = ModelQuota.day(new Date());
    if (today !== this.quotaDay) {
      this.quotaDay = today;
      this.env.quotaUsed = 0;
    }
    if (ModelQuota.remaining(this.env.quotaUsed) === 0) {
      return QUOTA_ERROR;
    }
    const now: number = Date.now();
    if (now - this.lastModelRequest < MIN_INTERVAL_MS) {
      return '请求太频繁，请稍后再试';
    }
    this.lastModelRequest = now;
    this.env.quotaUsed++;
    this.saveQuota();
    return '';
  }

  // A request that failed before any answer does not use the allowance.
  private returnModelRequest(): void {
    if (this.env.usingBuiltin() && this.env.quotaUsed > 0) {
      this.env.quotaUsed--;
      this.saveQuota();
    }
  }

  private saveQuota(): void {
    ConfigStore.saveQuota(this.abilityContext(), new QuotaRecord(ModelQuota.day(new Date()), this.env.quotaUsed))
      .catch(() => {
        // The count still applies for this session.
      });
  }

  // 只看法条: when the built-in allowance is used up, answers the pending
  // 普法 question from the local law index alone.
  private async answerFromLawsOnly(): Promise<void> {
    const prompt: string = this.quick.input.trim();
    if (prompt.length === 0 || this.quick.sending || !KnowledgeService.isReady()) {
      return;
    }
    this.quick.error = '';
    try {
      const knowledge: KnowledgeResult = await KnowledgeService.search(prompt);
      this.quick.messages = this.quick.messages.concat([
        new ChatMessage(ChatRole.USER, prompt),
        new ChatMessage(ChatRole.ASSISTANT, ConversationText.lawsOnlyAnswer(knowledge.citations), knowledge.citations)
      ]);
      this.quick.input = '';
      this.quick.anchorTurn = true;
      this.scrollTurnToTop(STREAM_QUICK);
      this.recordQuickSession();
      this.schedulePersist();
    } catch (error) {
      this.quick.error = this.errorMessage(error);
    }
  }

  private async saveConfig(): Promise<boolean> {
    const config: ApiConfig = this.env.customConfig();
    const validationError: string = AiApiClient.validateConfig(config);
    if (validationError.length > 0) {
      this.connectionState = validationError;
      return false;
    }
    try {
      await ConfigStore.save(this.abilityContext(), config);
      this.connectionState = '配置已安全保存';
      return true;
    } catch (error) {
      this.connectionState = '保存配置失败，请重试';
      return false;
    }
  }

  private async testConnection(): Promise<void> {
    if (this.configBusy) {
      return;
    }
    this.configBusy = true;
    this.connectionState = '正在保存并测试…';
    const saved: boolean = await this.saveConfig();
    if (!saved) {
      this.configBusy = false;
      return;
    }
    const messages: ChatMessage[] = [
      new ChatMessage(ChatRole.SYSTEM, '你是连接测试助手，只回答“连接成功”。'),
      new ChatMessage(ChatRole.USER, '请确认连接。')
    ];
    try {
      await AiApiClient.send(this.env.customConfig(), messages);
      this.connectionState = '连接成功，可以开始咨询';
    } catch (error) {
      this.connectionState = this.errorMessage(error);
    } finally {
      this.configBusy = false;
    }
  }

  private errorMessage(error: Error): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return '请求失败，请检查网络和模型配置';
  }

  private async sendQuickQuestion(): Promise<void> {
    const typedPrompt: string = this.quick.input.trim();
    const attachment: FileAttachment = this.quick.attachment;
    if ((typedPrompt.length === 0 && attachment.name.length === 0) || this.quick.sending) {
      return;
    }
    const prompt: string =
      typedPrompt.length > 0 ? typedPrompt : '请分析这份材料中涉及的劳动法律问题。';
    const validationError: string = AiApiClient.validateConfig(this.env.config());
    if (validationError.length > 0) {
      this.quick.error = validationError + CONFIG_HINT;
      return;
    }
    if (!KnowledgeService.isReady()) {
      this.quick.error = '本地法律资料尚未就绪，请稍后再试';
      return;
    }
    const quotaError: string = this.takeModelRequest();
    if (quotaError.length > 0) {
      this.quick.error = quotaError;
      return;
    }
    this.quickQuestionController.stopEditing();
    this.quick.sending = true;
    this.quick.error = '';
    const handle: StreamHandle = this.beginStream(STREAM_QUICK);
    LawCardStateService.recordConsultation(
      this.abilityContext(),
      LawCardStateService.topicForPrompt(prompt)
    ).catch(() => {
      // 最近咨询仅用于卡片概览，失败不阻塞主咨询。
    });

    try {
      const knowledge: KnowledgeResult =
        await KnowledgeService.search(prompt + '\n' + attachment.text.substring(0, 2000));
      if (handle.cancelled) {
        return;
      }
      const displayPrompt: string = attachment.name.length > 0 ?
        prompt + '\n附件：' + attachment.name : prompt;
      const apiPrompt: string = ConversationPrompts.withAttachment(prompt, attachment);
      this.quick.messages =
        this.quick.messages.concat([new ChatMessage(ChatRole.USER, displayPrompt, [], apiPrompt)]);
      this.quick.input = '';
      this.quick.attachment = new FileAttachment();
      this.quick.attachmentError = '';
      this.quick.anchorTurn = true;
      this.scrollTurnToTop(STREAM_QUICK);
      const apiMessages: ChatMessage[] =
        ConversationPrompts.messages(ConversationPrompts.quickSystem(knowledge), this.quick.messages);
      // No scroller: the answer streams below the question without pulling the
      // view down; the jump button appears once it runs past the screen.
      const outcome: StreamOutcome =
        await this.runStream(STREAM_QUICK, handle, apiMessages, knowledge.citations, undefined);
      if (outcome.text.length > 0 || outcome.reasoning.length > 0) {
        this.quick.messages = this.quick.messages.concat([
          this.assistantMessage(outcome, knowledge.citations)
        ]);
      }
    } catch (error) {
      this.returnModelRequest();
      this.quick.error = this.errorMessage(error);
    } finally {
      this.quick.sending = false;
      if (this.streamHandles[STREAM_QUICK] === handle) {
        this.streamHandles[STREAM_QUICK] = undefined;
      }
      this.recordQuickSession();
      this.schedulePersist();
    }
  }

  private async sendCaseMessage(): Promise<void> {
    const typedPrompt: string = this.caseChat.input.trim();
    const attachment: FileAttachment = this.caseChat.attachment;
    if ((typedPrompt.length === 0 && attachment.name.length === 0) || this.caseChat.sending) {
      return;
    }
    const prompt: string =
      typedPrompt.length > 0 ? typedPrompt : '请结合这份附件开始梳理案件信息。';
    const validationError: string = AiApiClient.validateConfig(this.env.config());
    if (validationError.length > 0) {
      this.caseChat.error = validationError + CONFIG_HINT;
      return;
    }
    if (!KnowledgeService.isReady()) {
      this.caseChat.error = '本地法律资料尚未就绪，请稍后再试';
      return;
    }
    const quotaError: string = this.takeModelRequest();
    if (quotaError.length > 0) {
      this.caseChat.error = quotaError;
      return;
    }
    this.caseMessageController.stopEditing();
    this.caseChat.error = '';
    this.caseChat.sending = true;
    const handle: StreamHandle = this.beginStream(STREAM_CASE);
    try {
      const knowledge: KnowledgeResult =
        await KnowledgeService.search(prompt + '\n' + attachment.text.substring(0, 2000));
      if (handle.cancelled) {
        return;
      }
      const displayPrompt: string = attachment.name.length > 0 ?
        prompt + '\n附件：' + attachment.name : prompt;
      const apiPrompt: string = ConversationPrompts.withAttachment(prompt, attachment);
      this.caseChat.messages =
        this.caseChat.messages.concat([new ChatMessage(ChatRole.USER, displayPrompt, [], apiPrompt)]);
      this.caseChat.input = '';
      this.caseChat.attachment = new FileAttachment();
      this.caseChat.attachmentError = '';
      this.caseChat.anchorTurn = true;
      this.scrollTurnToTop(STREAM_CASE);
      const apiMessages: ChatMessage[] =
        ConversationPrompts.messages(ConversationPrompts.caseSystem(knowledge), this.caseChat.messages);
      // As in 普法: the answer streams below the question without pulling the
      // view down.
      const outcome: StreamOutcome =
        await this.runStream(STREAM_CASE, handle, apiMessages, knowledge.citations, undefined);
      if (outcome.text.length > 0 || outcome.reasoning.length > 0) {
        this.caseChat.messages = this.caseChat.messages.concat([
          this.assistantMessage(outcome, knowledge.citations)
        ]);
      }
    } catch (error) {
      this.returnModelRequest();
      this.caseChat.error = this.errorMessage(error);
    } finally {
      this.caseChat.sending = false;
      if (this.streamHandles[STREAM_CASE] === handle) {
        this.streamHandles[STREAM_CASE] = undefined;
      }
      this.schedulePersist();
    }
  }

  // Scrolls the latest question to the top of the 普法 or 维权 conversation.
  private scrollTurnToTop(kind: number): void {
    const scroller: Scroller = this.scroller(kind);
    setTimeout(() => {
      try {
        const utils = this.getUIContext().getComponentUtils();
        const scrollTop: number =
          utils.getRectangleById(kind === STREAM_CASE ? CASE_SCROLL_ID : QUICK_SCROLL_ID).windowOffset.y;
        const turnTop: number =
          utils.getRectangleById(kind === STREAM_CASE ? CASE_TURN_ID : QUICK_TURN_ID).windowOffset.y;
        const offset: number = scroller.currentOffset().yOffset +
          this.getUIContext().px2vp(turnTop - scrollTop) - 8;
        scroller.scrollTo({
          xOffset: 0,
          yOffset: Math.max(0, offset),
          animation: { duration: this.env.reduceMotion ? 0 : 320, curve: Curve.EaseOut }
        });
      } catch (error) {
        this.scrollConversationToBottom(scroller);
      }
    }, 80);
  }

  private scroller(kind: number): Scroller {
    return kind === STREAM_CASE ? this.caseScroller : this.quickScroller;
  }

  private scrollConversationToBottom(scroller: Scroller): void {
    setTimeout(() => {
      try {
        scroller.scrollEdge(Edge.Bottom);
      } catch (error) {
        // 页面切换期间滚动控制器可能暂时未绑定，不影响咨询本身。
      }
    }, 80);
  }

  private async pickAttachment(forCase: boolean): Promise<void> {
    if (this.isAttachmentPicking) {
      return;
    }
    this.isAttachmentPicking = true;
    if (forCase) {
      this.caseChat.attachmentError = '';
    } else {
      this.quick.attachmentError = '';
    }
    try {
      const attachment: FileAttachment = await AttachmentService.pick(this.abilityContext());
      if (forCase) {
        this.caseChat.attachment = attachment;
      } else {
        this.quick.attachment = attachment;
      }
    } catch (error) {
      const message: string = this.errorMessage(error);
      if (message !== '未选择文件') {
        if (forCase) {
          this.caseChat.attachmentError = message;
        } else {
          this.quick.attachmentError = message;
        }
      }
    } finally {
      this.isAttachmentPicking = false;
    }
  }

  private openAttachmentSheet(forCase: boolean): void {
    if (this.isAttachmentPicking) {
      return;
    }
    if (forCase) {
      this.caseMessageController.stopEditing();
    } else {
      this.quickQuestionController.stopEditing();
    }
    this.sheetKind = forCase ? 2 : 1;
  }

  private async chooseAttachmentFromSheet(): Promise<void> {
    const forCase: boolean = this.sheetKind === 2;
    await this.pickAttachment(forCase);
    this.sheetKind = 0;
  }

  private openCitationSheet(citations: LawCitation[]): void {
    this.sheetCitations = citations;
    this.sheetKind = 3;
  }

  // Icon badges use a light tint in light mode, matching the scenario cards.
  private badgeBackground(): ResourceColor {
    return this.env.isDark ? this.env.cx.brand : this.env.cx.tint;
  }

  private badgeIconColor(): ResourceColor {
    return this.env.isDark ? this.env.cx.onBrand : this.env.cx.brand;
  }

  private openEvidence(query: string, category: string, importNow: boolean): void {
    this.evidenceQuery = query;
    this.evidenceCategory = category;
    this.evidenceImport = importNow;
    this.evidenceMode = EVIDENCE_MODE_LIST;
    this.sheetKind = 0;
    this.currentSection = AppSection.CASE;
    this.headerProgress = 1;
    // The library reads its starting query when it appears, so leave and
    // re-enter the page if it is already showing.
    if (this.rightsTab === RIGHTS_EVIDENCE) {
      this.rightsTab = RIGHTS_DOSSIER;
      setTimeout(() => {
        this.rightsTab = RIGHTS_EVIDENCE;
      }, 0);
    } else {
      this.rightsTab = RIGHTS_EVIDENCE;
    }
  }

  // A conversation scrolled into reading hides the tab bar, as a contract
  // report does on its own.
  private applyReading(): void {
    if (this.currentSection === AppSection.CONTRACT) {
      return;
    }
    this.setTabBarHidden(this.currentSection === AppSection.QUICK ? this.quick.reading :
      this.rightsTab === RIGHTS_CHAT && this.caseChat.reading);
    // In immersive reading 普法's title bar hides; the status bar goes with it
    // so the time and icons do not sit on the text.
    this.setStatusBarHidden(this.currentSection === AppSection.QUICK && this.quick.immersive);
  }

  private statusBarHidden: boolean = false;

  private setStatusBarHidden(hidden: boolean): void {
    if (hidden === this.statusBarHidden || this.mainWindow === undefined) {
      return;
    }
    this.statusBarHidden = hidden;
    this.mainWindow.setSpecificSystemBarEnabled('status', !hidden, true).catch(() => {
      // The status bar then simply stays.
    });
  }

  private endReading(): void {
    this.quick.reading = false;
    this.quick.immersive = false;
    this.caseChat.reading = false;
    this.caseChat.immersive = false;
  }

  // Room a conversation needs beyond the folded composer to read without
  // fitting the page: the header still to collapse, and the 维权 bars.
  private readingRoom(forCase: boolean): number {
    return HEADER_SCROLL + HEADER_SHRINK * (1 - this.headerProgress) + (forCase ? RIGHTS_BAR_HEIGHT : 0);
  }

  private showRights(tab: number): void {
    this.endReading();
    this.rightsTab = tab;
    this.syncHeader();
  }

  // While a contract report is read the tab bar steps aside with the folded
  // composer, using HdsTabs' own hide and show animations.
  private setTabBarHidden(hidden: boolean): void {
    if (hidden === this.tabBarHidden) {
      return;
    }
    this.tabBarHidden = hidden;
    try {
      if (hidden) {
        this.hdsTabsController.applyHideAnimation(HdsAnimationMode.SCROLL_ANIMATION);
      } else {
        this.hdsTabsController.applyShowAnimation(HdsAnimationMode.SCROLL_ANIMATION);
      }
    } catch (error) {
      // The tab bar then simply stays in place.
    }
  }

  // Matches the header to the page now showing: collapsed where the page
  // scrolls inside its own component (合同, 证据), otherwise as far as that
  // page is scrolled.
  private syncHeader(): void {
    let progress: number = 1;
    if (this.currentSection === AppSection.QUICK ||
      (this.currentSection === AppSection.CASE && this.rightsTab !== RIGHTS_EVIDENCE)) {
      const scroller: Scroller = this.currentSection === AppSection.QUICK ? this.quickScroller :
        this.rightsTab === RIGHTS_DOSSIER ? this.dossierScroller : this.caseScroller;
      let offset: number = 0;
      try {
        offset = scroller.currentOffset().yOffset;
      } catch (error) {
        // Not laid out yet: the page starts at the top.
      }
      progress = this.headerProgressAt(offset, this.currentSection === AppSection.QUICK ? this.quick :
        this.rightsTab === RIGHTS_DOSSIER ? undefined : this.caseChat);
    }
    if (progress === this.headerProgress) {
      return;
    }
    this.getUIContext().animateTo({ duration: this.env.reduceMotion ? 0 : 200, curve: Curve.EaseOut }, () => {
      this.headerProgress = progress;
    });
  }

  private fillDossier(field: number, value: string): void {
    const labels: string[] = ['案件发生地', '单位名称', '平均月薪', '时间节点'];
    if (field === 0) {
      this.caseState.location = value;
    } else if (field === 1) {
      this.caseState.company = value;
    } else if (field === 2) {
      this.caseState.salary = value;
    } else if (field === 3) {
      this.caseState.timeline = value;
    } else {
      return;
    }
    this.updateProgress();
    this.schedulePersist();
    this.getUIContext().getPromptAction().showToast({
      systemMaterial: Material.popup(),
      message: '已填入卷宗：' + labels[field], duration: 1500
    });
  }

  // Opens 案件 with a reviewed clause and its findings attached, plus the
  // user's question when they typed one.
  private askAboutContract(title: string, body: string, question: string = ''): void {
    this.caseChat.attachment = new FileAttachment(title, '合同审查结果', body.substring(0, EVIDENCE_TEXT_LIMIT),
      body.length > EVIDENCE_TEXT_LIMIT);
    this.caseChat.attachmentError = '';
    if (question.trim().length > 0) {
      this.caseChat.input = question.trim();
    } else if (this.caseChat.input.trim().length === 0) {
      this.caseChat.input = '这一条对我有什么影响？我该怎么做？';
    }
    this.currentSection = AppSection.CASE;
    this.showRights(RIGHTS_CHAT);
    this.scrollConversationToBottom(this.caseScroller);
  }

  // Puts the recognized text into the 案件 composer as an attachment. The
  // attachment flow already treats it as material, not instructions.
  private askWithEvidence(item: EvidenceItem): void {
    const body: string = (item.category.length > 0 ? '材料类别：' + item.category + '\n' : '')
      + (item.rowsText.length > 0 ? item.rowsText : item.text);
    const truncated: boolean = body.length > EVIDENCE_TEXT_LIMIT;
    this.caseChat.attachment = new FileAttachment(item.title, '证据图片（手机端文字识别）',
      truncated ? body.substring(0, EVIDENCE_TEXT_LIMIT) : body, truncated);
    this.caseChat.attachmentError = '';
    if (this.caseChat.input.trim().length === 0) {
      this.caseChat.input = '请结合这份材料分析：';
    }
    this.currentSection = AppSection.CASE;
    this.showRights(RIGHTS_CHAT);
    this.scrollConversationToBottom(this.caseScroller);
  }

  // 证据核对: for each 证据清单 item, evidence of a matching category counts as
  // 已有; items that only mention a term in their text are 可能相关.
  private async openChecklist(content: string): Promise<void> {
    const items: ChecklistItem[] = EvidenceExtractor.checklist(content);
    if (items.length === 0) {
      return;
    }
    let evidence: EvidenceItem[] = [];
    try {
      evidence = await EvidenceStore.load(this.abilityContext());
    } catch (error) {
      evidence = [];
    }
    this.checklistRows = items.map((item: ChecklistItem) => {
      const row: ChecklistRow = new ChecklistRow(item);
      row.matched = evidence.filter((entry: EvidenceItem) => item.categories.includes(entry.category));
      const related: SearchResult[] = EvidenceSearch.merge(evidence, item.terms.join(' '), new Map<string, number>());
      row.related = related.map((result: SearchResult) => result.item)
        .filter((entry: EvidenceItem) => !row.matched.some((match: EvidenceItem) => match.id === entry.id));
      return row;
    });
    this.sheetKind = SHEET_CHECKLIST;
  }

  private checklistHave(): number {
    return this.checklistRows.filter((row: ChecklistRow) => row.matched.length > 0).length;
  }

  // The report as it streams in, then as saved.
  private reportText(): string {
    return this.reportRun.streaming.length > 0 ? this.reportRun.streaming : this.caseState.report;
  }

  private reportTextCitations(): LawCitation[] {
    return this.reportRun.streaming.length > 0 ? this.reportRun.streamCitations : this.caseState.reportCitations;
  }

  private citationChipBg(): string {
    return this.env.isDark ? '#2A2416' : '#F6EAD2';
  }

  private syncActiveCitation(): void {
    this.activeCitation = this.sheetKind === SHEET_CITATION ? CitationKey.of(this.detailContent, this.detailIndex) : '';
  }

  private bindActions(): void {
    this.chatActions.openCitation = (content: string, citations: LawCitation[], index: number) => {
      this.openCitationDetail(content, citations, index);
    };
    this.chatActions.openCitations = (citations: LawCitation[]) => {
      this.openCitationSheet(citations);
    };
    this.chatActions.openChecklist = (content: string) => {
      this.openChecklist(content);
    };
    this.chatActions.selecting = (active: boolean) => {
      this.textSelecting = active;
    };
    this.chatActions.isSelecting = (): boolean => this.textSelecting;
    this.chatActions.send = (forCase: boolean) => {
      if (forCase) {
        this.sendCaseMessage();
      } else {
        this.sendQuickQuestion();
      }
    };
    this.chatActions.stop = (forCase: boolean) => {
      this.stopStream(forCase ? STREAM_CASE : STREAM_QUICK);
    };
    this.chatActions.attach = (forCase: boolean) => {
      this.openAttachmentSheet(forCase);
    };
    this.drawerActions.close = () => {
      this.closeHistoryDrawer();
    };
    this.drawerActions.startNew = () => {
      this.startNewConsultation();
    };
    this.drawerActions.open = (session: QuickSession) => {
      this.openSessionFromDrawer(session);
    };
    this.drawerActions.remove = (id: string) => {
      this.deleteQuickSession(id);
    };
    this.quickEvents.scrolled = (scroller: Scroller) => {
      this.updateHeaderForScroll(scroller, this.quick);
    };
    this.quickEvents.openSettings = () => {
      this.mineOpen = true;
    };
    this.quickEvents.lawsOnly = () => {
      this.answerFromLawsOnly();
    };
    this.quickEvents.swipeStart = () => {
      this.beginDrawerSwipe();
    };
    this.quickEvents.swipeUpdate = (offsetX: number) => {
      this.drawer.updateSwipe(offsetX);
    };
    this.quickEvents.swipeEnd = (offsetX: number, velocityX: number) => {
      this.drawer.endSwipe(this.getUIContext(), this.env.reduceMotion, offsetX, velocityX);
    };
    this.caseEvents.scrolled = (scroller: Scroller) => {
      this.updateHeaderForScroll(scroller, this.caseChat);
    };
    this.caseEvents.openSettings = () => {
      this.mineOpen = true;
    };
    this.dossierActions.changed = () => {
      this.updateProgress();
      this.schedulePersist();
    };
    this.dossierActions.toggleFloat = () => {
      this.toggleFloatChecklist();
    };
    this.dossierActions.generate = () => {
      this.openReportSheet();
    };
    this.dossierActions.stop = () => {
      this.stopStream(STREAM_REPORT);
    };
    this.dossierActions.openSettings = () => {
      this.mineOpen = true;
    };
    this.dossierActions.scrolled = (scroller: Scroller) => {
      this.updateHeaderForScroll(scroller);
    };
    this.mineActions.close = () => {
      this.mineOpen = false;
    };
    this.mineActions.test = () => {
      this.testConnection();
    };
    this.mineActions.clear = () => {
      this.clearLocalRecords();
    };
    this.mineActions.setTheme = (mode: number) => {
      this.setThemeMode(mode);
    };
    this.mineActions.saveShowReasoning = (value: boolean) => {
      this.saveReasoningFlag(SHOW_REASONING_KEY, value);
    };
    this.mineActions.setBuiltin = (value: boolean) => {
      this.setUseBuiltin(value);
    };
    this.mineActions.setLightLevel = (level: number) => {
      this.env.lightLevel = level;
      ConfigStore.saveNumber(this.abilityContext(), LIGHT_LEVEL_KEY, level).catch(() => {
        // The level still applies for this session.
      });
    };
    this.mineActions.saveAutoExpand = (value: boolean) => {
      this.saveReasoningFlag(EXPAND_REASONING_KEY, value);
    };
  }

  private openCitationDetail(content: string, citations: LawCitation[], index: number): void {
    if (index < 0 || index >= citations.length) {
      return;
    }
    this.quickQuestionController.stopEditing();
    this.caseMessageController.stopEditing();
    this.detailReturnSheet = this.sheetKind === 4 ? 4 : 0;
    this.detailLeads = CitationText.leads(content, citations.length);
    this.detailCitations = citations;
    this.detailContent = content;
    this.detailIndex = index;
    this.sheetKind = SHEET_CITATION;
  }

  private closeCitationDetail(): void {
    this.sheetKind = this.detailReturnSheet;
    this.detailReturnSheet = 0;
  }

  private stepCitation(delta: number): void {
    const next: number = this.detailIndex + delta;
    if (next >= 0 && next < this.detailCitations.length) {
      this.detailIndex = next;
    }
  }

  private detailCitation(): LawCitation | undefined {
    return this.detailIndex < this.detailCitations.length ? this.detailCitations[this.detailIndex] : undefined;
  }

  private detailHighlight(): HighlightRange | undefined {
    const citation: LawCitation | undefined = this.detailCitation();
    if (citation === undefined || this.detailIndex >= this.detailLeads.length) {
      return undefined;
    }
    return CitationText.highlight(citation.excerpt, this.detailLeads[this.detailIndex]);
  }

  private statusLabel(status: string): string {
    if (status.includes('失效') || status.includes('废止')) {
      return status.includes('部分') ? '部分失效' : '已失效';
    }
    if (status.includes('尚未生效')) {
      return '尚未生效';
    }
    if (status.includes('修订')) {
      return '已被修订';
    }
    if (status.includes('现行有效')) {
      return '现行有效';
    }
    return '效力未标注';
  }

  private statusColor(status: string): ResourceColor {
    const label: string = this.statusLabel(status);
    if (label === '现行有效') {
      return this.env.cx.ok;
    }
    if (label === '已失效' || label === '部分失效') {
      return this.env.cx.danger;
    }
    if (label === '效力未标注') {
      return this.env.cx.muted;
    }
    return this.env.cx.warn;
  }

  private statusBg(status: string): ResourceColor {
    const label: string = this.statusLabel(status);
    if (label === '现行有效') {
      return this.env.cx.okBg;
    }
    if (label === '已失效' || label === '部分失效') {
      return this.env.cx.dangerBg;
    }
    if (label === '效力未标注') {
      return this.env.cx.tint;
    }
    return this.env.isDark ? '#2A2416' : '#F6E9CE';
  }

  private openReportSheet(): void {
    if (this.caseState.progress < 60) {
      return;
    }
    this.reportStage = this.caseState.report.length > 0 ? 4 : 0;
    this.sheetKind = 4;
  }

  private sheetMaterial(): uiMaterial.Material | undefined {
    return Material.dialog(this.env.isDark);
  }

  private async generateReport(): Promise<void> {
    if (this.caseState.progress < 60 || this.reportRun.sending) {
      return;
    }
    const validationError: string = AiApiClient.validateConfig(this.env.config());
    if (validationError.length > 0) {
      this.reportRun.error = validationError + CONFIG_HINT;
      return;
    }
    if (!KnowledgeService.isReady()) {
      this.reportRun.error = '本地法律资料尚未就绪，请稍后再试';
      return;
    }
    const quotaError: string = this.takeModelRequest();
    if (quotaError.length > 0) {
      this.reportRun.error = quotaError;
      return;
    }
    this.fieldControllers.forEach((controller: TextInputController) => {
      controller.stopEditing();
    });
    this.detailsController.stopEditing();
    this.reportRun.sending = true;
    this.reportRun.error = '';
    this.reportStage = 1;
    const handle: StreamHandle = this.beginStream(STREAM_REPORT);
    try {
      const summary: string = ConversationPrompts.dossierSummary(this.currentDossier());
      let evidenceText: string = '';
      try {
        evidenceText = ConversationPrompts.evidenceSummary(await EvidenceStore.load(this.abilityContext()));
      } catch (error) {
        evidenceText = '';
      }
      this.reportStage = 2;
      const knowledge: KnowledgeResult = await KnowledgeService.search(summary);
      if (handle.cancelled) {
        this.reportStage = this.caseState.report.length > 0 ? 4 : 0;
        return;
      }
      const messages: ChatMessage[] = [
        new ChatMessage(ChatRole.SYSTEM, ConversationPrompts.reportSystem(knowledge)),
        new ChatMessage(ChatRole.USER, summary + evidenceText)
      ];
      this.reportStage = 3;
      const outcome: StreamOutcome =
        await this.runStream(STREAM_REPORT, handle, messages, knowledge.citations, undefined);
      if (outcome.text.length === 0) {
        this.reportStage = this.caseState.report.length > 0 ? 4 : 0;
        return;
      }
      this.caseState.report = this.finalAnswer(outcome, knowledge.citations);
      this.caseState.reportCitations = knowledge.citations;
      this.reportStage = 4;
    } catch (error) {
      this.returnModelRequest();
      this.reportRun.error = this.errorMessage(error);
      this.reportStage = 0;
    } finally {
      this.reportRun.sending = false;
      if (this.streamHandles[STREAM_REPORT] === handle) {
        this.streamHandles[STREAM_REPORT] = undefined;
      }
      this.schedulePersist();
    }
  }

  private updateProgress(): void {
    let count: number = 0;
    let mask: number = 0;
    for (let index: number = 0; index < 6; index++) {
      if (this.fieldFilled(index)) {
        count++;
        mask |= 1 << index;
      }
    }
    ChecklistFloatService.update(mask);
    const nextProgress: number = Math.round(count * 100 / 6);
    if (nextProgress !== this.caseState.progress) {
      this.getUIContext().animateTo({ duration: this.env.reduceMotion ? 0 : 240, curve: Curve.EaseOut }, () => {
        this.caseState.progress = nextProgress;
      });
    }
  }

  private async toggleFloatChecklist(): Promise<void> {
    if (this.checklistFloatBusy) {
      return;
    }
    this.checklistFloatBusy = true;
    this.checklistFloatError = '';
    try {
      if (ChecklistFloatService.isOpen()) {
        await ChecklistFloatService.stop();
        this.checklistFloatActive = false;
      } else {
        let mask: number = 0;
        for (let index: number = 0; index < 6; index++) {
          if (this.fieldFilled(index)) {
            mask |= 1 << index;
          }
        }
        await ChecklistFloatService.open(this.abilityContext(), mask, this.env.isDark);
        this.checklistFloatActive = true;
      }
    } catch (error) {
      this.checklistFloatError = this.errorMessage(error);
    } finally {
      this.checklistFloatBusy = false;
    }
  }

  private fieldFilled(index: number): boolean {
    return this.caseState.fieldFilled(index);
  }

  private scenarioGold(index: number): boolean {
    return index % 2 === 1;
  }

  private returnToQuickHome(): void {
    if (this.quick.sending) {
      return;
    }
    this.quickQuestionController.stopEditing();
    this.recordQuickSession();
    this.quickSessionId = '';
    this.quick.input = '';
    this.quick.messages = [];
    this.quick.anchorTurn = false;
    this.quick.error = '';
    this.quick.attachment = new FileAttachment();
    this.quick.attachmentError = '';
    this.quick.reading = false;
    this.quick.immersive = false;
    this.headerProgress = 0;
    // The home replaces the conversation without a scroll, so the title bar
    // would stay in its scrolled, glass look; scrolling to the top tells it.
    setTimeout(() => {
      this.quickScroller.scrollTo({ xOffset: 0, yOffset: 0 });
    }, 50);
    this.schedulePersist();
  }

  // How far the header is collapsed with the page scrolled to offset. It
  // shrinks by HEADER_SHRINK over the first HEADER_SCROLL, and the page below
  // grows by as much. A conversation only a little taller than its page would
  // then fit, snap back to the top and open the header again, so one that
  // cannot scroll past the collapse keeps the header open.
  private headerProgressAt(offset: number, chat?: ChatSession): number {
    if (chat !== undefined) {
      const openViewport: number = chat.viewportHeight - HEADER_SHRINK * this.headerProgress;
      if (chat.contentHeight - openViewport < HEADER_SCROLL + HEADER_SHRINK) {
        return 0;
      }
    }
    return this.env.reduceMotion ? (offset > 72 ? 1 : 0) : Math.max(0, Math.min(1, offset / HEADER_SCROLL));
  }

  private updateHeaderForScroll(scroller: Scroller, chat?: ChatSession): void {
    const progress: number = this.headerProgressAt(scroller.currentOffset().yOffset, chat);
    if (Math.abs(progress - this.headerProgress) >= 0.01 || progress === 0 || progress === 1) {
      this.headerProgress = progress;
    }
  }

  private sectionTitle(): string {
    if (this.currentSection === AppSection.CASE) {
      return this.rightsTab === RIGHTS_CHAT && this.caseChat.reading ? this.currentCaseTitle() + ' · 梳理' : '维权';
    }
    if (this.currentSection === AppSection.CONTRACT) {
      return '合同体检';
    }
    return '劳动权益助手';
  }

  private sectionSubtitle(): string {
    if (this.currentSection === AppSection.CASE) {
      return '梳理事实、整理卷宗、管理证据';
    }
    if (this.currentSection === AppSection.CONTRACT) {
      return '逐条检查劳动合同里的红线条款';
    }
    return '懂法律，更懂你的难处';
  }

  private scenarioIcon(index: number): Resource {
    if (index === 0) {
      return $r('app.media.ic_coin');
    }
    if (index === 1) {
      return $r('app.media.ic_flame');
    }
    if (index === 2) {
      return $r('app.media.ic_doc');
    }
    return $r('app.media.ic_clock');
  }

  private floatingStyle(): HdsTabsFloatingStyle {
    const t: ThemeColors = this.env.cx;
    return {
      barWidth: {
        smallWidth: 268,
        mediumWidth: 330,
        largeWidth: 330
      },
      barSideMargin: 20,
      barBottomMargin: 30,
      // No mask behind the bar: content scrolling under it shows through its
      // glass (沉浸光感). A background-colored mask here hides the material.
      gradientMask: {
        maskColor: t.bgBottom,
        maskHeight: 0
      },
      // On wide devices the bar follows the hand holding it.
      adaptToHandedness: true,
      lightColor: t.glow,
      systemMaterialEffect: {
        materialType: Material.hdsType(),
        materialLevel: Material.hdsLevel(this.env.lightLevel, this.env.reduceMotion)
      },
      thermoCtrl: true,
      // Set even at its default: the keyboard style hides the bar with 0, and
      // a field left out keeps its last value when the style switches back.
      barOpacity: 1,
      miniBar: {
        miniBarBuilder: (): void => {
          this.MineButton()
        },
        miniBarWidth: { smallWidth: 64, mediumWidth: 64, largeWidth: 64 },
        miniBarStyle: HdsBarStyle.COLLAPSE
      }
    };
  }

  // 我的, the round control beside the tab bar (HdsTabs mini bar).
  @Builder
  private MineButton() {
    Column({ space: 3 }) {
      ChatIcon({ res: $r('app.media.ic_person'), size: 21, color: this.env.cx.muted })
      Text('我的').fontSize(11).fontColor(this.env.cx.muted)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .accessibilityText('我的')
    .clickEffect(this.env.reduceMotion ? null : { level: ClickEffectLevel.LIGHT, scale: 0.94 })
    .onClick(() => {
      this.quickQuestionController.stopEditing();
      this.mineOpen = true;
    })
  }

  private keyboardHiddenStyle(): HdsTabsFloatingStyle {
    const t: ThemeColors = this.env.cx;
    return {
      barWidth: {
        smallWidth: 344,
        mediumWidth: 420,
        largeWidth: 420
      },
      barSideMargin: 20,
      barBottomMargin: 0,
      gradientMask: {
        maskColor: t.bgBottom,
        maskHeight: 0
      },
      adaptToHandedness: false,
      lightColor: t.glow,
      systemMaterialEffect: {
        materialType: Material.hdsType(),
        materialLevel: Material.hdsLevel(this.env.lightLevel, this.env.reduceMotion)
      },
      thermoCtrl: true,
      barOpacity: 0
    };
  }

  // Room the collapsed title leaves for the header actions on the 普法 page.
  private headerActionsWidth(): number {
    if (this.currentSection !== AppSection.QUICK) {
      return 0;
    }
    return this.quick.messages.length > 0 ? 94 : 46;
  }

  @Builder
  private GlassIconButton(res: Resource, label: string, action: number) {
    Column() {
      ChatIcon({ res: res, size: 19, color: this.env.cx.gold })
    }
    .width(40)
    .height(40)
    .justifyContent(FlexAlign.Center)
    .borderRadius(20)
    .backgroundColor(this.env.isDark ? '#661C2A44' : '#59FFFFFF')
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN, Material.blurOptions(this.env.isDark))
    .border({ width: 1, color: this.env.cx.navBorder })
    .shadow({ radius: 14, color: this.env.cx.navShadow, offsetY: 3 })
    .visualEffect(pointLight(LIGHT_BUTTON, this.env.isDark, this.env.cx))
    .enabled(action === 1 || !this.quick.sending)
    .opacity(action === 1 || !this.quick.sending ? 1 : 0.5)
    .accessibilityText(label)
    .onClick(() => {
      if (action === 0) {
        this.startNewConsultation();
      } else {
        this.openHistoryDrawer();
      }
    })
  }

  @Builder
  private Header() {
    Stack() {
      Row() {
        Blank()
        Image($r('app.media.ic_scale'))
          .width(150 - 50 * this.headerProgress)
          .height(150 - 50 * this.headerProgress)
          .fillColor(this.env.cx.headerText)
          .opacity(0.10)
          .margin({ top: 24, right: -14 })
      }
      .width('100%')
      .height('100%')
      .alignItems(VerticalAlign.Top)

      Column() {
        Text(this.sectionTitle())
          .fontSize(26 - 6 * this.headerProgress)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontWeight(FontWeight.Bold)
          .fontColor(this.env.cx.headerText)
        Text(this.sectionSubtitle())
          .fontSize(13)
          .fontColor(this.env.cx.headerSub)
          .height(20 * (1 - this.headerProgress))
          .opacity(Math.max(0, 1 - 2 * this.headerProgress))
          .margin({ top: 6 * (1 - this.headerProgress) })
        Row()
          .width(34)
          .height(3 * (1 - this.headerProgress))
          .opacity(Math.max(0, 1 - 2 * this.headerProgress))
          .backgroundColor(this.env.cx.glow)
          .borderRadius(2)
          .margin({ top: 12 * (1 - this.headerProgress) })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .height('100%')
      .padding({
        left: 22 + this.headerActionsWidth() * this.headerProgress,
        right: 22,
        top: 54 - 2 * this.headerProgress,
        bottom: 18
      })

      if (this.currentSection === AppSection.QUICK) {
        // One set of actions that glides from under the gold accent line
        // (expanded) to in front of the title (collapsed).
        Row({ space: 8 }) {
          this.GlassIconButton($r('app.media.ic_menu'), '历史咨询', 1)
          if (this.quick.messages.length > 0) {
            this.GlassIconButton($r('app.media.ic_home'), '返回普法首页', 0)
          }
        }
        .position({ x: 22 - 6 * this.headerProgress, y: 138 - 92 * this.headerProgress })
      }
    }
    .width('100%')
    .height(HEADER_HEIGHT - HEADER_SHRINK * this.headerProgress)
    .clip(true)
    .linearGradient({
      angle: 118,
      colors: [[this.env.cx.headerA, 0.0], [this.env.cx.headerB, 0.58], [this.env.cx.headerC, 1.0]]
    })
  }

  @Builder
  private NoticeCard() {
    Row() {
      Text('提示')
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.env.cx.warn)
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor(this.env.isDark ? '#2A2416' : '#F6E9CE')
        .borderRadius(7)
      Text('AI 内容仅供参考，重要决定请核对最新法规或咨询专业人士。')
        .fontSize(11)
        .lineHeight(17)
        .fontColor(this.env.cx.muted)
        .layoutWeight(1)
        .margin({ left: 8 })
    }
    .width('100%')
    .padding(11)
    .backgroundColor(this.env.cx.surface2)
    .borderRadius(14)
  }

  @Builder
  private CitationItem(citation: LawCitation, expanded: boolean = false) {
    Column() {
      Row({ space: 6 }) {
        Text(citation.id.startsWith('K') ? citation.id.substring(1) : citation.id)
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.env.cx.onBrand)
          .padding({ left: 6, right: 6, top: 1, bottom: 1 })
          .backgroundColor(this.env.cx.brand)
          .borderRadius(6)
        Text(citation.title + ' · ' + citation.article)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.env.cx.text)
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(citation.status.includes('失效') ? '已失效' : '现行')
          .fontSize(9)
          .fontWeight(FontWeight.Bold)
          .fontColor(citation.status.includes('失效') ? this.env.cx.danger : this.env.cx.ok)
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .backgroundColor(citation.status.includes('失效') ? this.env.cx.dangerBg : this.env.cx.okBg)
          .borderRadius(999)
      }
      .width('100%')
      Text(!expanded && citation.excerpt.length > 240 ?
        citation.excerpt.substring(0, 240) + '…' : citation.excerpt)
        .fontSize(11)
        .lineHeight(17)
        .fontColor(this.env.cx.muted)
        .width('100%')
        .margin({ top: 7 })
      Text('来源：' + citation.source
        + (citation.effectiveDate.length > 0 ? ' · 生效 ' + citation.effectiveDate : ''))
        .fontSize(10)
        .lineHeight(15)
        .fontColor(this.env.cx.faint)
        .width('100%')
        .margin({ top: 6 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(11)
    .backgroundColor(this.env.cx.surface)
    .borderRadius(12)
    .border({ width: 1, color: this.env.cx.line })
  }

  @Builder
  private ChecklistBody() {
    Scroll() {
      Column({ space: 10 }) {
        ForEach(this.checklistRows, (row: ChecklistRow) => {
          Row({ space: 10 }) {
            Column({ space: 4 }) {
              Text(row.item.name)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.env.cx.text)
                .width('100%')
              Text(row.matched.length > 0 ? row.matched.map((entry: EvidenceItem) => entry.title).join('、') :
                (row.related.length > 0 ? '文字提到：' + row.related.map((entry: EvidenceItem) => entry.title).join('、') :
                  row.item.detail))
                .fontSize(11)
                .fontColor(this.env.cx.muted)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text(row.matched.length > 0 ? '已有 ' + row.matched.length.toString() + ' 份' :
              (row.related.length > 0 ? '可能相关' : '缺少 · 去导入'))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(row.matched.length > 0 ? this.env.cx.ok : (row.related.length > 0 ? this.env.cx.warn : this.env.cx.danger))
              .padding({ left: 9, right: 9, top: 4, bottom: 4 })
              .backgroundColor(row.matched.length > 0 ? this.env.cx.okBg :
                (row.related.length > 0 ? this.citationChipBg() : this.env.cx.dangerBg))
              .borderRadius(999)
          }
          .width('100%')
          .padding(12)
          .backgroundColor(this.env.cx.surface)
          .borderRadius(14)
          .border({ width: 1, color: this.env.cx.line })
          .onClick(() => {
            if (row.matched.length > 0 && row.item.categories.length > 0) {
              this.openEvidence('', row.matched[0].category, false);
            } else if (row.related.length > 0) {
              this.openEvidence(row.item.terms.length > 1 ? row.item.terms[1] : row.item.name, '', false);
            } else {
              this.openEvidence('', '', true);
            }
          })
        }, (row: ChecklistRow) => row.item.name)
        Text('「已有」按材料类别判断，「可能相关」表示材料文字里提到了相关内容，请以实际材料为准。')
          .fontSize(10.5)
          .lineHeight(16)
          .fontColor(this.env.cx.faint)
          .width('100%')
      }
      .width('100%')
      .padding({ bottom: 28 })
    }
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .width('100%')
  }

  @Builder
  private CitationStepButton(label: string, delta: number) {
    Text(label)
      .fontSize(20)
      .fontColor(this.detailIndex + delta >= 0 && this.detailIndex + delta < this.detailCitations.length ?
        this.env.cx.gold : this.env.cx.faint)
      .textAlign(TextAlign.Center)
      .width(34)
      .height(34)
      .backgroundColor(this.env.cx.tint)
      .borderRadius(17)
      .accessibilityText(delta < 0 ? '上一条依据' : '下一条依据')
      .onClick(() => {
        this.stepCitation(delta);
      })
  }

  @Builder
  private CitationDetailHeader() {
    Row({ space: 8 }) {
      Text('依据 ' + (this.detailIndex + 1).toString())
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.env.cx.onGold)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .backgroundColor(this.env.cx.gold)
        .borderRadius(999)
      Text('共 ' + this.detailCitations.length.toString() + ' 条')
        .fontSize(12)
        .fontColor(this.env.cx.muted)
      Blank()
      this.CitationStepButton('‹', -1)
      this.CitationStepButton('›', 1)
      Button('关闭')
        .fontSize(12)
        .fontColor(this.env.cx.brand)
        .height(34)
        .backgroundColor(this.env.cx.tint)
        .borderRadius(10)
        .margin({ left: 4 })
        .onClick(() => {
          this.closeCitationDetail();
        })
    }
    .width('100%')
  }

  @Builder
  private CitationDetailBody() {
    if (this.detailCitation() !== undefined) {
      Column({ space: 12 }) {
        Column({ space: 4 }) {
          Text(this.detailCitation()!.title)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.env.cx.text)
            .width('100%')
          if (this.detailCitation()!.article.length > 0) {
            Text(this.detailCitation()!.article)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.env.cx.gold)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        Row({ space: 6 }) {
          Text(this.statusLabel(this.detailCitation()!.status))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.statusColor(this.detailCitation()!.status))
            .padding({ left: 9, right: 9, top: 3, bottom: 3 })
            .backgroundColor(this.statusBg(this.detailCitation()!.status))
            .borderRadius(999)
          if (this.detailCitation()!.effectiveDate.length > 0) {
            Text(this.detailCitation()!.effectiveDate + ' 施行')
              .fontSize(11)
              .fontColor(this.env.cx.muted)
              .padding({ left: 9, right: 9, top: 3, bottom: 3 })
              .backgroundColor(this.env.cx.tint)
              .borderRadius(999)
          }
        }
        .width('100%')
        Scroll() {
          if (this.detailHighlight() !== undefined) {
            Text() {
              Span(this.detailCitation()!.excerpt.substring(0, this.detailHighlight()!.start))
              Span(this.detailCitation()!.excerpt.substring(this.detailHighlight()!.start,
                this.detailHighlight()!.end))
                .fontColor(this.env.cx.text)
                .fontWeight(FontWeight.Medium)
                .textBackgroundStyle({ color: this.env.isDark ? '#33E0B45C' : '#33C0842A', radius: 4 })
              Span(this.detailCitation()!.excerpt.substring(this.detailHighlight()!.end))
            }
            .fontSize(14)
            .lineHeight(23)
            .fontColor(this.env.cx.muted)
            .width('100%')
          } else {
            Text(this.detailCitation()!.excerpt)
              .fontSize(14)
              .lineHeight(23)
              .fontColor(this.env.cx.muted)
              .width('100%')
          }
        }
        .layoutWeight(1)
        .width('100%')
        .padding(14)
        .align(Alignment.TopStart)
        .backgroundColor(this.env.cx.surface)
        .borderRadius(14)
        .border({ width: 1, color: this.env.cx.line })
        .scrollBar(BarState.Auto)
        Row({ space: 6 }) {
          ChatIcon({ res: $r('app.media.ic_doc'), size: 13, color: this.env.cx.faint })
          Text(this.detailCitation()!.source)
            .fontSize(11)
            .fontColor(this.env.cx.faint)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text('全部依据 ›')
            .fontSize(12)
            .fontColor(this.env.cx.brand)
            .padding({ left: 8, top: 4, bottom: 4 })
            .onClick(() => {
              this.sheetCitations = this.detailCitations;
              this.detailReturnSheet = 0;
              this.sheetKind = 3;
            })
        }
        .width('100%')
        Text('资料为机械收录，尚未完成全面法律效力审查，请以官方最新文本为准。')
          .fontSize(10.5)
          .lineHeight(15)
          .fontColor(this.env.cx.faint)
          .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
    }
  }

  @Builder
  private ReportStageRow(label: string, stage: number) {
    Row({ space: 10 }) {
      Text(this.reportStage > stage ? '✓' : stage.toString())
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.reportStage >= stage ? this.env.cx.onBrand : this.env.cx.faint)
        .textAlign(TextAlign.Center)
        .width(26)
        .height(26)
        .backgroundColor(this.reportStage >= stage ? this.env.cx.brand : this.env.cx.surface2)
        .borderRadius(13)
      Text(label)
        .fontSize(14)
        .fontColor(this.reportStage >= stage ? this.env.cx.text : this.env.cx.muted)
        .layoutWeight(1)
      if (this.reportStage === stage && this.reportRun.sending) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(this.env.cx.gold)
      }
    }
    .width('100%')
    .padding({ top: 7, bottom: 7 })
  }

  @Builder
  private UnifiedSheet() {
    Column({ space: 16 }) {
      if (this.sheetKind === SHEET_CITATION) {
        this.CitationDetailHeader()
      } else {
        Row() {
          Column({ space: 4 }) {
            Text(this.sheetKind === 3 ? '本轮检索依据' :
              this.sheetKind === 4 ? '案件分析报告' :
              this.sheetKind === SHEET_CASES ? '我的案件' :
              this.sheetKind === SHEET_CHECKLIST ? '证据核对' : '添加咨询材料')
              .fontSize(19)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.env.cx.text)
            Text(this.sheetKind === 3 ?
              this.sheetCitations.length.toString() + ' 条本地法规片段' :
              this.sheetKind === 4 ? '整理事实、检索依据，再生成报告' :
              this.sheetKind === SHEET_CASES ? '每个案件有各自的对话、卷宗和报告 · 证据库共用' :
              this.sheetKind === SHEET_CHECKLIST ? '对照回答里的证据清单 · 已有 ' + this.checklistHave().toString()
                + ' / ' + this.checklistRows.length.toString() :
              '由你主动选择要分析的文件')
              .fontSize(12)
              .fontColor(this.env.cx.muted)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Button('关闭')
            .fontSize(12)
            .fontColor(this.env.cx.brand)
            .height(34)
            .backgroundColor(this.env.cx.tint)
            .borderRadius(10)
            .onClick(() => {
              this.sheetKind = 0;
            })
        }
        .width('100%')
      }

      if (this.sheetKind === SHEET_CITATION) {
        this.CitationDetailBody()
      } else if (this.sheetKind === SHEET_CHECKLIST) {
        this.ChecklistBody()
      } else if (this.sheetKind === SHEET_CASES) {
        this.CasesBody()
      } else if (this.sheetKind === 3) {
        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.sheetCitations, (citation: LawCitation) => {
              this.CitationItem(citation, true)
            })
            Text('资料为机械收录，尚未完成全面法律效力审查，请以官方最新文本为准。')
              .fontSize(11)
              .lineHeight(17)
              .fontColor(this.env.cx.muted)
              .width('100%')
          }
          .width('100%')
          .padding({ bottom: 28 })
        }
        .scrollBar(BarState.Auto)
        .layoutWeight(1)
        .width('100%')
      } else if (this.sheetKind === 4) {
        Column({ space: 12 }) {
          Column() {
            this.ReportStageRow('整理已填写的案情', 1)
            this.ReportStageRow('检索本地法规依据', 2)
            this.ReportStageRow('调用所选模型生成报告', 3)
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .backgroundColor(this.env.cx.surface)
          .borderRadius(16)
          .border({ width: 1, color: this.env.cx.line })
          if (this.reportRun.error.length > 0) {
            Text(this.reportRun.error)
              .fontSize(12)
              .fontColor(this.env.cx.danger)
              .width('100%')
          }
          if (this.reportRun.streaming.length > 0 || this.caseState.report.length > 0) {
            Scroll() {
              Column({ space: 12 }) {
                AnswerText({
                  content: this.reportText(),
                  citations: this.reportTextCitations(),
                  report: true,
                  selectable: this.reportRun.streaming.length === 0,
                  actions: this.chatActions
                })
                if (this.reportRun.streaming.length === 0) {
                  AnswerActionsView({
                    content: this.caseState.report,
                    citations: this.caseState.reportCitations,
                    report: true,
                    actions: this.chatActions
                  })
                }
                if (this.reportRun.streaming.length === 0 && this.caseState.reportCitations.length > 0) {
                  Button('查看 ' + this.caseState.reportCitations.length.toString() + ' 条法规依据')
                    .fontSize(13)
                    .fontColor(this.env.cx.brand)
                    .backgroundColor(this.env.cx.tint)
                    .onClick(() => {
                      this.openCitationSheet(this.caseState.reportCitations);
                    })
                }
              }
              .width('100%')
              .padding(14)
            }
            .scrollBar(BarState.Auto)
            .layoutWeight(1)
            .width('100%')
            .backgroundColor(this.env.cx.surface)
            .borderRadius(16)
          } else {
            Text('报告内容仅供初步参考。重要决定请核对最新法规，必要时咨询专业人士。')
              .fontSize(12)
              .lineHeight(18)
              .fontColor(this.env.cx.muted)
              .width('100%')
          }
          Button(this.reportRun.sending ? '停止生成' :
            (this.caseState.report.length > 0 ? '重新生成报告' : '开始生成报告'))
            .width('100%')
            .height(48)
            .fontSize(15)
            .fontColor(this.reportRun.sending ? this.env.cx.danger : this.env.cx.onBrand)
            .backgroundColor(this.reportRun.sending ? this.env.cx.dangerBg : this.env.cx.brand)
            .borderRadius(15)
            .onClick(() => {
              if (this.reportRun.sending) {
                this.stopStream(STREAM_REPORT);
              } else {
                this.generateReport();
              }
            })
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        Column({ space: 12 }) {
          Row({ space: 11 }) {
            ChatIcon({ res: $r('app.media.ic_doc'), size: 24, color: this.env.cx.brand })
            Column({ space: 4 }) {
              Text('选择本机文件')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.env.cx.text)
              Text('支持 TXT、MD、DOCX；暂不识别图片或扫描件')
                .fontSize(11)
                .fontColor(this.env.cx.muted)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .padding(14)
          .backgroundColor(this.env.cx.surface)
          .borderRadius(16)
          .border({ width: 1, color: this.env.cx.line })
          Text('文件只在本机提取文字；点击发送咨询后，选中的内容才会发给你配置的模型服务商。')
            .fontSize(11)
            .lineHeight(17)
            .fontColor(this.env.cx.muted)
            .width('100%')
          Button('继续选择文件')
            .width('100%')
            .height(48)
            .fontSize(15)
            .fontColor(this.env.cx.onBrand)
            .backgroundColor(this.env.cx.brand)
            .borderRadius(15)
            .onClick(() => {
              this.chooseAttachmentFromSheet();
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 20, right: 20, top: 22, bottom: 20 })
  }

  @Builder
  private EvidencePane() {
    EvidenceLibrary({
      cx: this.env.cx,
      isDark: this.env.isDark,
      mode: $evidenceMode,
      embedded: true,
      bottomInset: this.env.keyboardVisible ? 0 : TAB_BAR_CLEARANCE,
      onClose: () => {
        this.showRights(RIGHTS_CHAT);
      },
      onCountChange: (count: number) => {
        this.evidenceCount = count;
      },
      dossierValues: [this.caseState.location, this.caseState.company, this.caseState.salary, this.caseState.timeline, this.caseState.request, this.caseState.details],
      onFill: (field: number, value: string) => {
        this.fillDossier(field, value);
      },
      onAsk: (item: EvidenceItem) => {
        this.askWithEvidence(item);
      },
      initialQuery: this.evidenceQuery,
      initialCategory: this.evidenceCategory,
      initialImport: this.evidenceImport
    })
  }

  @Builder
  private CaseRow(title: string, detail: string, current: boolean, record: CaseRecord | undefined) {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text(title)
          .fontSize(14)
          .fontWeight(current ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.env.cx.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(detail)
          .fontSize(11)
          .fontColor(this.env.cx.muted)
          .width('100%')
      }
      .layoutWeight(1)
      if (current) {
        Text('当前')
          .fontSize(10.5)
          .fontColor(this.env.cx.gold)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(this.citationChipBg())
          .borderRadius(9)
      } else if (record !== undefined) {
        Text('删除')
          .fontSize(11.5)
          .fontColor(this.env.cx.faint)
          .padding(6)
          .onClick(() => {
            this.deleteCase(record);
          })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(current ? this.env.cx.tint : this.env.cx.surface)
    .borderRadius(14)
    .border({ width: 1, color: current ? this.env.cx.gold : this.env.cx.line })
    .onClick(() => {
      if (record !== undefined) {
        this.openCase(record.id);
      } else {
        this.sheetKind = 0;
      }
    })
  }

  @Builder
  private CasesBody() {
    Column({ space: 12 }) {
      Button('＋ 新案件')
        .width('100%')
        .height(42)
        .fontSize(14)
        .fontColor(this.env.cx.onGold)
        .backgroundColor(this.env.cx.gold)
        .borderRadius(13)
        .enabled(!this.caseBusy() && this.hasCaseContent())
        .onClick(() => {
          this.startNewCase();
        })
      Scroll() {
        Column({ space: 10 }) {
          this.CaseRow(this.currentCaseTitle(),
            this.caseChat.messages.length.toString() + ' 条消息 · 卷宗 ' + this.caseState.progress.toString() + '%', true, undefined)
          ForEach(this.caseState.history, (record: CaseRecord) => {
            this.CaseRow(record.title, new Date(record.updatedAt).toLocaleDateString() + ' · ' +
              record.messages.length.toString() + ' 条消息' + (record.dossier.report.length > 0 ? ' · 已出报告' : ''),
              false, record)
          }, (record: CaseRecord) => record.id + '_' + record.updatedAt.toString())
          if (this.caseState.history.length === 0) {
            Text('开始新案件后，之前的案件会存档在这里，可以随时切换回来继续。')
              .fontSize(11.5)
              .lineHeight(18)
              .fontColor(this.env.cx.muted)
              .width('100%')
              .margin({ top: 4 })
          }
        }
        .width('100%')
        .padding({ bottom: 28 })
      }
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .layoutWeight(1)
    .width('100%')
  }

  // Current case name, the case list, and a new case, above the 维权 pages.
  @Builder
  private CaseBar() {
    Row({ space: 8 }) {
      Row({ space: 4 }) {
        Text(this.currentCaseTitle())
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.env.cx.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1)
        // Cases with content: the archive plus the current one unless it is empty.
        Text(this.caseState.history.length > 0 ?
          '▾ ' + (this.caseState.history.length + (this.hasCaseContent() ? 1 : 0)).toString() + ' 个案件' : '▾')
          .fontSize(11)
          .fontColor(this.env.cx.muted)
      }
      .layoutWeight(1)
      .height(34)
      .accessibilityText('我的案件')
      .onClick(() => {
        this.sheetKind = SHEET_CASES;
      })
      Text('＋ 新案件')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.hasCaseContent() && !this.caseBusy() ? this.env.cx.gold : this.env.cx.faint)
        .padding({ left: 11, right: 11, top: 6, bottom: 6 })
        .backgroundColor(this.env.cx.tint)
        .borderRadius(14)
        .enabled(this.hasCaseContent() && !this.caseBusy())
        .onClick(() => {
          this.startNewCase();
        })
    }
    .width('100%')
    .padding({ left: 18, right: 16, top: 8 })
  }

  // Computed here rather than passed in: a by-value builder argument would
  // keep showing the first value it was given.
  private rightsLabel(tab: number): string {
    if (tab === RIGHTS_DOSSIER) {
      return '卷宗 ' + this.caseState.progress.toString() + '%';
    }
    if (tab === RIGHTS_EVIDENCE) {
      return this.evidenceCount > 0 ? '证据 ' + this.evidenceCount.toString() : '证据';
    }
    return '梳理';
  }

  @Builder
  private RightsSegment(tab: number) {
    Text(this.rightsLabel(tab))
      .fontSize(13.5)
      .fontWeight(this.rightsTab === tab ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(this.rightsTab === tab ? this.env.cx.text : this.env.cx.muted)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(32)
      .borderRadius(10)
      .backgroundColor(this.rightsTab === tab ? this.env.cx.surface : Color.Transparent)
      .shadow(this.rightsTab === tab ? { radius: 6, color: this.env.cx.softShadow, offsetY: 1 } :
        { radius: 0, color: Color.Transparent, offsetY: 0 })
      .animation({ duration: this.env.reduceMotion ? 0 : 160, curve: Curve.EaseOut })
      .accessibilityText(this.rightsLabel(tab))
      .onClick(() => {
        this.showRights(tab);
      })
  }

  // 维权: the case conversation, the dossier it fills in, and the evidence
  // library, as three pages of one section.
  @Builder
  private RightsPage() {
    Column() {
      // Folded while reading the conversation; the header names the case.
      if (!(this.rightsTab === RIGHTS_CHAT && this.caseChat.reading)) {
        Column() {
          this.CaseBar()
          Row() {
            this.RightsSegment(RIGHTS_CHAT)
            this.RightsSegment(RIGHTS_DOSSIER)
            this.RightsSegment(RIGHTS_EVIDENCE)
          }
          .padding(3)
          .backgroundColor(this.env.cx.surface2)
          .borderRadius(12)
          .margin({ left: 16, right: 16, top: 4, bottom: 2 })
        }
        .width('100%')
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -24 })))
      }
      // 梳理 and 卷宗 stay alive while hidden, so each keeps its scroll
      // position and the header can follow it. 证据 is rebuilt each time: it
      // reads its starting query when it appears.
      Stack() {
        Column() {
          this.CaseChat()
        }
        .width('100%')
        .height('100%')
        .visibility(this.rightsTab === RIGHTS_CHAT ? Visibility.Visible : Visibility.None)
        Column() {
          DossierPage({
            caseState: this.caseState,
            reportRun: this.reportRun,
            floatActive: this.checklistFloatActive,
            floatBusy: this.checklistFloatBusy,
            floatError: this.checklistFloatError,
            caseFields: this.caseFields,
            fieldControllers: this.fieldControllers,
            detailsController: this.detailsController,
            scroller: this.dossierScroller,
            actions: this.dossierActions,
            chatActions: this.chatActions
          })
        }
        .width('100%')
        .height('100%')
        .visibility(this.rightsTab === RIGHTS_DOSSIER ? Visibility.Visible : Visibility.None)
        if (this.rightsTab === RIGHTS_EVIDENCE) {
          this.EvidencePane()
        }
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private MineCover() {
    MinePage({
      connectionState: this.connectionState,
      configBusy: this.configBusy,
      documentCount: this.knowledgeDocumentCount,
      searchableCount: this.knowledgeSearchableCount,
      quickCount: this.quickHistory.length,
      caseCount: this.caseState.history.length + (this.hasCaseContent() ? 1 : 0),
      progress: this.caseState.progress,
      evidenceCount: this.evidenceCount,
      contractCount: this.contractReportCount,
      busy: this.quick.sending || this.caseChat.sending || this.reportRun.sending,
      actions: this.mineActions
    })
  }

  @Builder
  private ContractPane() {
    ContractReview({
      cx: this.env.cx,
      isDark: this.env.isDark,
      lightLevel: this.env.lightLevel,
      reduceMotion: this.env.reduceMotion,
      mode: $contractMode,
      embedded: true,
      bottomInset: this.env.keyboardVisible ? 0 : TAB_BAR_CLEARANCE,
      dataVersion: this.localDataVersion,
      onReadingChange: (reading: boolean) => {
        this.setTabBarHidden(reading);
      },
      onCountChange: (count: number) => {
        this.contractReportCount = count;
      },
      baseUrl: this.env.config().baseUrl,
      modelName: this.env.config().model,
      apiKey: this.env.config().apiKey,
      modelLabel: this.env.usingBuiltin() ? '内置模型' : '你配置的模型',
      takeModelRequest: (): string => this.takeModelRequest(),
      returnModelRequest: () => {
        this.returnModelRequest();
      },
      defaultCity: this.caseState.location,
      onClose: () => {
      },
      onAsk: (title: string, body: string, question: string) => {
        this.askAboutContract(title, body, question);
      }
    })
  }

  @Builder
  private ErrorHint(message: string) {
    ErrorNotice({
      message: message,
      cx: this.env.cx,
      onSettings: () => {
        this.mineOpen = true;
      }
    })
  }

  @Builder
  private ScenarioCard(item: PromptSuggestion, index: number) {
    Column() {
      Row() {
        Column() {
          ChatIcon({ res: this.scenarioIcon(index), size: 17, color: this.scenarioGold(index) ? this.env.cx.gold : this.env.cx.brand })
        }
        .width(34)
        .height(34)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.scenarioGold(index) ?
          (this.env.isDark ? '#2A2416' : '#F6EAD2') : this.env.cx.tint)
        .borderRadius(10)
        Blank()
        Text('›')
          .fontSize(20)
          .fontColor(this.env.cx.faint)
      }
      .width('100%')
      Text(item.title)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.env.cx.text)
        .width('100%')
        .margin({ top: 10 })
      Text(item.description)
        .fontSize(10.5)
        .fontColor(this.env.cx.muted)
        .width('100%')
        .margin({ top: 3 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(13)
    .backgroundColor(this.env.cx.surface)
    .borderRadius(16)
    .border({ width: 1, color: this.env.cx.line })
    .shadow({ radius: 12, color: this.env.cx.cardShadow, offsetY: 4 })
    .onClick(() => {
      this.quick.input = item.prompt;
    })
  }

  @Builder
  private KnowledgePanel() {
    Row() {
      Column() {
        ChatIcon({ res: $r('app.media.ic_book'), size: 22, color: this.badgeIconColor() })
      }
      .width(46)
      .height(46)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.badgeBackground())
      .borderRadius(15)
      .shadow({ radius: 12, color: this.env.cx.cardShadow, offsetY: 4 })
      Column() {
        Text('本地法规库')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.env.cx.text)
        Text(this.knowledgeDocumentCount > 0 ?
          this.knowledgeDocumentCount.toString() + ' 份法规 · '
            + this.knowledgeSearchableCount.toString() + ' 份可检索' : this.knowledgeState)
          .fontSize(11)
          .fontColor(this.env.cx.brand)
          .margin({ top: 5 })
        Text('在手机上检索 · 不联网 · 回答附法条依据')
          .fontSize(9.5)
          .fontColor(this.env.cx.muted)
          .margin({ top: 5 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })
      Column() {
        ChatIcon({ res: $r('app.media.ic_check'), size: 15, color: this.env.cx.ok })
      }
      .width(30)
      .height(30)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.env.cx.okBg)
      .borderRadius(15)
    }
    .width('100%')
    .padding(15)
    .backgroundColor(this.env.cx.surface)
    .borderRadius(18)
    .border({ width: 1, color: this.env.cx.line })
    .shadow({ radius: 16, color: this.env.cx.cardShadow, offsetY: 5 })
  }

  @Builder
  private Composer() {
    Column() {
      Row({ space: 9 }) {
        Column() {
          ChatIcon({ res: $r('app.media.ic_consult'), size: 16, color: this.badgeIconColor() })
        }
        .width(30)
        .height(30)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.badgeBackground())
        .borderRadius(10)
        Text('先把情况告诉我')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.env.cx.text)
      }
      .width('100%')
      .margin({ bottom: 11 })
      if (this.quick.attachment.name.length > 0) {
        AttachmentRow({
          attachment: this.quick.attachment,
          cx: this.env.cx,
          onRemove: () => {
            this.quick.attachment = new FileAttachment();
          }
        })
      }
      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          ChatIcon({ res: $r('app.media.ic_plus'), size: 18, color: this.env.cx.gold })
        }
        .width(42)
        .height(42)
        .backgroundColor(this.env.cx.surface2)
        .borderWidth(1)
        .borderColor(this.env.cx.line)
        .enabled(!this.isAttachmentPicking && !this.quick.sending)
        .onClick(() => {
          this.openAttachmentSheet(false);
        })
        TextArea({
          text: this.quick.input,
          placeholder: '输入劳动法律问题…',
          controller: this.quickQuestionController
        })
          .layoutWeight(1)
          .constraintSize({ minHeight: 44, maxHeight: 96 })
          .fontSize(15)
          .fontColor(this.env.cx.text)
          .placeholderColor(this.env.cx.placeholder)
          .caretColor(this.env.cx.gold)
          .selectedBackgroundColor(this.env.cx.selection)
          .backgroundColor(Color.Transparent)
          .borderWidth(0)
          .padding({ left: 6, right: 6, top: 11, bottom: 11 })
          .onChange((value: string) => {
            this.quick.input = value;
          })
        // 本地法规检索 is always on, as in the pinned composer.
        Column() {
          ChatIcon({ res: $r('app.media.ic_book'), size: 14, color: this.env.cx.ok })
        }
        .margin({ bottom: 14 })
        .accessibilityText('本地法规检索已开启')
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          ChatIcon({ res: $r('app.media.ic_send'), size: 18, color: this.env.cx.onGold })
        }
        .width(42)
        .height(42)
        .backgroundColor(this.quick.canSend() ? this.env.cx.gold : this.env.cx.surface2)
        .enabled(this.quick.canSend())
        .onClick(() => {
          this.sendQuickQuestion();
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .padding({ left: 7, right: 7, top: 6, bottom: 6 })
      .backgroundColor(this.env.cx.surface2)
      .borderRadius(26)
      .border({ width: 1, color: this.env.cx.line })
      if (this.quick.attachmentError.length > 0) {
        AttachmentErrorRow({ message: this.quick.attachmentError, cx: this.env.cx })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(15)
    .backgroundColor(this.env.cx.surface)
    .borderRadius(22)
    .border({ width: 1, color: this.env.cx.line })
    .shadow({ radius: 18, color: this.env.cx.softShadow, offsetY: 6 })
  }

  // The title bar's button on the right: history. The scale on the left
  // (in the back button's place) goes back to the home.
  private quickMenu(): HdsNavigationMenuItemOptions[] {
    return [{
      content: {
        icon: $r('app.media.ic_menu'),
        label: '历史咨询',
        action: () => {
          this.openHistoryDrawer();
        }
      }
    }];
  }

  // The brand header at the top of the 普法 page, scrolling away with it; the
  // title bar floats over it, clear until the page scrolls.
  @Builder
  private QuickHero() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Image($r('app.media.ic_scale'))
        .width(150)
        .height(150)
        .fillColor(this.env.cx.headerText)
        .opacity(0.10)
        .margin({ top: 24, right: -14 })
      Column() {
        Text('劳动权益助手')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.env.cx.headerText)
        Text('懂法律，更懂你的难处')
          .fontSize(13)
          .fontColor(this.env.cx.headerSub)
          .margin({ top: 6 })
        Row()
          .width(34)
          .height(3)
          .backgroundColor(this.env.cx.glow)
          .borderRadius(2)
          .margin({ top: 12 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: 22, right: 22, top: 104, bottom: 22 })
    }
    // Full width: the conversation pads its content by 16 on each side.
    // Wider than its column, which centers it, so it reaches both edges.
    .width('calc(100% + 32vp)')
    .clip(true)
    .linearGradient({
      angle: 118,
      colors: [[this.env.cx.headerA, 0.0], [this.env.cx.headerB, 0.58], [this.env.cx.headerC, 1.0]]
    })
    .margin({ top: -14 })
  }

  @Builder
  private QuickPage() {
    HdsNavigation() {
      this.QuickConversation()
    }
    .titleBar({
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR
        },
        systemMaterialEffect: {
          materialType: Material.hdsType(),
          materialLevel: Material.hdsLevel(this.env.lightLevel, this.env.reduceMotion)
        },
        // Over the blue header the title is hidden (the header shows it large)
        // and the buttons are white; once the bar turns to glass both darken.
        originalStyle: {
          contentStyle: {
            menuStyle: { iconColor: this.env.cx.headerText, backgroundColor: '#33FFFFFF' },
            backIconStyle: { iconColor: this.env.cx.headerText, backgroundColor: '#33FFFFFF' }
          }
        },
        scrollEffectStyle: {
          contentStyle: {
            menuStyle: { iconColor: this.env.cx.brand },
            backIconStyle: { iconColor: this.env.cx.brand }
          }
        }
      },
      // No title: the scale mark on the left, history on the right.
      content: {
        title: { mainTitle: '' },
        backIcon: {
          icon: $r('app.media.ic_scale'),
          label: '回到普法首页',
          isEnabled: !this.quick.sending,
          action: () => {
            this.startNewConsultation();
          }
        },
        menu: { value: this.quickMenu() }
      },
      // Below the status bar, while the page's content runs up under it.
      avoidLayoutSafeArea: true
    })
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(false)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
    .mode(NavigationMode.Stack)
    // Stays while scrolling; only immersive reading (a tap) hides it.
    .hideTitleBar(this.quick.immersive, true)
    .bindToScrollable([this.quickScroller])
  }

  @Builder
  private QuickConversation() {
    Conversation({
      chat: this.quick,
      conversing: this.quick.messages.length > 0,
      placeholder: '继续追问…',
      sendingLabel: '正在检索本地法规并作答…',
      askLabel: '追问',
      tapToHide: true,
      readingRoom: this.readingRoom(false),
      picking: this.isAttachmentPicking,
      drawerSwipe: true,
      scrollId: QUICK_SCROLL_ID,
      turnId: QUICK_TURN_ID,
      scroller: this.quickScroller,
      controller: this.quickQuestionController,
      actions: this.chatActions,
      events: this.quickEvents
    }) {
      this.QuickHome()
    }
  }

  // The 普法 home, before the first question.
  @Builder
  private QuickHome() {
    this.QuickHero()
    if (this.quick.messages.length === 0) {
      this.Composer()
      // Right under the question it is about, where it is seen.
      if (this.quick.error.length > 0) {
        ErrorNotice({
          message: this.quick.error,
          cx: this.env.cx,
          onSettings: () => {
            this.mineOpen = true;
          },
          onLawsOnly: () => {
            this.answerFromLawsOnly();
          }
        })
      }
      Row() {
        Text('常见问题')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.env.cx.text)
        Blank()
        Text('点击后可继续补充')
          .fontSize(10)
          .fontColor(this.env.cx.muted)
      }
      .width('100%')
      .margin({ top: 2 })
      Grid() {
        ForEach(this.suggestions, (item: PromptSuggestion, index: number) => {
          GridItem() {
            this.ScenarioCard(item, index)
          }
        })
      }
      .columnsTemplate('1fr 1fr')
      .columnsGap(10)
      .rowsGap(10)
      .width('100%')
      this.KnowledgePanel()
      this.NoticeCard()
    }
  }

  // 维权 · 梳理: the case conversation, laid out like 普法 with the composer
  // pinned at the bottom.
  @Builder
  private CaseChat() {
    Conversation({
      chat: this.caseChat,
      forCase: true,
      placeholder: this.caseChat.messages.length > 0 ? '补充案情或追问…' : '从事情的起因开始说…',
      sendingLabel: '正在梳理案件信息…',
      askLabel: '补充案情',
      readingRoom: this.readingRoom(true),
      picking: this.isAttachmentPicking,
      scrollId: CASE_SCROLL_ID,
      turnId: CASE_TURN_ID,
      scroller: this.caseScroller,
      controller: this.caseMessageController,
      actions: this.chatActions,
      events: this.caseEvents
    }) {
      this.CaseLead()
    }
  }

  // Above the 维权 conversation: how complete the dossier is, and the
  // opening prompt.
  @Builder
  private CaseLead() {
    Row({ space: 13 }) {
      ProgressRing({ value: this.caseState.progress, size: 54, cx: this.env.cx })
      Column() {
        Text('卷宗完整度')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.env.cx.text)
          .width('100%')
        Text('对话中我会逐步提取六项要素，达 60% 可在「卷宗」页生成报告。')
          .fontSize(11)
          .lineHeight(16)
          .fontColor(this.env.cx.muted)
          .width('100%')
          .margin({ top: 4 })
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.caseFields, (field: CaseFieldInfo, index: number) => {
            this.CaseFieldChip(field, index)
          })
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding(15)
    .backgroundColor(this.env.cx.surface)
    .borderRadius(18)
    .border({ width: 1, color: this.env.cx.line })

    // Opening prompt, laid flat like the answers.
    Text('请从事情的起因开始描述。暂时不确定的信息也可以留空，我会继续追问。')
      .fontSize(15.5)
      .lineHeight(26)
      .fontColor(this.env.cx.text)
      .width('100%')
      .padding({ left: 2, right: 2 })
  }

  @Builder
  private CaseFieldChip(field: CaseFieldInfo, index: number) {
    Row({ space: 3 }) {
      Text(field.label)
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.fieldFilled(index) ? this.env.cx.goldDeep : this.env.cx.faint)
      Text(this.fieldFilled(index) ? '· 已填' : '· 待补')
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.fieldFilled(index) ? this.env.cx.goldDeep : this.env.cx.faint)
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor(this.fieldFilled(index) ?
      (this.env.isDark ? '#2A2416' : '#F6EAD2') : this.env.cx.surface2)
    .borderRadius(999)
    .margin({ right: 5, top: 6 })
    .animation({ duration: this.env.reduceMotion ? 0 : 180, curve: Curve.EaseOut })
  }

  @Builder
  private NavItem(res: Resource, label: string, target: AppSection) {
    Column({ space: 3 }) {
      ChatIcon({ res: res, size: this.currentSection === target ? 22 : 21, color: this.currentSection === target ? (this.env.isDark ? this.env.cx.gold : this.env.cx.goldDeep) : this.env.cx.muted })
      Text(label)
        .fontSize(11)
        .fontWeight(this.currentSection === target ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(this.currentSection === target ? (this.env.isDark ? this.env.cx.gold : this.env.cx.goldDeep) : this.env.cx.muted)
    }
    .justifyContent(FlexAlign.Center)
    .width('88%')
    .height(52)
    .backgroundColor(this.currentSection === target ? this.env.cx.navActiveBg : Color.Transparent)
    .borderRadius(26)
    .border(this.currentSection === target ?
      { width: 1, color: this.env.isDark ? '#66E0B45C' : '#66C0842A' } :
      { width: 0, color: Color.Transparent })
    .shadow(this.currentSection === target ?
      { radius: 16, color: this.env.cx.navShadow, offsetY: 4 } :
      { radius: 0, color: Color.Transparent, offsetY: 0 })
    .scale({ x: this.currentSection === target && !this.env.reduceMotion ? 1.04 : 1,
      y: this.currentSection === target && !this.env.reduceMotion ? 1.04 : 1 })
    .animation({ duration: this.env.reduceMotion ? 0 : 180, curve: Curve.EaseOut })
    .clickEffect(this.env.reduceMotion ? null : { level: ClickEffectLevel.LIGHT, scale: 0.96 })
  }

  build() {
    Stack() {
      Column() {
        // A contract report has its own compact header, so the page's is
        // dropped to give the text more room.
        // 普法 has its own immersive title bar (QuickPage); a contract report
        // has its own compact header.
        if (this.currentSection !== AppSection.QUICK && !(this.currentSection === AppSection.CONTRACT &&
          (this.contractMode === CONTRACT_MODE_REPORT || this.contractMode === CONTRACT_MODE_CLAUSE))) {
          this.Header()
        }
        HdsTabs({
          barPosition: BarPosition.End,
          index: this.currentSection,
          controller: this.hdsTabsController
        }) {
          TabContent() {
            this.QuickPage()
          }
          .tabBar(this.NavItem($r('app.media.ic_consult'), '普法', AppSection.QUICK))
          TabContent() {
            this.RightsPage()
          }
          .tabBar(this.NavItem($r('app.media.ic_scale'), '维权', AppSection.CASE))
          TabContent() {
            this.ContractPane()
          }
          .tabBar(this.NavItem($r('app.media.ic_shield'), '合同', AppSection.CONTRACT))
        }
        .barMode(BarMode.Fixed)
        .barHeight(this.env.keyboardVisible ? 0 : 64)
        .barOverlap(true)
        .barFloatingStyle(this.env.keyboardVisible ? this.keyboardHiddenStyle() : this.floatingStyle())
        .divider({ mode: DividerMode.NONE })
        .scrollable(false)
        .animationDuration(220)
        .onChange((index: number) => {
          this.currentSection = index as AppSection;
          this.endReading();
          this.setTabBarHidden(false);
          this.syncHeader();
        })
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .linearGradient({
        angle: 180,
        colors: [[this.env.cx.bgTop, 0.0], [this.env.cx.bgBottom, 1.0]]
      })
      .bindSheet(this.sheetKind !== 0, this.UnifiedSheet(), {
        height: this.sheetKind === 3 || this.sheetKind === 4 ? '72%' :
        this.sheetKind === SHEET_CITATION || this.sheetKind === SHEET_CHECKLIST || this.sheetKind === SHEET_CASES ?
          '64%' : 290,
        preferType: SheetType.BOTTOM,
        dragBar: true,
        showClose: false,
        maskColor: this.env.isDark ? '#88040B18' : '#66404A5A',
        systemMaterial: this.sheetMaterial(),
        onWillDismiss: () => {
          // Dismissing a citation opened from the report goes back to the report.
          this.sheetKind = this.sheetKind === SHEET_CITATION ? this.detailReturnSheet : 0;
          this.detailReturnSheet = 0;
        }
      })

      if (this.drawer.visible) {
        HistoryDrawer({
          drawer: this.drawer,
          sessions: $quickHistory,
          activeId: this.quick.messages.length > 0 ? this.quickSessionId : '',
          busy: this.quick.sending,
          actions: this.drawerActions
        })
      }
      // Carries the 我的 cover: one component cannot hold both it and the
      // sheets bound above.
      Column()
        .width(0)
        .height(0)
        .bindContentCover(this.mineOpen, this.MineCover(), {
          modalTransition: ModalTransition.DEFAULT,
          onWillDismiss: (action: DismissContentCoverAction) => {
            action.dismiss();
            this.mineOpen = false;
          }
        })
    }
    .width('100%')
    .height('100%')
  }
}
