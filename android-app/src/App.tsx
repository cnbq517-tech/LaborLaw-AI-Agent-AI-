import React, { useCallback, useEffect, useState } from 'react';
import { Capacitor } from '@capacitor/core';
import { StatusBar, Style } from '@capacitor/status-bar';
import { ChatMessage, ChatRole, type LawCitation } from '@harmony/models/AppModels';
import { CaseRecord, ChatState, DossierState, QuickSession } from '@harmony/models/ChatState';
import {
  EVIDENCE_DONE,
  EVIDENCE_FAILED,
  EVIDENCE_RECOGNIZING,
  EVIDENCE_SOURCE_PHOTO,
  EVIDENCE_SOURCE_SHARED,
  EvidenceItem,
} from '@harmony/models/Evidence';
import { CAT_OTHER, EvidenceExtractor, LineBox } from '@harmony/services/EvidenceExtractor';
import { CitationSheet } from './components/CitationSheet';
import { FloatingNav, type NavTab } from './components/FloatingNav';
import { CasePage } from './pages/CasePage';
import { ContractPage } from './pages/ContractPage';
import { MinePage } from './pages/MinePage';
import { QuickConsultPage } from './pages/QuickConsultPage';
import {
  clearAllEvidence,
  deleteEvidenceItem,
  loadAllEvidence,
  saveEvidenceItem,
  type LocalEvidence,
} from './services/evidenceStore';
import { knowledgeClient, type KnowledgeStateSnapshot } from './services/knowledgeClient';
import {
  fileToCompressedDataUrl,
  listenSharedImages,
  recognizeImageOnDevice,
  takePendingSharedImages,
  type SharedImagePayload,
} from './services/ocrBridge';
import {
  loadCaseArchive,
  loadChatState,
  loadContractHistory,
  loadQuickHistory,
  loadSettings,
  saveCaseArchive,
  saveChatState,
  saveContractHistory,
  saveQuickHistory,
  saveSettings,
  type AppSettings,
  type SavedContractReport,
} from './services/storage';

