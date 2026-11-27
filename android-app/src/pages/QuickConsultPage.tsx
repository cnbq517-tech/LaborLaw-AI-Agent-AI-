import React, { useRef, useState } from 'react';
import { Loader2, RefreshCw } from 'lucide-react';
import { ChatMessage, ChatRole, type LawCitation } from '@harmony/models/AppModels';
import { MAX_QUICK_SESSIONS, QuickSession } from '@harmony/models/ChatState';
import { ConversationPrompts } from '@harmony/services/ConversationPrompts';
import { ConversationText } from '@harmony/services/ConversationText';
import { KnowledgeEngine } from '@harmony/services/KnowledgeEngine';
import { TASK_ANSWER } from '@harmony/services/ModelTuning';
import { ChatPanel } from '../components/ChatPanel';
import { HarmonyIcon, type HarmonyIconName } from '../components/HarmonyIcon';
import { HistoryDrawer } from '../components/HistoryDrawer';
import { streamChatCompletion, type StreamHandle } from '../services/aiClient';
import { knowledgeClient, type KnowledgeStateSnapshot } from '../services/knowledgeClient';
import { toApiConfig, type AppSettings } from '../services/storage';

interface QuickConsultPageProps {
  settings: AppSettings;
  kbState: KnowledgeStateSnapshot;
  onRetryKb: () => void;
  messages: ChatMessage[];
  sessionId: string;
  history: QuickSession[];
  onUpdateSession: (messages: ChatMessage[], sessionId: string, history: QuickSession[]) => void;
  onOpenCitation: (citation: LawCitation, lead: string) => void;
  onOpenCitationsList: (citations: LawCitation[]) => void;
  onGoMine: () => void;
  onToast: (msg: string) => void;
}

const SCENARIOS: Array<{
  title: string;
  desc: string;
  prompt: string;
  icon: HarmonyIconName;
  gold: boolean;
}> = [
  {
    title: '工资拖欠',
    desc: '追索工资与补偿',
    prompt: '公司拖欠工资，我应该如何维权？',
    icon: 'coin',
    gold: false,
  },
  {
    title: '被公司辞退',
    desc: '判断解除程序风险',
    prompt: '公司突然辞退我，可以要求哪些补偿？',
    icon: 'flame',
    gold: true,
  },
  {
    title: '没有劳动合同',
    desc: '双倍工资与举证',
    prompt: '入职后一直没有签劳动合同怎么办？',
    icon: 'doc',
    gold: false,
  },
  {
    title: '加班费争议',
    desc: '计算方式与证据',
    prompt: '怎样证明加班并主张加班费？',
    icon: 'clock',
    gold: true,
  },
];

