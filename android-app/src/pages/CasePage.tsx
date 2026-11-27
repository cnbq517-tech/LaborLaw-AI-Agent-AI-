import React, { useEffect, useState } from 'react';
import { X } from 'lucide-react';
import { ChatMessage, ChatRole, type LawCitation } from '@harmony/models/AppModels';
import { CaseRecord, DossierState } from '@harmony/models/ChatState';
import { CaseArchive } from '@harmony/services/CaseArchive';
import { CitationText } from '@harmony/services/CitationText';
import { ConversationPrompts } from '@harmony/services/ConversationPrompts';
import {
  FIELD_COMPANY,
  FIELD_LOCATION,
  FIELD_SALARY,
  FIELD_TIMELINE,
} from '@harmony/services/EvidenceExtractor';
import { KnowledgeEngine } from '@harmony/services/KnowledgeEngine';
import { TASK_ANSWER } from '@harmony/services/ModelTuning';
import { ChatPanel } from '../components/ChatPanel';
import { EvidenceLibrary } from '../components/EvidenceLibrary';
import { HarmonyIcon } from '../components/HarmonyIcon';
import { streamChatCompletion, type StreamHandle } from '../services/aiClient';
import type { LocalEvidence } from '../services/evidenceStore';
import { knowledgeClient, type KnowledgeStateSnapshot } from '../services/knowledgeClient';
import { toApiConfig, type AppSettings } from '../services/storage';

interface CasePageProps {
  settings: AppSettings;
  kbState: KnowledgeStateSnapshot;
  onRetryKb: () => void;
  caseId: string;
  messages: ChatMessage[];
  dossier: DossierState;
  archive: CaseRecord[];
  evidence: LocalEvidence[];
  focusEvidenceSeq: number;
  onImportEvidenceFiles: (files: FileList) => void;
  onRetryEvidenceOcr: (item: LocalEvidence) => void;
  onUpdateEvidenceCategory: (id: string, category: string) => void;
  onDeleteEvidence: (id: string) => void;
  onUpdateCase: (
    caseId: string,
    messages: ChatMessage[],
    dossier: DossierState,
    archive: CaseRecord[]
  ) => void;
  onOpenCitation: (citation: LawCitation, lead: string) => void;
  onOpenCitationsList: (citations: LawCitation[]) => void;
  onToast: (msg: string) => void;
}

const DOSSIER_FIELDS: Array<{
  key: keyof DossierState;
  chipLabel: string;
  label: string;
  placeholder: string;
  multiline?: boolean;
}> = [
  { key: 'location', chipLabel: '案件发生地', label: '案件发生地', placeholder: '例如：广东省深圳市南山区' },
  { key: 'company', chipLabel: '单位名称', label: '用人单位', placeholder: '例如：某某科技有限公司' },
  { key: 'salary', chipLabel: '平均月薪', label: '平均月薪', placeholder: '例如：税前 12,000 元（含绩效）' },
  { key: 'timeline', chipLabel: '时间节点', label: '关键时间节点', placeholder: '例如：2024-03 入职，2026-10 辞退' },
  { key: 'request', chipLabel: '核心诉求', label: '核心诉求', placeholder: '例如：拖欠工资、违法解除赔偿金 2N' },
  {
    key: 'details',
    chipLabel: '详细经过',
    label: '详细经过',
    placeholder: '简述入职、合同签订、社保、考勤、沟通或辞退经过…',
    multiline: true,
  },
];

const ProgressRing: React.FC<{ percent: number }> = ({ percent }) => {
  const size = 54;
  const stroke = 4.5;
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const dash = c - (Math.min(100, Math.max(0, percent)) / 100) * c;
  return (
    <div style={{ position: 'relative', width: size, height: size, flexShrink: 0 }}>
      <svg width={size} height={size} style={{ transform: 'rotate(-90deg)' }}>
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          stroke="var(--surface-2)"
          strokeWidth={stroke}
        />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          stroke={percent >= 60 ? 'var(--gold)' : 'var(--brand)'}
          strokeWidth={stroke}
          strokeLinecap="round"
          strokeDasharray={c}
          strokeDashoffset={dash}
        />
      </svg>
      <div
        style={{
          position: 'absolute',
          inset: 0,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontSize: 13.5,
          fontWeight: 700,
          color: 'var(--text)',
        }}
      >
        {percent}%
      </div>
    </div>
  );
};

