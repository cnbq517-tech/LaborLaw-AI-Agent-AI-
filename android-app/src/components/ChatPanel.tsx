import React, { useEffect, useRef, useState } from 'react';
import { Loader2 } from 'lucide-react';
import type { ChatMessage, LawCitation } from '@harmony/models/AppModels';
import { CitationText } from '@harmony/services/CitationText';
import { ConversationText } from '@harmony/services/ConversationText';
import { HarmonyIcon } from './HarmonyIcon';

interface ChatPanelProps {
  messages: ChatMessage[];
  input: string;
  onInputChange: (val: string) => void;
  onSend: () => void;
  onStop: () => void;
  streaming: boolean;
  placeholder: string;
  headerSlot?: React.ReactNode;
  emptyState?: React.ReactNode;
  showPinnedComposer?: boolean;
  onScrollTopChange?: (scrollTop: number) => void;
  onOpenCitation: (citation: LawCitation, lead: string) => void;
  onOpenCitationsList?: (citations: LawCitation[]) => void;
  onToast: (msg: string) => void;
}

export const ChatPanel: React.FC<ChatPanelProps> = ({
  messages,
  input,
  onInputChange,
  onSend,
  onStop,
  streaming,
  placeholder,
  headerSlot,
  emptyState,
  showPinnedComposer = true,
  onScrollTopChange,
  onOpenCitation,
  onOpenCitationsList,
  onToast,
}) => {
  const scrollRef = useRef<HTMLDivElement | null>(null);
  const bottomRef = useRef<HTMLDivElement | null>(null);
  const [expandedReasoning, setExpandedReasoning] = useState<Record<number, boolean>>({});
  const [showJump, setShowJump] = useState(false);

  useEffect(() => {
    if (messages.length > 0) {
      bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
    }
  }, [messages.length]);

  const handleScroll = () => {
    const el = scrollRef.current;
    if (!el) return;
    onScrollTopChange?.(el.scrollTop);
    const distanceToBottom = el.scrollHeight - el.scrollTop - el.clientHeight;
    setShowJump(messages.length > 0 && distanceToBottom > 240);
  };

  const toggleReasoning = (idx: number) => {
    setExpandedReasoning((prev) => ({ ...prev, [idx]: !prev[idx] }));
  };

  const copyMessage = async (msg: ChatMessage, withCitations: boolean) => {
    const text = CitationText.copyText(msg.content, msg.citations, withCitations);
    const used = CitationText.usedCitationCount(msg.content, msg.citations.length);
    try {
      await navigator.clipboard.writeText(text);
      onToast(withCitations ? `已复制回答和 ${used} 条依据` : '已复制');
    } catch {
      onToast('复制失败，请长按文字手动复制');
    }
  };

  const canSend = input.trim().length > 0;

  return (
    <>
      <div
        ref={scrollRef}
        className={`scroll-area full-bleed ${showPinnedComposer ? 'has-composer' : ''}`}
        onScroll={handleScroll}
      >
        {headerSlot}

        {messages.length === 0 && emptyState ? (
          emptyState
        ) : (
          <div className="chat-list">
            {messages.map((msg, idx) => {
              const isUser = msg.role === 'user';
              const isLast = idx === messages.length - 1;
              const segments = isUser ? [] : CitationText.split(msg.content, msg.citations.length);
              const leads = isUser ? [] : CitationText.leads(msg.content, msg.citations.length);
              const isThinkingLive = isLast && streaming && !msg.content;
              const showReasoning = expandedReasoning[idx] ?? isThinkingLive;
              const usedCount = isUser
                ? 0
                : CitationText.usedCitationCount(msg.content, msg.citations.length);

              return (
                <div key={idx} className={`msg-row ${isUser ? 'user' : 'assistant'}`}>
                  {isUser ? (
                    <div className="user-bubble">{msg.content}</div>
                  ) : (
                    <>
                      {msg.reasoning &&
                        (showReasoning ? (
                          <div className="reasoning-card">
                            <div className="reasoning-card-head">
                              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
                                {isThinkingLive && (
                                  <Loader2
                                    size={13}
                                    style={{ animation: 'spin 1s linear infinite' }}
                                  />
                                )}
                                {isThinkingLive
                                  ? '正在思考…'
                                  : `已思考 ${ConversationText.thinkLabel(msg.thinkMs)}`}
                              </span>
                              <button
                                type="button"
                                className="reasoning-collapse-btn"
                                onClick={() => toggleReasoning(idx)}
                              >
                                收起
                              </button>
                            </div>
                            <div className="reasoning-text">{msg.reasoning}</div>
                            <div className="reasoning-disclaimer">
                              思考过程由模型生成，未经引用校验，可能包含推测，请以正式回答为准。
                            </div>
                          </div>
                        ) : (
                          <button
                            type="button"
                            className="reasoning-chip"
                            onClick={() => toggleReasoning(idx)}
                          >
                            已思考 {ConversationText.thinkLabel(msg.thinkMs)} ›
                          </button>
                        ))}

                      {msg.content ? (
                        <div className="assistant-flat-text">
                          {segments.map((seg, sIdx) =>
                            seg.citationIndex < 0 ? (
                              <React.Fragment key={sIdx}>{seg.text}</React.Fragment>
                            ) : (
                              <button
                                key={sIdx}
                                type="button"
                                className="citation-chip"
                                onClick={() =>
                                  onOpenCitation(
                                    msg.citations[seg.citationIndex],
                                    leads[seg.citationIndex] || ''
                                  )
                                }
                              >
                                {seg.citationIndex + 1}
                              </button>
                            )
                          )}
                        </div>
                      ) : (
                        isLast &&
                        streaming && (
                          <div
                            style={{
                              display: 'flex',
                              alignItems: 'center',
                              gap: 8,
                              color: 'var(--muted)',
                              fontSize: 13,
                              padding: '4px 2px',
                            }}
                          >
                            <Loader2
                              size={16}
                              color="var(--brand)"
                              style={{ animation: 'spin 1s linear infinite' }}
                            />
                            <span>正在检索本地法规并作答…</span>
                          </div>
                        )
                      )}

                      {msg.content && !(isLast && streaming) && (
                        <div className="answer-actions">
                          <button
                            type="button"
                            className="answer-pill-btn gold-soft"
                            onClick={() => copyMessage(msg, false)}
                          >
                            <HarmonyIcon name="copy" size={13} color="var(--gold)" />
                            复制
                          </button>
                          {usedCount > 0 && (
                            <button
                              type="button"
                              className="answer-pill-btn tint-muted"
                              onClick={() => copyMessage(msg, true)}
                            >
                              <HarmonyIcon name="book" size={13} color="var(--muted)" />
                              复制含依据
                            </button>
                          )}
                          {msg.citations.length > 0 && (
                            <button
                              type="button"
                              className="answer-pill-btn tint-brand"
                              onClick={() =>
                                onOpenCitationsList
                                  ? onOpenCitationsList(msg.citations)
                                  : onOpenCitation(msg.citations[0], leads[0] || '')
                              }
                            >
                              <HarmonyIcon name="book" size={13} color="var(--brand)" />
                              依据 {msg.citations.length} 条
                            </button>
                          )}
                        </div>
                      )}
                    </>
                  )}
                </div>
              );
            })}
            <div ref={bottomRef} />
          </div>
        )}
      </div>

      {showJump && (
        <button
          type="button"
          className="jump-latest-btn"
          aria-label="回到最新"
          onClick={() => bottomRef.current?.scrollIntoView({ behavior: 'smooth' })}
        >
          <HarmonyIcon name="arrow_down" size={18} color="var(--text)" />
        </button>
      )}

      {showPinnedComposer && (
        <div className="pinned-composer-wrap">
          <div className="pinned-composer-card">
            <div className="pinned-composer-row">
              <button
                type="button"
                className="pinned-circle-btn"
                aria-label="添加附件"
                onClick={() => onToast('阶段 2 将支持拍照与附件识别')}
              >
                <HarmonyIcon name="plus" size={17} color="var(--gold)" />
              </button>
              <textarea
                className="composer-input"
                rows={1}
                value={input}
                placeholder={placeholder}
                onChange={(e) => onInputChange(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault();
                    if (!streaming && canSend) onSend();
                  }
                }}
              />
              <div style={{ marginBottom: 10, display: 'flex', alignItems: 'center' }}>
                <HarmonyIcon name="book" size={14} color="var(--ok)" />
              </div>
              {streaming ? (
                <button
                  type="button"
                  className="pinned-send-btn stop"
                  onClick={onStop}
                  aria-label="停止生成"
                >
                  <HarmonyIcon name="stop" size={17} color="var(--on-gold)" />
                </button>
              ) : (
                <button
                  type="button"
                  className={`pinned-send-btn ${canSend ? 'ready' : ''}`}
                  disabled={!canSend}
                  onClick={onSend}
                  aria-label="发送"
                >
                  <HarmonyIcon
                    name="send"
                    size={17}
                    color={canSend ? 'var(--on-gold)' : 'var(--faint)'}
                  />
                </button>
              )}
            </div>
            <div className="pinned-composer-footnote">
              AI 内容仅供参考，重要决定请核对最新法规或咨询专业人士
            </div>
          </div>
        </div>
      )}
    </>
  );
};