export const QuickConsultPage: React.FC<QuickConsultPageProps> = ({
  settings,
  kbState,
  onRetryKb,
  messages,
  sessionId,
  history,
  onUpdateSession,
  onOpenCitation,
  onOpenCitationsList,
  onGoMine,
  onToast,
}) => {
  const [input, setInput] = useState('');
  const [streaming, setStreaming] = useState(false);
  const [streamHandle, setStreamHandle] = useState<StreamHandle | null>(null);
  const [showHistory, setShowHistory] = useState(false);
  const [scrolled, setScrolled] = useState(false);
  const homeInputRef = useRef<HTMLTextAreaElement | null>(null);
  const edgeSwipeStartX = useRef<number>(-1);
  const edgeSwipeStartY = useRef<number>(0);

  const upsertHistory = (msgs: ChatMessage[], sid: string): QuickSession[] => {
    if (msgs.length === 0) return history;
    const id = sid || `q_${Date.now().toString(36)}`;
    const title = ConversationText.sessionTitle(msgs);
    const updated = new QuickSession(id, title, Date.now(), msgs);
    return [updated, ...history.filter((s) => s.id !== id)].slice(0, MAX_QUICK_SESSIONS);
  };

  const sendPrompt = async (rawText: string) => {
    const question = rawText.trim();
    if (!question || streaming) return;

    const sid = sessionId || `q_${Date.now().toString(36)}`;
    const userMsg = new ChatMessage(ChatRole.USER, question);
    const assistantMsg = new ChatMessage(ChatRole.ASSISTANT, '');
    const baseMsgs = [...messages, userMsg];
    let currentMsgs = [...baseMsgs, assistantMsg];

    setInput('');
    setStreaming(true);
    onUpdateSession(currentMsgs, sid, upsertHistory(currentMsgs, sid));

    const kbResult = await knowledgeClient.search(question, 6);
    assistantMsg.citations = kbResult.citations;

    const apiConfig = toApiConfig(settings);
    if (!apiConfig.apiKey.trim()) {
      const fallbackText =
        kbResult.citations.length > 0
          ? ConversationText.lawsOnlyAnswer(kbResult.citations) +
            '\n\n提示：尚未配置大模型 API Key，以上为本地法规库直接检索结果。前往「我的」配置 API 后可生成完整分析。'
          : '尚未配置大模型 API Key，且本地法规库未检索到直接匹配的条文。请前往「我的」配置 API 地址、模型与 Key。';
      assistantMsg.content = KnowledgeEngine.validateAnswer(fallbackText, kbResult.citations);
      currentMsgs = [...baseMsgs, assistantMsg];
      onUpdateSession(currentMsgs, sid, upsertHistory(currentMsgs, sid));
      setStreaming(false);
      return;
    }

    const systemPrompt = ConversationPrompts.quickSystem(kbResult);
    const requestMessages = ConversationPrompts.messages(systemPrompt, baseMsgs);

    const handle = streamChatCompletion(
      apiConfig,
      requestMessages,
      {
        onDelta: (answer, reasoning) => {
          const live = new ChatMessage(ChatRole.ASSISTANT, answer, kbResult.citations);
          live.reasoning = reasoning;
          onUpdateSession([...baseMsgs, live], sid, history);
        },
      },
      TASK_ANSWER
    );
    setStreamHandle(handle);

    try {
      const out = await handle.promise;
      const finalContent = out.content.trim()
        ? KnowledgeEngine.validateAnswer(out.content, kbResult.citations)
        : out.aborted
          ? '已停止生成。'
          : '模型未返回内容，请稍后重试。';
      const finalMsg = new ChatMessage(ChatRole.ASSISTANT, finalContent, kbResult.citations);
      finalMsg.reasoning = out.reasoning;
      finalMsg.thinkMs = out.thinkMs;
      const doneMsgs = [...baseMsgs, finalMsg];
      onUpdateSession(doneMsgs, sid, upsertHistory(doneMsgs, sid));
    } catch (err) {
      const errMsg = err instanceof Error ? err.message : String(err);
      const fallback =
        kbResult.citations.length > 0
          ? `请求失败（${errMsg}）。\n\n以下为本地法规库检索到的相关条文：\n${ConversationText.lawsOnlyAnswer(
              kbResult.citations
            )}`
          : `请求失败：${errMsg}`;
      const failMsg = new ChatMessage(ChatRole.ASSISTANT, fallback, kbResult.citations);
      const doneMsgs = [...baseMsgs, failMsg];
      onUpdateSession(doneMsgs, sid, upsertHistory(doneMsgs, sid));
      onToast(errMsg);
    } finally {
      setStreaming(false);
      setStreamHandle(null);
    }
  };

  const handleReturnHome = () => {
    if (streaming) return;
    onUpdateSession([], '', history);
    setScrolled(false);
    setShowHistory(false);
  };

  const handleLoadSession = (session: QuickSession) => {
    if (streaming) streamHandle?.abort();
    onUpdateSession(session.messages, session.id, history);
    setShowHistory(false);
  };

  const handleDeleteSession = (id: string) => {
    const nextHistory = history.filter((s) => s.id !== id);
    const nextMsgs = id === sessionId ? [] : messages;
    const nextId = id === sessionId ? '' : sessionId;
    onUpdateSession(nextMsgs, nextId, nextHistory);
  };

  const canSendHome = input.trim().length > 0;

  const heroNode = (
    <div className="quick-hero">
      <HarmonyIcon name="scale" size={150} className="quick-hero-watermark" />
      <h1 className="quick-hero-title">劳动法律 AI 智能体</h1>
      <p className="quick-hero-sub">懂法律，更懂你的难处</p>
      <div className="quick-hero-bar" />
    </div>
  );

  return (
    <div
      className="page-body"
      onTouchStart={(e) => {
        const t = e.touches[0];
        // Avoid Android's system back gesture zone (0..36px on the left edge):
        // allow right-swipe anywhere in the main content area to open the drawer.
        const hasSelection = (window.getSelection()?.toString().length ?? 0) > 0;
        if (!showHistory && !hasSelection && t.clientX > 36) {
          edgeSwipeStartX.current = t.clientX;
          edgeSwipeStartY.current = t.clientY;
        } else {
          edgeSwipeStartX.current = -1;
        }
      }}
      onTouchEnd={(e) => {
        if (edgeSwipeStartX.current < 0) return;
        const t = e.changedTouches[0];
        const dx = t.clientX - edgeSwipeStartX.current;
        const dy = Math.abs(t.clientY - edgeSwipeStartY.current);
        edgeSwipeStartX.current = -1;
        if (dx > 64 && dx > dy * 1.6) {
          setShowHistory(true);
        }
      }}
    >
      {/* 全局浮动顶部栏：顶部透明白字，滚动超 16px 变毛玻璃 + 蓝色图标 */}
      <div className={`top-nav-bar ${scrolled ? 'scrolled' : ''}`}>
        <button
          type="button"
          className="top-nav-circle-btn"
          aria-label="回到普法首页"
          onClick={handleReturnHome}
        >
          <HarmonyIcon name="scale" size={20} />
        </button>
        <button
          type="button"
          className="top-nav-circle-btn"
          aria-label="历史咨询"
          onClick={() => setShowHistory(true)}
        >
          <HarmonyIcon name="menu" size={20} />
        </button>
      </div>

      <ChatPanel
        messages={messages}
        input={input}
        onInputChange={setInput}
        onSend={() => sendPrompt(input)}
        onStop={() => streamHandle?.abort()}
        streaming={streaming}
        placeholder="继续追问…"
        headerSlot={heroNode}
        showPinnedComposer={messages.length > 0}
        onScrollTopChange={(top) => setScrolled(top > 16)}
        onOpenCitation={onOpenCitation}
        onOpenCitationsList={onOpenCitationsList}
        onToast={onToast}
        emptyState={
          <div className="quick-content-col">
            {/* 1. 先把情况告诉我（首页输入卡） */}
            <div className="home-composer-card">
              <div className="home-composer-head">
                <div className="home-composer-icon-badge">
                  <HarmonyIcon name="consult" size={16} color="var(--brand)" />
                </div>
                <h2 className="home-composer-title">先把情况告诉我</h2>
              </div>

              <div className="home-composer-pill">
                <button
                  type="button"
                  className="home-plus-btn"
                  aria-label="添加附件"
                  onClick={() => onToast('阶段 2 将支持拍照与附件识别')}
                >
                  <HarmonyIcon name="plus" size={18} color="var(--gold)" />
                </button>
                <textarea
                  ref={homeInputRef}
                  className="composer-input"
                  rows={1}
                  value={input}
                  placeholder="输入劳动法律问题…"
                  onChange={(e) => setInput(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' && !e.shiftKey) {
                      e.preventDefault();
                      if (canSendHome) sendPrompt(input);
                    }
                  }}
                />
                <div style={{ marginBottom: 13, display: 'flex', alignItems: 'center' }}>
                  <HarmonyIcon name="book" size={14} color="var(--ok)" />
                </div>
                <button
                  type="button"
                  className={`home-send-btn ${canSendHome ? 'ready' : ''}`}
                  disabled={!canSendHome}
                  aria-label="发送"
                  onClick={() => sendPrompt(input)}
                >
                  <HarmonyIcon
                    name="send"
                    size={18}
                    color={canSendHome ? 'var(--on-gold)' : 'var(--faint)'}
                  />
                </button>
              </div>
            </div>

            {!settings.apiKey.trim() && (
              <div
                className="card"
                style={{
                  borderColor: 'var(--gold)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  gap: 10,
                }}
              >
                <div style={{ fontSize: 12.5 }}>
                  <strong>尚未配置模型 API Key</strong>
                  <div style={{ color: 'var(--muted)', fontSize: 11.5, marginTop: 2 }}>
                    当前可离线检索法规；配置 API 后解锁流式 AI 问答。
                  </div>
                </div>
                <button
                  type="button"
                  className="btn-gold"
                  style={{ flexShrink: 0, padding: '7px 12px', fontSize: 12.5 }}
                  onClick={onGoMine}
                >
                  去配置
                </button>
              </div>
            )}

            {/* 2. 常见问题 2×2 卡片 */}
            <div className="quick-section-row">
              <h3 className="quick-section-title">常见问题</h3>
              <span className="quick-section-hint">点击后可继续补充</span>
            </div>

            <div className="scenario-grid">
              {SCENARIOS.map((item) => (
                <button
                  key={item.title}
                  type="button"
                  className="scenario-card"
                  onClick={() => {
                    setInput(item.prompt);
                    homeInputRef.current?.focus();
                  }}
                >
                  <div className="scenario-card-top">
                    <div className={`scenario-icon-box ${item.gold ? 'gold' : 'blue'}`}>
                      <HarmonyIcon name={item.icon} size={17} />
                    </div>
                    <span className="scenario-chevron">›</span>
                  </div>
                  <div className="scenario-card-title">{item.title}</div>
                  <p className="scenario-card-desc">{item.desc}</p>
                </button>
              ))}
            </div>

            {/* 3. 本地法规库面板（含后台加载进度与异常重试兜底） */}
            <div className="kb-panel-card">
              <div className="kb-panel-icon">
                <HarmonyIcon name="book" size={22} color="var(--brand)" />
              </div>
              <div className="kb-panel-body">
                <div className="kb-panel-title">本地法规库</div>
                {kbState.status === 'ready' && (
                  <div className="kb-panel-count">
                    {kbState.documentCount} 份法规 · {kbState.searchableDocumentCount} 份可检索
                  </div>
                )}
                {kbState.status === 'loading' && (
                  <>
                    <div className="kb-panel-count">
                      {kbState.phase === 'parsing'
                        ? '正在后台解析 52MB 索引…'
                        : `正在后台加载本地法规库（${kbState.percent}%）…`}
                    </div>
                    <div className="kb-progress-track">
                      <div className="kb-progress-fill" style={{ width: `${kbState.percent}%` }} />
                    </div>
                  </>
                )}
                {kbState.status === 'error' && (
                  <div className="kb-panel-count error">
                    加载失败：{kbState.error || '请点击右侧重试'}
                  </div>
                )}
                {kbState.status === 'idle' && (
                  <div className="kb-panel-count">准备初始化本地法规库…</div>
                )}
                <div className="kb-panel-sub">在手机上检索 · 不联网 · 回答附法条依据</div>
              </div>
              {kbState.status === 'ready' && (
                <div className="kb-panel-check">
                  <HarmonyIcon name="check" size={15} color="var(--ok)" />
                </div>
              )}
              {kbState.status === 'loading' && (
                <div className="kb-panel-check" style={{ background: 'var(--tint)', color: 'var(--brand)' }}>
                  <Loader2 size={15} style={{ animation: 'spin 1s linear infinite' }} />
                </div>
              )}
              {kbState.status === 'error' && (
                <button
                  type="button"
                  className="btn-secondary"
                  style={{ padding: '6px 10px', fontSize: 12 }}
                  onClick={onRetryKb}
                >
                  <RefreshCw size={13} />
                  重试
                </button>
              )}
            </div>

            {/* 4. 底部免责与时效提示 */}
            <div className="notice-footer">
              <span className="notice-tag">提示</span>
              <span className="notice-text">
                AI 内容仅供参考，重要决定请核对最新法规或咨询专业人士。本地法规库可能存在地方口径差异或待更新条文。
              </span>
            </div>
          </div>
        }
      />

      <HistoryDrawer
        open={showHistory}
        sessions={history}
        activeSessionId={sessionId}
        onClose={() => setShowHistory(false)}
        onNewChat={handleReturnHome}
        onSelectSession={handleLoadSession}
        onDeleteSession={handleDeleteSession}
      />
    </div>
  );
};
