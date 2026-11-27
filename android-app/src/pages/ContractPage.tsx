import React, { useMemo, useRef, useState } from 'react';
import { ChevronLeft, ChevronRight, Lock, SlidersHorizontal, Sparkles, X } from 'lucide-react';
import type { LawCitation } from '@harmony/models/AppModels';
import { ContractAi, ReviewLaw } from '@harmony/contract/ContractAi';
import { ContractDocument } from '@harmony/contract/ContractDocument';
import { ContractLaws } from '@harmony/contract/ContractLaws';
import { ContractPrivacy } from '@harmony/contract/ContractPrivacy';
import { ContractRules } from '@harmony/contract/ContractRules';
import { ContractStructure } from '@harmony/contract/ContractStructure';
import {
  FACT_NO,
  FACT_UNKNOWN,
  FACT_YES,
  FactSheet,
  Finding,
  SEVERITY_HIGH,
  SEVERITY_MEDIUM,
  SEVERITY_REDLINE,
  StructureAudit,
} from '@harmony/contract/ContractTypes';
import {
  SAMPLE_CONTRACT_CITY,
  SAMPLE_CONTRACT_NAME,
  SAMPLE_CONTRACT_TEXT,
} from '@harmony/contract/SampleContract';
import { CAT_CONTRACT } from '@harmony/services/EvidenceExtractor';
import { HarmonyIcon } from '../components/HarmonyIcon';
import { completeStructuredJson } from '../services/aiClient';
import { parseContractFile } from '../services/docxParser';
import type { LocalEvidence } from '../services/evidenceStore';
import { knowledgeClient, type KnowledgeStateSnapshot } from '../services/knowledgeClient';
import {
  toApiConfig,
  type AppSettings,
  type SavedContractReport,
} from '../services/storage';

interface ContractPageProps {
  settings: AppSettings;
  kbState: KnowledgeStateSnapshot;
  onRetryKb: () => void;
  history: SavedContractReport[];
  evidence: LocalEvidence[];
  onUpdateHistory: (next: SavedContractReport[]) => void;
  onAskAboutContract: (title: string, question: string) => void;
  onOpenCitation: (citation: LawCitation, lead: string) => void;
  onToast: (msg: string) => void;
}