export const CasePage: React.FC<CasePageProps> = ({
  settings,
  caseId,
  messages,
  dossier,
  archive,
  evidence,
  focusEvidenceSeq,
  onImportEvidenceFiles,
  onRetryEvidenceOcr,
  onUpdateEvidenceCategory,
  onDeleteEvidence,
  onUpdateCase,
  onOpenCitation,
  onOpenCitationsList,
  onToast,
}) => {
  const [subTab, setSubTab] = useState<'chat' | 'dossier' | 'evidence'>('chat');
  const [input, setInput] = useState('');
  const [streaming, setStreaming] = useState(false);
  const [streamHandle, setStreamHandle] = useState<StreamHandle | null>(null);
  const [generatingReport, setGeneratingReport] = useState(false);
  const [showArchive, setShowArchive] = useState(false);

  useEffect(() => {
    if (focusEvidenceSeq > 0) {
      setSubTab('evidence');
    }
  }, [focusEvidenceSeq]);

  const filledFlags = DOSSIER_FIELDS.map((_, i) => CaseArchive.fieldFilled(dossier, i));
  const filledCount = filledFlags.filter(Boolean).length;
  const progress = Math.round((filledCount / 6) * 100);

  const commit = (nextId: string, nextMsgs: ChatMessage[], nextDossier: DossierState) => {
    const id = nextId || `case_${Date.now().toString(36)}`;
    const nextArchive = CaseArchive.archive(archive, id, nextMsgs, nextDossier);
    onUpdateCase(id, nextMsgs, nextDossier, nextArchive);
  };

  const handleSend = async () => {
    const text = input.trim();
    if (!text || streaming) return;

    const id = caseId || `case_${Date.now().toString(36)}`;
    const userMsg = new ChatMessage(ChatRole.USER, text);
    const baseMsgs = [...messages, userMsg];
    const placeholder = new ChatMessage(ChatRole.ASSISTANT, '');

    setInput('');
    setStreaming(true);
    commit(id, [...baseMsgs, placeholder], dossier);

    const searchQuery = [text, dossier.location, dossier.request].filter(Boolean).join(' ');
    const kbResult = await knowledgeClient.search(searchQuery, 6);

    const apiConfig = toApiConfig(settings);
    if (!apiConfig.apiKey.trim()) {
      const msg = new ChatMessage(
        ChatRole.ASSISTANT,
        '请先在「我的」中配置大模型 API Key，再进行多轮案情梳理。你也可以先切换到「卷宗」手动填写六项案件要素。',
        kbResult.citations
      );
      commit(id, [...baseMsgs, msg], dossier);
      setStreaming(false);
      return;
    }

    const dossierNote = CaseArchive.hasDossierInput(dossier)
      ? '\n\n当前卷宗已记录信息：\n' + ConversationPrompts.dossierSummary(dossier)
      : '';
    const sys = ConversationPrompts.caseSystem(kbResult) + dossierNote;
    const reqMsgs = ConversationPrompts.messages(sys, baseMsgs);

    const handle = streamChatCompletion(
      apiConfig,
      reqMsgs,
      {
        onDelta: (answer, reasoning) => {
          const live = new ChatMessage(ChatRole.ASSISTANT, answer, kbResult.citations);
          live.reasoning = reasoning;
          onUpdateCase(id, [...baseMsgs, live], dossier, archive);
        },
      },
      TASK_ANSWER
    );
    setStreamHandle(handle);

    try {
      const out = await handle.promise;
      const finalMsg = new ChatMessage(
        ChatRole.ASSISTANT,
        out.content.trim()
          ? KnowledgeEngine.validateAnswer(out.content, kbResult.citations)
          : out.aborted
            ? '已停止生成。'
            : '模型未返回内容，请重试。',
        kbResult.citations
      );
      finalMsg.reasoning = out.reasoning;
      finalMsg.thinkMs = out.thinkMs;
      commit(id, [...baseMsgs, finalMsg], dossier);
    } catch (err) {
      const errMsg = err instanceof Error ? err.message : String(err);
      const failMsg = new ChatMessage(ChatRole.ASSISTANT, `请求失败：${errMsg}`, kbResult.citations);
      commit(id, [...baseMsgs, failMsg], dossier);
      onToast(errMsg);
    } finally {
      setStreaming(false);
      setStreamHandle(null);
    }
  };

  const handleFieldChange = (key: keyof DossierState, value: string) => {
    const next = Object.assign(new DossierState(), dossier, { [key]: value });
    commit(caseId, messages, next);
  };

  const handleGenerateReport = async () => {
    if (generatingReport) return;
    if (!CaseArchive.hasDossierInput(dossier) && messages.length === 0) {
      onToast('请先填写至少一项卷宗信息或进行案情梳理');
      return;
    }
    const apiConfig = toApiConfig(settings);
    if (!apiConfig.apiKey.trim()) {
      onToast('请先在「我的」中配置 API Key');
      return;
    }

    setGeneratingReport(true);
    const summary =
      ConversationPrompts.dossierSummary(dossier) + ConversationPrompts.evidenceSummary(evidence);
    const kbResult = await knowledgeClient.search(summary + ' ' + dossier.request, 8);
    const sys = ConversationPrompts.reportSystem(kbResult);
    const promptMsg = new ChatMessage(
      ChatRole.USER,
      '请根据以下案件卷宗与梳理记录，生成一份结构化的维权分析报告：\n\n' + summary
    );
    const reqMsgs = ConversationPrompts.messages(sys, [...messages.slice(-6), promptMsg]);

    const handle = streamChatCompletion(
      apiConfig,
      reqMsgs,
      {
        onDelta: (answer) => {
          const liveDossier = Object.assign(new DossierState(), dossier, {
            report: answer,
            reportCitations: kbResult.citations,
          });
          onUpdateCase(caseId, messages, liveDossier, archive);
        },
      },
      TASK_ANSWER
    );

    try {
      const out = await handle.promise;
      const validated = KnowledgeEngine.validateAnswer(out.content, kbResult.citations);
      const nextDossier = Object.assign(new DossierState(), dossier, {
        report: validated,
        reportCitations: kbResult.citations,
      });
      commit(caseId, messages, nextDossier);
      onToast('维权分析报告已生成');
    } catch (err) {
      onToast(err instanceof Error ? err.message : '报告生成失败');
    } finally {
      setGeneratingReport(false);
    }
  };

  const handleNewCase = () => {
    if (streaming) streamHandle?.abort();
    onUpdateCase('', [], new DossierState(), archive);
    setShowArchive(false);
    onToast('已新建空白案件');
  };

  const handleLoadCase = (rec: CaseRecord) => {
    if (streaming) streamHandle?.abort();
    onUpdateCase(rec.id, rec.messages, rec.dossier, archive);
    setShowArchive(false);
  };

  const reportSegments = dossier.report
    ? CitationText.split(dossier.report, dossier.reportCitations.length)
    : [];
  const reportLeads = dossier.report
    ? CitationText.leads(dossier.report, dossier.reportCitations.length)
    : [];

  const caseLeadNode = (
    <div style={{ padding: '14px 16px 0', display: 'flex', flexDirection: 'column', gap: 14 }}>
      <div className="case-lead-card">
        <ProgressRing percent={progress} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 14.5, fontWeight: 700, color: 'var(--text)' }}>卷宗完整度</div>
          <div style={{ fontSize: 11.5, color: 'var(--muted)', marginTop: 4, lineHeight: 1.45 }}>
            对话中我会逐步提取六项要素，达 60% 可在「卷宗」页生成报告。
          </div>
          <div className="case-chip-wrap">
            {DOSSIER_FIELDS.map((f, i) => (
              <span
                key={f.key}
                className={`case-field-chip ${filledFlags[i] ? 'filled' : ''}`}
                onClick={() => setSubTab('dossier')}
              >
                {f.chipLabel} · {filledFlags[i] ? '已填' : '待补'}
              </span>
            ))}
          </div>
        </div>
      </div>

      <div className="assistant-flat-text">
        请从事情的起因开始描述。暂时不确定的信息也可以留空，我会继续追问。
      </div>
    </div>
  );

  return (
    <div className="page-body">
      {/* 1:1 鸿蒙维权蓝金头图 + 内嵌三段式切换 */}
      <header className="brand-header">
        <HarmonyIcon name="scale" size={96} className="brand-header-watermark" />
        <div className="brand-header-row">
          <div className="brand-header-left">
            <div className="brand-header-circle">
              <HarmonyIcon name="scale" size={20} />
            </div>
            <h1 className="brand-title">{CaseArchive.title(messages, dossier)}</h1>
          </div>
          <div className="header-circle-actions">
            <button
              type="button"
              className="header-icon-circle"
              aria-label="案件档案"
              onClick={() => setShowArchive(true)}
            >
              <HarmonyIcon name="folder" size={18} />
            </button>
            <button
              type="button"
              className="header-icon-circle"
              aria-label="新案件"
              onClick={handleNewCase}
            >
              <HarmonyIcon name="plus" size={19} />
            </button>
          </div>
        </div>

        <div className="header-seg-track">
          <button
            type="button"
            className={`header-seg-btn ${subTab === 'chat' ? 'active' : ''}`}
            onClick={() => setSubTab('chat')}
          >
            梳理
          </button>
          <button
            type="button"
            className={`header-seg-btn ${subTab === 'dossier' ? 'active' : ''}`}
            onClick={() => setSubTab('dossier')}
          >
            卷宗 {progress}%
          </button>
          <button
            type="button"
            className={`header-seg-btn ${subTab === 'evidence' ? 'active' : ''}`}
            onClick={() => setSubTab('evidence')}
          >
            证据{evidence.length > 0 ? ` ${evidence.length}` : ''}
          </button>
        </div>
      </header>

      {subTab === 'chat' && (
        <ChatPanel
          messages={messages}
          input={input}
          onInputChange={setInput}
          onSend={handleSend}
          onStop={() => streamHandle?.abort()}
          streaming={streaming}
          placeholder={messages.length > 0 ? '补充案情或追问…' : '从事情的起因开始说…'}
          headerSlot={caseLeadNode}
          onOpenCitation={onOpenCitation}
          onOpenCitationsList={onOpenCitationsList}
          onToast={onToast}
        />
      )}

      {subTab === 'dossier' && (
        <div className="scroll-area">
          <div className="card">
            <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 14 }}>
              <ProgressRing percent={progress} />
              <div>
                <div style={{ fontSize: 15, fontWeight: 700 }}>案件卷宗（{filledCount}/6 项）</div>
                <div style={{ fontSize: 12, color: 'var(--muted)', marginTop: 2 }}>
                  完善核心要素后可生成结构化维权分析与行动清单
                </div>
              </div>
            </div>

            {DOSSIER_FIELDS.map((field) => (
              <div key={field.key} className="field-group">
                <label className="field-label">{field.label}</label>
                {field.multiline ? (
                  <textarea
                    className="text-area"
                    value={String(dossier[field.key] ?? '')}
                    placeholder={field.placeholder}
                    onChange={(e) => handleFieldChange(field.key, e.target.value)}
                  />
                ) : (
                  <input
                    type="text"
                    className="text-input"
                    value={String(dossier[field.key] ?? '')}
                    placeholder={field.placeholder}
                    onChange={(e) => handleFieldChange(field.key, e.target.value)}
                  />
                )}
              </div>
            ))}

            <button
              type="button"
              className="btn-primary"
              style={{ width: '100%' }}
              disabled={generatingReport}
              onClick={handleGenerateReport}
            >
              {generatingReport ? '正在结合本地法规生成维权报告…' : '生成维权分析报告'}
            </button>
          </div>

          {dossier.report && (
            <div className="card">
              <div style={{ fontWeight: 700, fontSize: 15, marginBottom: 10 }}>维权分析报告</div>
              <div className="assistant-flat-text" style={{ fontSize: 15, lineHeight: '24px' }}>
                {reportSegments.map((seg, idx) =>
                  seg.citationIndex < 0 ? (
                    <React.Fragment key={idx}>{seg.text}</React.Fragment>
                  ) : (
                    <button
                      key={idx}
                      type="button"
                      className="citation-chip"
                      onClick={() =>
                        onOpenCitation(
                          dossier.reportCitations[seg.citationIndex],
                          reportLeads[seg.citationIndex] || ''
                        )
                      }
                    >
                      {seg.citationIndex + 1}
                    </button>
                  )
                )}
              </div>
              <div className="answer-actions" style={{ marginTop: 12 }}>
                <button
                  type="button"
                  className="answer-pill-btn gold-soft"
                  onClick={async () => {
                    const text = CitationText.copyText(
                      dossier.report,
                      dossier.reportCitations,
                      false
                    );
                    await navigator.clipboard.writeText(text).catch(() => {});
                    onToast('已复制');
                  }}
                >
                  <HarmonyIcon name="copy" size={13} color="var(--gold)" />
                  复制
                </button>
                <button
                  type="button"
                  className="answer-pill-btn tint-muted"
                  onClick={async () => {
                    const text = CitationText.copyText(
                      dossier.report,
                      dossier.reportCitations,
                      true
                    );
                    await navigator.clipboard.writeText(text).catch(() => {});
                    onToast('已复制报告及参考依据');
                  }}
                >
                  <HarmonyIcon name="book" size={13} color="var(--muted)" />
                  复制含依据
                </button>
              </div>
            </div>
          )}
        </div>
      )}

      {subTab === 'evidence' && (
        <EvidenceLibrary
          items={evidence}
          onImportFiles={onImportEvidenceFiles}
          onRetryOcr={onRetryEvidenceOcr}
          onUpdateCategory={onUpdateEvidenceCategory}
          onDelete={onDeleteEvidence}
          onApplyDossierField={(fieldIndex, value, label) => {
            const keyMap: Record<number, keyof DossierState> = {
              [FIELD_LOCATION]: 'location',
              [FIELD_COMPANY]: 'company',
              [FIELD_SALARY]: 'salary',
              [FIELD_TIMELINE]: 'timeline',
            };
            const key = keyMap[fieldIndex];
            if (key) {
              handleFieldChange(key, value);
              onToast(`已将「${value}」填入卷宗 · ${label}`);
            }
          }}
          onToast={onToast}
        />
      )}

      {showArchive && (
        <div className="sheet-backdrop" onClick={() => setShowArchive(false)}>
          <div className="sheet-panel" onClick={(e) => e.stopPropagation()}>
            <div className="sheet-header">
              <strong>归档案件（{archive.length}）</strong>
              <button
                type="button"
                className="btn-secondary"
                style={{ padding: '6px 10px' }}
                onClick={() => setShowArchive(false)}
              >
                <X size={16} />
              </button>
            </div>
            <div className="sheet-body">
              {archive.length === 0 ? (
                <p style={{ color: 'var(--muted)', textAlign: 'center', padding: '24px 0' }}>
                  暂无已保存的案件
                </p>
              ) : (
                archive.map((rec) => (
                  <button
                    key={rec.id}
                    type="button"
                    className="card"
                    style={{
                      width: '100%',
                      textAlign: 'left',
                      marginBottom: 8,
                      cursor: 'pointer',
                    }}
                    onClick={() => handleLoadCase(rec)}
                  >
                    <div style={{ fontWeight: 600 }}>{rec.title}</div>
                    <div style={{ fontSize: 12, color: 'var(--muted)', marginTop: 4 }}>
                      梳理消息 {rec.messages.length} 条
                      {rec.dossier.report ? ' · 已生成报告' : ''}
                    </div>
                  </button>
                ))
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