export const App: React.FC = () => {
  const [tab, setTab] = useState<NavTab>('quick');
  const [lastMainTab, setLastMainTab] = useState<'quick' | 'case' | 'contract'>('quick');
  const [settings, setSettings] = useState<AppSettings>(() => loadSettings());
  const [chatState, setChatState] = useState<ChatState>(() => loadChatState());
  const [quickHistory, setQuickHistory] = useState<QuickSession[]>(() => loadQuickHistory());
  const [caseArchive, setCaseArchive] = useState<CaseRecord[]>(() => loadCaseArchive());
  const [contractHistory, setContractHistory] = useState<SavedContractReport[]>(() =>
    loadContractHistory()
  );
  const [evidence, setEvidence] = useState<LocalEvidence[]>([]);
  const [focusEvidenceSeq, setFocusEvidenceSeq] = useState(0);
  const [kbState, setKbState] = useState<KnowledgeStateSnapshot>(() => knowledgeClient.getState());
  const [activeCitation, setActiveCitation] = useState<{
    citation: LawCitation | null;
    citationsList: LawCitation[];
    lead: string;
  } | null>(null);
  const [toast, setToast] = useState('');

  const showToast = useCallback((msg: string) => {
    setToast(msg);
    window.setTimeout(() => {
      setToast((prev) => (prev === msg ? '' : prev));
    }, 2600);
  }, []);

  const runOcrForItem = useCallback(async (item: LocalEvidence) => {
    const recognizing: LocalEvidence = { ...item, status: EVIDENCE_RECOGNIZING, error: '' };
    setEvidence((prev) => prev.map((x) => (x.id === item.id ? recognizing : x)));
    await saveEvidenceItem(recognizing);

    try {
      const res = await recognizeImageOnDevice(item.dataUrl);
      const boxes = res.lines.map(
        (l) => new LineBox(l.text, l.left, l.centerY, l.height)
      );
      const rows = EvidenceExtractor.rows(boxes);
      const rowsText = rows.length > 0 ? rows.join('\n') : res.text;
      const autoCat = EvidenceExtractor.classify(rowsText) || CAT_OTHER;
      const finalCat = item.categoryManual && item.category ? item.category : autoCat;
      const extracted = EvidenceExtractor.extract(rows, finalCat, [], []);

      const done: LocalEvidence = {
        ...recognizing,
        status: EVIDENCE_DONE,
        width: res.width || item.width,
        height: res.height || item.height,
        text: res.text,
        rowsText,
        category: finalCat,
        extracted,
      };
      setEvidence((prev) => prev.map((x) => (x.id === item.id ? done : x)));
      await saveEvidenceItem(done);
    } catch (err) {
      const failed: LocalEvidence = {
        ...recognizing,
        status: EVIDENCE_FAILED,
        error: err instanceof Error ? err.message : String(err),
      };
      setEvidence((prev) => prev.map((x) => (x.id === item.id ? failed : x)));
      await saveEvidenceItem(failed);
    }
  }, []);

  const ingestSharedImages = useCallback(
    async (images: SharedImagePayload[]) => {
      if (images.length === 0) return;
      const created: LocalEvidence[] = [];
      for (const img of images) {
        const base = new EvidenceItem();
        base.id = `ev_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 6)}`;
        base.source = EVIDENCE_SOURCE_SHARED;
        base.createdAt = Date.now();
        base.title = img.name || '分享存入图片';
        base.width = img.width;
        base.height = img.height;
        base.status = EVIDENCE_RECOGNIZING;
        const local: LocalEvidence = Object.assign(base, { dataUrl: img.dataUrl });
        await saveEvidenceItem(local);
        created.push(local);
      }
      setEvidence((prev) => [...created, ...prev]);
      setLastMainTab('case');
      setTab('case');
      setFocusEvidenceSeq((n) => n + 1);
      showToast(`已从系统分享存入 ${created.length} 张证据照片，正在本机离线识别…`);
      for (const item of created) {
        await runOcrForItem(item);
      }
    },
    [runOcrForItem, showToast]
  );

  useEffect(() => {
    const unsub = knowledgeClient.subscribe(setKbState);
    knowledgeClient.init();
    return unsub;
  }, []);

  useEffect(() => {
    let removeShareListener: (() => void) | null = null;
    loadAllEvidence().then((list) => setEvidence(list));
    takePendingSharedImages().then((imgs) => {
      if (imgs.length > 0) ingestSharedImages(imgs);
    });
    listenSharedImages((imgs) => {
      ingestSharedImages(imgs);
    }).then((unsub) => {
      removeShareListener = unsub;
    });
    return () => {
      removeShareListener?.();
    };
  }, [ingestSharedImages]);

  useEffect(() => {
    const media = window.matchMedia('(prefers-color-scheme: dark)');
    const apply = () => {
      const dark =
        settings.theme === 'dark' || (settings.theme === 'system' && media.matches);
      document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light');
      if (Capacitor.isNativePlatform()) {
        StatusBar.setStyle({ style: Style.Dark }).catch(() => {});
        StatusBar.setBackgroundColor({ color: dark ? '#0C1B36' : '#122F5A' }).catch(() => {});
      }
    };
    apply();
    media.addEventListener('change', apply);
    return () => media.removeEventListener('change', apply);
  }, [settings.theme]);

  const switchTab = (next: NavTab) => {
    if (next !== 'mine') {
      setLastMainTab(next);
    }
    setTab(next);
  };

  const handleSaveSettings = (next: AppSettings) => {
    setSettings(next);
    saveSettings(next);
  };

  const handleUpdateQuick = (
    messages: ChatMessage[],
    sessionId: string,
    history: QuickSession[]
  ) => {
    const nextState = Object.assign(new ChatState(), chatState, {
      quickMessages: messages,
      quickSessionId: sessionId,
    });
    setChatState(nextState);
    setQuickHistory(history);
    saveChatState(nextState);
    saveQuickHistory(history);
  };

  const handleUpdateCase = (
    caseId: string,
    messages: ChatMessage[],
    dossier: DossierState,
    archive: CaseRecord[]
  ) => {
    const nextState = Object.assign(new ChatState(), chatState, {
      caseId,
      caseMessages: messages,
      dossier,
    });
    setChatState(nextState);
    setCaseArchive(archive);
    saveChatState(nextState);
    saveCaseArchive(archive);
  };

  const handleImportEvidenceFiles = async (files: FileList) => {
    const list = Array.from(files);
    const created: LocalEvidence[] = [];
    for (const file of list) {
      try {
        const { dataUrl, width, height } = await fileToCompressedDataUrl(file);
        const base = new EvidenceItem();
        base.id = `ev_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 6)}`;
        base.source = EVIDENCE_SOURCE_PHOTO;
        base.createdAt = Date.now();
        base.title = file.name.replace(/\.[^.]+$/, '') || '证据照片';
        base.width = width;
        base.height = height;
        base.status = EVIDENCE_RECOGNIZING;
        const local: LocalEvidence = Object.assign(base, { dataUrl });
        await saveEvidenceItem(local);
        created.push(local);
      } catch (err) {
        showToast(err instanceof Error ? err.message : '导入图片失败');
      }
    }
    if (created.length > 0) {
      setEvidence((prev) => [...created, ...prev]);
      showToast(`已导入 ${created.length} 张证据照片，正在本机离线识别…`);
      for (const item of created) {
        await runOcrForItem(item);
      }
    }
  };

  const handleUpdateEvidenceCategory = async (id: string, category: string) => {
    const target = evidence.find((i) => i.id === id);
    if (!target) return;
    const updated: LocalEvidence = { ...target, category, categoryManual: true };
    setEvidence((prev) => prev.map((x) => (x.id === id ? updated : x)));
    await saveEvidenceItem(updated);
  };

  const handleDeleteEvidence = async (id: string) => {
    setEvidence((prev) => prev.filter((x) => x.id !== id));
    await deleteEvidenceItem(id);
    showToast('已删除该份证据');
  };

  const handleUpdateContractHistory = (next: SavedContractReport[]) => {
    setContractHistory(next);
    saveContractHistory(next);
  };

  const handleAskAboutContract = (title: string, question: string) => {
    const msg = new ChatMessage(ChatRole.USER, `关于《${title}》：${question}`);
    const nextMsgs = [...chatState.caseMessages, msg];
    handleUpdateCase(chatState.caseId, nextMsgs, chatState.dossier, caseArchive);
    switchTab('case');
    showToast('已将合同问题带入「维权」，可继续追问');
  };

  const handleClearAllData = () => {
    setChatState(new ChatState());
    setQuickHistory([]);
    setCaseArchive([]);
    setContractHistory([]);
    setEvidence([]);
    clearAllEvidence();
  };

  return (
    <div className="app-shell">
      {tab === 'quick' && (
        <QuickConsultPage
          settings={settings}
          kbState={kbState}
          onRetryKb={() => knowledgeClient.retry()}
          messages={chatState.quickMessages}
          sessionId={chatState.quickSessionId}
          history={quickHistory}
          onUpdateSession={handleUpdateQuick}
          onOpenCitation={(citation, lead) =>
            setActiveCitation({ citation, citationsList: [], lead })
          }
          onOpenCitationsList={(citationsList) =>
            setActiveCitation({ citation: null, citationsList, lead: '' })
          }
          onGoMine={() => switchTab('mine')}
          onToast={showToast}
        />
      )}

      {tab === 'case' && (
        <CasePage
          settings={settings}
          kbState={kbState}
          onRetryKb={() => knowledgeClient.retry()}
          caseId={chatState.caseId}
          messages={chatState.caseMessages}
          dossier={chatState.dossier}
          archive={caseArchive}
          evidence={evidence}
          focusEvidenceSeq={focusEvidenceSeq}
          onImportEvidenceFiles={handleImportEvidenceFiles}
          onRetryEvidenceOcr={runOcrForItem}
          onUpdateEvidenceCategory={handleUpdateEvidenceCategory}
          onDeleteEvidence={handleDeleteEvidence}
          onUpdateCase={handleUpdateCase}
          onOpenCitation={(citation, lead) =>
            setActiveCitation({ citation, citationsList: [], lead })
          }
          onOpenCitationsList={(citationsList) =>
            setActiveCitation({ citation: null, citationsList, lead: '' })
          }
          onToast={showToast}
        />
      )}

      {tab === 'contract' && (
        <ContractPage
          settings={settings}
          kbState={kbState}
          onRetryKb={() => knowledgeClient.retry()}
          history={contractHistory}
          evidence={evidence}
          onUpdateHistory={handleUpdateContractHistory}
          onAskAboutContract={handleAskAboutContract}
          onOpenCitation={(citation, lead) =>
            setActiveCitation({ citation, citationsList: [], lead })
          }
          onToast={showToast}
        />
      )}

      {tab === 'mine' && (
        <MinePage
          settings={settings}
          kbState={kbState}
          quickCount={quickHistory.length}
          caseCount={caseArchive.length}
          contractCount={contractHistory.length}
          evidenceCount={evidence.length}
          onBack={() => switchTab(lastMainTab)}
          onRetryKb={() => knowledgeClient.retry()}
          onSaveSettings={handleSaveSettings}
          onClearAllData={handleClearAllData}
          onToast={showToast}
        />
      )}

      {tab !== 'mine' && <FloatingNav active={tab} onChange={switchTab} />}

      <CitationSheet
        citation={activeCitation?.citation ?? null}
        citationsList={activeCitation?.citationsList ?? []}
        lead={activeCitation?.lead ?? ''}
        onSelectCitation={(c) =>
          setActiveCitation((prev) => ({
            citation: c,
            citationsList: prev?.citationsList ?? [],
            lead: '',
          }))
        }
        onClose={() => setActiveCitation(null)}
      />

      {toast && <div className="toast">{toast}</div>}
    </div>
  );
};