function formatDate(ts: number): string {
  const d = new Date(ts);
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${mm}/${dd}/${d.getFullYear()}`;
}

export const ContractPage: React.FC<ContractPageProps> = ({
  settings,
  history,
  evidence,
  onUpdateHistory,
  onAskAboutContract,
  onOpenCitation,
  onToast,
}) => {
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const [mode, setMode] = useState<'home' | 'report'>('home');
  const [parsingFile, setParsingFile] = useState(false);
  const [showEvidencePicker, setShowEvidencePicker] = useState(false);
  const [reportId, setReportId] = useState('');
  const [contractName, setContractName] = useState('');
  const [rawText, setRawText] = useState('');
  const [city, setCity] = useState('');
  const [position, setPosition] = useState('');
  const [confidential, setConfidential] = useState(FACT_UNKNOWN);
  const [signed, setSigned] = useState(FACT_UNKNOWN);

  const [audit, setAudit] = useState<StructureAudit | null>(null);
  const [findings, setFindings] = useState<Finding[]>([]);
  const [ruleFindings, setRuleFindings] = useState<Finding[]>([]);
  const [aiReviewed, setAiReviewed] = useState(false);
  const [viewMode, setViewMode] = useState<'findings' | 'document'>('findings');
  const [severityFilter, setSeverityFilter] = useState<string>('ALL');
  const [showFactsSheet, setShowFactsSheet] = useState(false);
  const [activeFinding, setActiveFinding] = useState<Finding | null>(null);
  const [aiRunning, setAiRunning] = useState(false);
  const [aiProgress, setAiProgress] = useState('');
  const [followUp, setFollowUp] = useState('');

  const normalizedText = useMemo(
    () => (rawText ? ContractStructure.normalize(rawText) : ''),
    [rawText]
  );

  const maskPreview = useMemo(
    () => (normalizedText ? ContractPrivacy.mask(normalizedText) : null),
    [normalizedText]
  );

  const anchorLabel = (anchorId: string): string => {
    const a = audit?.anchors.find((item) => item.anchorId === anchorId);
    return a?.rawNo ? a.rawNo : '全文';
  };

  const upsertHistory = (
    id: string,
    name: string,
    text: string,
    c: string,
    pos: string,
    conf: string,
    sig: string,
    list: Finding[],
    isAi: boolean
  ) => {
    const rec: SavedContractReport = {
      id,
      name,
      text,
      city: c,
      position: pos,
      confidential: conf,
      signed: sig,
      createdAt: Date.now(),
      redlineCount: list.filter((f) => f.severity === SEVERITY_REDLINE).length,
      totalCount: list.length,
      aiReviewed: isAi,
    };
    onUpdateHistory([rec, ...history.filter((h) => h.id !== id)].slice(0, 20));
  };

  const runLocalAudit = (
    name: string,
    text: string,
    opts?: { id?: string; city?: string; position?: string; confidential?: string; signed?: string }
  ) => {
    const useCity = opts?.city ?? city;
    const usePos = opts?.position ?? position;
    const useConf = opts?.confidential ?? confidential;
    const useSig = opts?.signed ?? signed;
    const id = opts?.id || `c_${Date.now().toString(36)}`;

    const norm = ContractStructure.normalize(text);
    const structure = ContractStructure.audit(norm, false);
    const facts = new FactSheet();
    facts.city = useCity.trim();
    facts.position = usePos.trim();
    facts.confidential = useConf;
    facts.signed = useSig;

    const ruleRes = ContractRules.run(structure.anchors, norm, facts);
    setReportId(id);
    setContractName(name);
    setRawText(text);
    setCity(useCity);
    setPosition(usePos);
    setConfidential(useConf);
    setSigned(useSig);
    setAudit(structure);
    setRuleFindings(ruleRes.findings);
    setFindings(ruleRes.findings);
    setAiReviewed(false);
    setSeverityFilter('ALL');
    setViewMode('findings');
    setMode('report');
    upsertHistory(id, name, text, useCity, usePos, useConf, useSig, ruleRes.findings, false);
  };

  const handleLoadSample = () => {
    runLocalAudit(SAMPLE_CONTRACT_NAME, SAMPLE_CONTRACT_TEXT, {
      city: SAMPLE_CONTRACT_CITY,
      position: '',
      confidential: FACT_UNKNOWN,
      signed: FACT_UNKNOWN,
    });
  };

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    setParsingFile(true);
    if (file.name.toLowerCase().endsWith('.pdf')) {
      onToast('正在手机端侧逐页识别 PDF，请稍候…');
    }
    try {
      const parsed = await parseContractFile(file);
      runLocalAudit(parsed.name, parsed.text, { city: '' });
      if (parsed.pageNote) {
        onToast(`PDF 识别完成（${parsed.pageNote}）`);
      }
    } catch (err) {
      onToast(err instanceof Error ? err.message : '读取合同文件失败');
    } finally {
      setParsingFile(false);
    }
  };

  const contractPhotos = useMemo(
    () =>
      evidence.filter(
        (item) => (item.rowsText || item.text).trim().length >= 10
      ),
    [evidence]
  );

  const contractCategoryCount = useMemo(
    () => contractPhotos.filter((i) => i.category === CAT_CONTRACT).length,
    [contractPhotos]
  );

  const handleRunAiReview = async () => {
    if (!audit || !normalizedText || aiRunning) return;
    const apiConfig = toApiConfig(settings);
    if (!apiConfig.apiKey.trim()) {
      onToast('请先在「我的」中配置 API Key，再启用脱敏 AI 深度审查');
      return;
    }

    setAiRunning(true);
    const facts = new FactSheet();
    facts.city = city.trim();
    facts.position = position.trim();
    facts.confidential = confidential;
    facts.signed = signed;

    const batches = ContractAi.batches(audit.anchors);
    const aiFindings: Finding[] = [];

    try {
      for (let i = 0; i < batches.length; i++) {
        setAiProgress(`脱敏 AI 审查第 ${i + 1}/${batches.length} 批条款…`);
        const batch = batches[i];
        const kb = await knowledgeClient.search(ContractAi.lawQuery(batch), 5);
        const laws = kb.citations.map(
          (c, idx) => new ReviewLaw(`K${idx + 1}`, c.title, c.article, c.excerpt)
        );
        const prompt = ContractAi.reviewPrompt(facts, laws, batch, ruleFindings, '');
        const out = await completeStructuredJson(apiConfig, ContractAi.systemPrompt(), prompt);
        const validIds = batch.map((a) => a.anchorId);
        const parsed = ContractAi.parse(out.content, validIds, laws);
        if (parsed.ok) {
          aiFindings.push(...parsed.findings);
        }
      }

      const merged = ContractAi.merge(ruleFindings, aiFindings);
      setFindings(merged);
      setAiReviewed(true);
      upsertHistory(
        reportId,
        contractName,
        rawText,
        city,
        position,
        confidential,
        signed,
        merged,
        true
      );
      onToast(`AI 脱敏审查完成：共 ${merged.length} 处问题`);
    } catch (err) {
      onToast(err instanceof Error ? err.message : 'AI 深度审查失败');
    } finally {
      setAiRunning(false);
      setAiProgress('');
    }
  };

  const handleOpenLawRef = async (refLabel: string) => {
    const loc = ContractLaws.resolve(refLabel);
    if (!loc) {
      onToast(`未在本地法规映射中找到 ${refLabel}`);
      return;
    }
    const key = `${loc.title}\u0000${loc.article}\u0000${loc.label}`;
    const list = await knowledgeClient.articles([key]);
    if (list.length > 0) {
      onOpenCitation(list[0], '');
    } else {
      const search = await knowledgeClient.search(refLabel, 1);
      if (search.citations.length > 0) {
        onOpenCitation(search.citations[0], '');
      } else {
        onToast(`本地库未定位到 ${refLabel}`);
      }
    }
  };

  const redlineCount = findings.filter((f) => f.severity === SEVERITY_REDLINE).length;
  const highCount = findings.filter((f) => f.severity === SEVERITY_HIGH).length;
  const medCount = findings.filter((f) => f.severity === SEVERITY_MEDIUM).length;

  const filteredFindings = useMemo(() => {
    if (severityFilter === 'ALL') return findings;
    return findings.filter((f) => f.severity === severityFilter);
  }, [findings, severityFilter]);

  const pendingFacts = useMemo(() => {
    const set = new Set<string>();
    findings.forEach((f) => f.pendingFacts.forEach((p) => set.add(p)));
    return Array.from(set);
  }, [findings]);

  const docLines = useMemo(() => {
    if (!audit || !normalizedText) return [];
    return ContractDocument.lines(normalizedText, audit.anchors, findings);
  }, [audit, normalizedText, findings]);

  if (mode === 'home') {
    return (
      <div className="page-body">
        <header className="brand-header">
          <HarmonyIcon name="scale" size={96} className="brand-header-watermark" />
          <div className="brand-header-row">
            <div className="brand-header-left">
              <div className="brand-header-circle">
                <HarmonyIcon name="scale" size={20} />
              </div>
              <div>
                <h1 className="brand-title">合同体检</h1>
                <p className="brand-subtitle">规则审查在手机上完成 · 报告仅保存在本机</p>
              </div>
            </div>
          </div>
        </header>

        <div className="scroll-area">
          <input
            ref={fileInputRef}
            type="file"
            accept=".txt,.docx,.pdf,text/plain,application/pdf,application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            style={{ display: 'none' }}
            onChange={handleFileChange}
          />

          <button
            type="button"
            className="contract-entry-card"
            disabled={parsingFile}
            onClick={() => fileInputRef.current?.click()}
          >
            <div className="contract-entry-icon">
              <HarmonyIcon name="doc" size={20} />
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 16, fontWeight: 700, color: 'var(--text)' }}>
                {parsingFile ? '正在端侧识别合同文件…' : '选择合同文件'}
              </div>
              <div style={{ fontSize: 12.5, color: 'var(--muted)', marginTop: 3 }}>
                支持 DOCX、PDF（含扫描件）、TXT
              </div>
            </div>
            <ChevronRight size={18} color="var(--gold)" />
          </button>

          <button
            type="button"
            className="contract-entry-card"
            onClick={() => {
              if (contractPhotos.length === 0) {
                onToast('证据库中暂无已识别文字的照片，请先在「维权 → 证据」导入');
                return;
              }
              setShowEvidencePicker(true);
            }}
          >
            <div className="contract-entry-icon">
              <HarmonyIcon name="photo" size={20} />
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 16, fontWeight: 700, color: 'var(--text)' }}>
                用证据库里的合同照片
              </div>
              <div style={{ fontSize: 12.5, color: 'var(--muted)', marginTop: 3 }}>
                {contractCategoryCount > 0
                  ? `${contractCategoryCount} 张已识别为「合同」的照片`
                  : contractPhotos.length > 0
                    ? `共 ${contractPhotos.length} 张已识别文字的证据照片可选`
                    : '在「维权 → 证据」导入合同照片后即可直接体检'}
              </div>
            </div>
            <ChevronRight size={18} color="var(--gold)" />
          </button>

          <button type="button" className="contract-entry-card" onClick={handleLoadSample}>
            <div className="contract-entry-icon">
              <HarmonyIcon name="shield" size={20} />
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 16, fontWeight: 700, color: 'var(--text)' }}>
                用示例合同试试
              </div>
              <div style={{ fontSize: 12.5, color: 'var(--muted)', marginTop: 3 }}>
                一份有典型问题的虚构合同，看看审查结果
              </div>
            </div>
            <ChevronRight size={18} color="var(--gold)" />
          </button>

          <p
            style={{
              fontSize: 12.5,
              color: 'var(--muted)',
              lineHeight: 1.6,
              margin: '14px 2px 18px',
            }}
          >
            规则审查完全在手机上进行。开启 AI 深度审查时，只发送条款文字，姓名、身份证号、手机号、住址等会先替换成占位符。
          </p>

          {history.length > 0 && (
            <>
              <div style={{ fontSize: 16, fontWeight: 700, marginBottom: 10 }}>审查记录</div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                {history.map((rec) => (
                  <div
                    key={rec.id}
                    className="card"
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'space-between',
                      gap: 10,
                      marginTop: 0,
                    }}
                  >
                    <button
                      type="button"
                      style={{
                        flex: 1,
                        textAlign: 'left',
                        border: 'none',
                        background: 'transparent',
                        color: 'var(--text)',
                        padding: 0,
                        cursor: 'pointer',
                      }}
                      onClick={() =>
                        runLocalAudit(rec.name, rec.text, {
                          id: rec.id,
                          city: rec.city,
                          position: rec.position,
                          confidential: rec.confidential,
                          signed: rec.signed,
                        })
                      }
                    >
                      <div style={{ fontSize: 15, fontWeight: 700 }}>{rec.name}</div>
                      <div style={{ fontSize: 12, color: 'var(--muted)', marginTop: 4 }}>
                        {formatDate(rec.createdAt)} · 红线 {rec.redlineCount} · 共 {rec.totalCount}{' '}
                        处 · {rec.aiReviewed ? 'AI 审查完成' : '仅本地规则'}
                      </div>
                    </button>
                    <button
                      type="button"
                      style={{
                        border: 'none',
                        background: 'transparent',
                        color: 'var(--faint)',
                        fontSize: 13,
                        cursor: 'pointer',
                        padding: '6px 4px',
                      }}
                      onClick={() => onUpdateHistory(history.filter((h) => h.id !== rec.id))}
                    >
                      删除
                    </button>
                  </div>
                ))}
              </div>
            </>
          )}
        </div>

        {showEvidencePicker && (
          <div className="sheet-backdrop" onClick={() => setShowEvidencePicker(false)}>
            <div className="sheet-panel" onClick={(e) => e.stopPropagation()}>
              <div className="sheet-header">
                <strong>选择证据库照片进行合同体检</strong>
                <button
                  type="button"
                  className="btn-secondary"
                  style={{ padding: '6px 10px' }}
                  onClick={() => setShowEvidencePicker(false)}
                >
                  <X size={16} />
                </button>
              </div>
              <div className="sheet-body">
                {contractPhotos.map((item) => (
                  <button
                    key={item.id}
                    type="button"
                    className="card"
                    style={{
                      width: '100%',
                      display: 'flex',
                      alignItems: 'center',
                      gap: 10,
                      textAlign: 'left',
                      marginBottom: 8,
                      cursor: 'pointer',
                    }}
                    onClick={() => {
                      setShowEvidencePicker(false);
                      runLocalAudit(item.title, item.rowsText || item.text, { city: '' });
                    }}
                  >
                    <img
                      src={item.dataUrl}
                      alt={item.title}
                      style={{ width: 48, height: 48, borderRadius: 10, objectFit: 'cover' }}
                    />
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ fontWeight: 700, fontSize: 14 }}>{item.title}</div>
                      <div style={{ fontSize: 12, color: 'var(--muted)', marginTop: 2 }}>
                        {item.category || '其他'} · 已识别 {(item.rowsText || item.text).length} 字
                      </div>
                    </div>
                  </button>
                ))}
              </div>
            </div>
          </div>
        )}
      </div>
    );
  }

  return (
    <div className="page-body">
      {/* 1:1 鸿蒙合同报告头图 + 筛选胶囊 + 原文/清单切换 */}
      <header className="brand-header">
        <HarmonyIcon name="scale" size={96} className="brand-header-watermark" />
        <div className="brand-header-row">
          <div className="brand-header-left">
            <button
              type="button"
              className="brand-header-circle"
              aria-label="返回"
              onClick={() => setMode('home')}
            >
              <ChevronLeft size={21} />
            </button>
            <div style={{ minWidth: 0 }}>
              <h1
                className="brand-title"
                style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}
              >
                {contractName}
              </h1>
              <p className="brand-subtitle">{findings.length} 处问题</p>
            </div>
          </div>
          <button
            type="button"
            className="header-icon-circle"
            aria-label="补充事实与 AI 审查"
            onClick={() => setShowFactsSheet(true)}
          >
            <SlidersHorizontal size={17} />
          </button>
        </div>

        <div className="contract-filter-bar">
          <div className="contract-filter-pills">
            {redlineCount > 0 && (
              <button
                type="button"
                className={`filter-pill red ${severityFilter === SEVERITY_REDLINE ? 'active' : ''}`}
                onClick={() =>
                  setSeverityFilter(
                    severityFilter === SEVERITY_REDLINE ? 'ALL' : SEVERITY_REDLINE
                  )
                }
              >
                红线 {redlineCount}
              </button>
            )}
            {highCount > 0 && (
              <button
                type="button"
                className={`filter-pill high ${severityFilter === SEVERITY_HIGH ? 'active' : ''}`}
                onClick={() =>
                  setSeverityFilter(severityFilter === SEVERITY_HIGH ? 'ALL' : SEVERITY_HIGH)
                }
              >
                高 {highCount}
              </button>
            )}
            {medCount > 0 && (
              <button
                type="button"
                className={`filter-pill med ${severityFilter === SEVERITY_MEDIUM ? 'active' : ''}`}
                onClick={() =>
                  setSeverityFilter(severityFilter === SEVERITY_MEDIUM ? 'ALL' : SEVERITY_MEDIUM)
                }
              >
                中 {medCount}
              </button>
            )}
          </div>

          <div className="contract-view-switch">
            <button
              type="button"
              className={`contract-view-btn ${viewMode === 'document' ? 'active' : ''}`}
              onClick={() => setViewMode('document')}
            >
              原文
            </button>
            <button
              type="button"
              className={`contract-view-btn ${viewMode === 'findings' ? 'active' : ''}`}
              onClick={() => setViewMode('findings')}
            >
              清单
            </button>
          </div>
        </div>
      </header>

      <div className="scroll-area" style={{ paddingBottom: 'calc(182px + env(safe-area-inset-bottom, 0px))' }}>
        {viewMode === 'findings' ? (
          <>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              <strong style={{ fontSize: 17 }}>发现 {findings.length} 处问题</strong>
              <span
                style={{
                  fontSize: 11.5,
                  fontWeight: 600,
                  padding: '3px 9px',
                  borderRadius: 999,
                  background: 'var(--ok-bg)',
                  color: 'var(--ok)',
                }}
              >
                {aiReviewed ? 'AI 审查完成' : '仅本地规则'}
              </span>
            </div>

            {findings.length > 0 && (
              <div className="severity-meter">
                {redlineCount > 0 && (
                  <div
                    className="severity-meter-seg"
                    style={{ flex: redlineCount, background: 'var(--danger)' }}
                  />
                )}
                {highCount > 0 && (
                  <div
                    className="severity-meter-seg"
                    style={{ flex: highCount, background: 'var(--gold)' }}
                  />
                )}
                {medCount > 0 && (
                  <div
                    className="severity-meter-seg"
                    style={{ flex: medCount, background: 'var(--gold-deep)' }}
                  />
                )}
              </div>
            )}

            <div style={{ fontSize: 12.5, color: 'var(--muted)', marginBottom: 12 }}>
              红线 {redlineCount} · 高 {highCount} · 中 {medCount}
              <button
                type="button"
                style={{
                  marginLeft: 10,
                  border: 'none',
                  background: 'transparent',
                  color: 'var(--brand)',
                  fontSize: 12.5,
                  fontWeight: 600,
                  cursor: 'pointer',
                  padding: 0,
                }}
                onClick={() => setShowFactsSheet(true)}
              >
                {aiRunning ? aiProgress || 'AI 审查中…' : '补充事实 / 脱敏 AI 复核 ›'}
              </button>
            </div>

            {pendingFacts.length > 0 && (
              <div
                style={{
                  background: 'var(--chip-bg)',
                  borderRadius: 12,
                  padding: '10px 12px',
                  fontSize: 12.5,
                  color: 'var(--gold-deep)',
                  marginBottom: 12,
                  lineHeight: 1.5,
                }}
              >
                部分结论取决于：{pendingFacts.join('、')}，已标为待确认
              </div>
            )}

            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              {filteredFindings.map((f, idx) => (
                <div
                  key={f.findingId + idx}
                  style={{
                    paddingBottom: 12,
                    borderBottom: '1px solid var(--line)',
                  }}
                >
                  <div
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'space-between',
                      gap: 8,
                      marginBottom: 6,
                    }}
                  >
                    <strong style={{ fontSize: 15.5 }}>
                      {anchorLabel(f.anchorId)} · {f.topic}
                    </strong>
                    <div style={{ display: 'flex', gap: 5, flexShrink: 0 }}>
                      <span className={`sev-badge sev-${f.severity}`}>{f.severity}</span>
                      <span className="sev-badge sev-提示">{f.nature}</span>
                    </div>
                  </div>
                  <p style={{ margin: '0 0 6px', fontSize: 14, lineHeight: 1.65 }}>{f.reason}</p>
                  {f.suggestion && (
                    <p style={{ margin: '0 0 8px', fontSize: 13, color: 'var(--muted)' }}>
                      建议：{f.suggestion}
                    </p>
                  )}
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: 6 }}>
                    <span style={{ fontSize: 12, color: 'var(--faint)' }}>
                      {f.ruleId === 'AI' ? 'AI 复核' : `规则 ${f.ruleId}`}
                    </span>
                    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
                      {f.lawRefs.map((ref) => (
                        <button
                          key={ref}
                          type="button"
                          className="answer-pill-btn tint-brand"
                          style={{ height: 26, fontSize: 11.5 }}
                          onClick={() => handleOpenLawRef(ref)}
                        >
                          <HarmonyIcon name="book" size={12} color="var(--brand)" />
                          {ref}
                        </button>
                      ))}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </>
        ) : (
          <div style={{ fontSize: 15, lineHeight: 1.85 }}>
            {pendingFacts.length > 0 && (
              <div
                style={{
                  background: 'var(--chip-bg)',
                  borderRadius: 10,
                  padding: '8px 11px',
                  fontSize: 12,
                  color: 'var(--gold-deep)',
                  marginBottom: 12,
                }}
              >
                部分结论取决于：{pendingFacts.join('、')}
              </div>
            )}
            {docLines.map((line) => (
              <div
                key={line.index}
                style={{
                  marginBottom: 10,
                  fontWeight: line.heading ? 700 : 400,
                }}
              >
                {line.segments.map((seg, sIdx) =>
                  seg.finding < 0 ? (
                    <React.Fragment key={sIdx}>{seg.text}</React.Fragment>
                  ) : (
                    <span
                      key={sIdx}
                      className={`doc-hl-${seg.severity}`}
                      onClick={() => setActiveFinding(findings[seg.finding] ?? null)}
                    >
                      {seg.text}
                    </span>
                  )
                )}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* 底部悬浮「就这份合同继续问…」毛玻璃输入胶囊 */}
      <div className="pinned-composer-wrap">
        <div className="pinned-composer-card">
          <div className="pinned-composer-row">
            <textarea
              className="composer-input"
              rows={1}
              style={{ paddingLeft: 10 }}
              value={followUp}
              placeholder="就这份合同继续问…"
              onChange={(e) => setFollowUp(e.target.value)}
            />
            <button
              type="button"
              className={`pinned-send-btn ${followUp.trim() ? 'ready' : ''}`}
              disabled={!followUp.trim()}
              aria-label="发送至维权"
              onClick={() => {
                const q = followUp.trim();
                if (!q) return;
                setFollowUp('');
                onAskAboutContract(contractName, q);
              }}
            >
              <HarmonyIcon
                name="send"
                size={17}
                color={followUp.trim() ? 'var(--on-gold)' : 'var(--faint)'}
              />
            </button>
          </div>
          <div className="pinned-composer-footnote">发送后在「维权」中继续 · AI 内容仅供参考</div>
        </div>
      </div>

      {/* 补充事实 & 脱敏 AI 深度复核弹窗 */}
      {showFactsSheet && (
        <div className="sheet-backdrop" onClick={() => setShowFactsSheet(false)}>
          <div className="sheet-panel" onClick={(e) => e.stopPropagation()}>
            <div className="sheet-header">
              <strong>补充事实与脱敏 AI 审查</strong>
              <button
                type="button"
                className="btn-secondary"
                style={{ padding: '6px 10px' }}
                onClick={() => setShowFactsSheet(false)}
              >
                <X size={16} />
              </button>
            </div>
            <div className="sheet-body">
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
                <div className="field-group" style={{ marginBottom: 0 }}>
                  <label className="field-label">适用城市</label>
                  <input
                    type="text"
                    className="text-input"
                    value={city}
                    placeholder="如：深圳 / 北京"
                    onChange={(e) => setCity(e.target.value)}
                  />
                </div>
                <div className="field-group" style={{ marginBottom: 0 }}>
                  <label className="field-label">岗位</label>
                  <input
                    type="text"
                    className="text-input"
                    value={position}
                    placeholder="如：研发 / 销售"
                    onChange={(e) => setPosition(e.target.value)}
                  />
                </div>
                <div className="field-group" style={{ marginBottom: 0 }}>
                  <label className="field-label">是否涉密</label>
                  <select
                    className="select-input"
                    value={confidential}
                    onChange={(e) => setConfidential(e.target.value)}
                  >
                    <option value={FACT_UNKNOWN}>不确定</option>
                    <option value={FACT_NO}>否</option>
                    <option value={FACT_YES}>是</option>
                  </select>
                </div>
                <div className="field-group" style={{ marginBottom: 0 }}>
                  <label className="field-label">签署状态</label>
                  <select
                    className="select-input"
                    value={signed}
                    onChange={(e) => setSigned(e.target.value)}
                  >
                    <option value={FACT_UNKNOWN}>不确定</option>
                    <option value={FACT_NO}>未签</option>
                    <option value={FACT_YES}>已签</option>
                  </select>
                </div>
              </div>

              {maskPreview && maskPreview.counts.size > 0 && (
                <div
                  style={{
                    marginTop: 12,
                    fontSize: 12,
                    color: 'var(--muted)',
                    display: 'flex',
                    alignItems: 'center',
                    gap: 6,
                    flexWrap: 'wrap',
                  }}
                >
                  <Lock size={13} color="var(--ok)" />
                  <span>AI 发送前自动脱敏：</span>
                  {Array.from(maskPreview.counts.entries()).map(([k, v]) => (
                    <span key={k} className="sev-badge sev-提示">
                      {k} ×{v}
                    </span>
                  ))}
                </div>
              )}

              <div style={{ display: 'flex', gap: 8, marginTop: 14 }}>
                <button
                  type="button"
                  className="btn-secondary"
                  style={{ flex: 1 }}
                  onClick={() => {
                    runLocalAudit(contractName, rawText, {
                      id: reportId,
                      city,
                      position,
                      confidential,
                      signed,
                    });
                    setShowFactsSheet(false);
                  }}
                >
                  更新本地规则结果
                </button>
                <button
                  type="button"
                  className="btn-primary"
                  style={{ flex: 1 }}
                  disabled={aiRunning}
                  onClick={async () => {
                    setShowFactsSheet(false);
                    await handleRunAiReview();
                  }}
                >
                  <Sparkles size={15} />
                  {aiRunning ? '审查中…' : '脱敏 AI 深度审查'}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* 原文高亮点击后的单条风险详情弹窗 */}
      {activeFinding && (
        <div className="sheet-backdrop" onClick={() => setActiveFinding(null)}>
          <div className="sheet-panel" onClick={(e) => e.stopPropagation()}>
            <div className="sheet-header">
              <strong>
                {anchorLabel(activeFinding.anchorId)} · {activeFinding.topic}
              </strong>
              <button
                type="button"
                className="btn-secondary"
                style={{ padding: '6px 10px' }}
                onClick={() => setActiveFinding(null)}
              >
                <X size={16} />
              </button>
            </div>
            <div className="sheet-body">
              <div style={{ display: 'flex', gap: 6, marginBottom: 10 }}>
                <span className={`sev-badge sev-${activeFinding.severity}`}>
                  {activeFinding.severity}
                </span>
                <span className="sev-badge sev-提示">{activeFinding.nature}</span>
                <span className="sev-badge sev-提示">{activeFinding.bargain}</span>
              </div>
              <p style={{ margin: '0 0 10px', fontSize: 14.5, lineHeight: 1.65 }}>
                {activeFinding.reason}
              </p>
              {activeFinding.suggestion && (
                <div className="card" style={{ background: 'var(--surface-2)', boxShadow: 'none' }}>
                  <div style={{ fontSize: 12, color: 'var(--muted)', marginBottom: 4 }}>修改建议</div>
                  <div style={{ fontSize: 14 }}>{activeFinding.suggestion}</div>
                </div>
              )}
              {activeFinding.lawRefs.length > 0 && (
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 12 }}>
                  {activeFinding.lawRefs.map((ref) => (
                    <button
                      key={ref}
                      type="button"
                      className="answer-pill-btn tint-brand"
                      onClick={() => {
                        setActiveFinding(null);
                        handleOpenLawRef(ref);
                      }}
                    >
                      <HarmonyIcon name="book" size={13} color="var(--brand)" />
                      {ref}
                    </button>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
