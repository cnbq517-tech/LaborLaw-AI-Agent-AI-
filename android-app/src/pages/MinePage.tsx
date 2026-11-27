import React, { useState } from 'react';
import { ChevronLeft, Eye, EyeOff } from 'lucide-react';
import { HarmonyIcon } from '../components/HarmonyIcon';
import { testApiConnection } from '../services/aiClient';
import type { KnowledgeStateSnapshot } from '../services/knowledgeClient';
import {
  clearAllConversationData,
  toApiConfig,
  type AppSettings,
  type ThemePreference,
} from '../services/storage';

interface MinePageProps {
  settings: AppSettings;
  kbState: KnowledgeStateSnapshot;
  quickCount: number;
  caseCount: number;
  contractCount: number;
  evidenceCount: number;
  onBack: () => void;
  onRetryKb: () => void;
  onSaveSettings: (next: AppSettings) => void;
  onClearAllData: () => void;
  onToast: (msg: string) => void;
}

const PRESETS = [
  { label: 'DeepSeek', baseUrl: 'https://api.deepseek.com/v1', model: 'deepseek-chat' },
  { label: 'DeepSeek 思考', baseUrl: 'https://api.deepseek.com/v1', model: 'deepseek-reasoner' },
  { label: '通义千问', baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1', model: 'qwen-plus' },
  { label: '硅基流动', baseUrl: 'https://api.siliconflow.cn/v1', model: 'deepseek-ai/DeepSeek-V3' },
];

export const MinePage: React.FC<MinePageProps> = ({
  settings,
  kbState,
  quickCount,
  caseCount,
  contractCount,
  evidenceCount,
  onBack,
  onSaveSettings,
  onClearAllData,
  onToast,
}) => {
  const [baseUrl, setBaseUrl] = useState(settings.baseUrl);
  const [model, setModel] = useState(settings.model);
  const [apiKey, setApiKey] = useState(settings.apiKey);
  const [showKey, setShowKey] = useState(false);
  const [testing, setTesting] = useState(false);
  const [connStatus, setConnStatus] = useState(
    settings.apiKey.trim() ? '已载入本机配置' : '尚未配置'
  );

  const persistApi = (u: string, m: string, k: string) => {
    const next: AppSettings = {
      ...settings,
      baseUrl: u.trim(),
      model: m.trim(),
      apiKey: k.trim(),
    };
    onSaveSettings(next);
    return next;
  };

  const handleTest = async () => {
    if (testing) return;
    const next = persistApi(baseUrl, model, apiKey);
    setTesting(true);
    setConnStatus('正在测试连接…');
    try {
      const reply = await testApiConnection(toApiConfig(next));
      setConnStatus(`连接正常（${reply.slice(0, 12)}）`);
      onToast('API 连接测试通过');
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      setConnStatus(`连接失败：${msg.slice(0, 40)}`);
      onToast('API 连接测试失败');
    } finally {
      setTesting(false);
    }
  };

  const handleTheme = (theme: ThemePreference) => {
    onSaveSettings({ ...settings, theme });
  };

  const handleClear = () => {
    clearAllConversationData();
    onClearAllData();
    onToast('已清空本机普法历史、维权案件与合同报告');
  };

  return (
    <div className="page-body">
      {/* 1:1 鸿蒙「我的」顶部蓝金头图 + 返回按钮 */}
      <header className="brand-header">
        <HarmonyIcon name="scale" size={96} className="brand-header-watermark" />
        <div className="brand-header-row">
          <div className="brand-header-left">
            <button
              type="button"
              className="brand-header-circle"
              aria-label="返回"
              onClick={onBack}
            >
              <ChevronLeft size={21} />
            </button>
            <div>
              <h1 className="brand-title">我的</h1>
              <p className="brand-subtitle">模型服务、外观与本机数据</p>
            </div>
          </div>
        </div>
      </header>

      <div className="scroll-area">
        {/* 1. 模型服务卡片 */}
        <div className="card">
          <div className="mine-card-head">
            <div className="mine-card-icon">
              <HarmonyIcon name="gear" size={17} />
            </div>
            <h2 className="mine-card-title">模型服务</h2>
          </div>

          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginBottom: 12 }}>
            {PRESETS.map((p) => (
              <button
                key={p.label}
                type="button"
                className="answer-pill-btn tint-muted"
                style={{ height: 28 }}
                onClick={() => {
                  setBaseUrl(p.baseUrl);
                  setModel(p.model);
                  persistApi(p.baseUrl, p.model, apiKey);
                }}
              >
                {p.label}
              </button>
            ))}
          </div>

          <div className="field-group">
            <label className="field-label">Base URL</label>
            <input
              type="url"
              className="text-input"
              value={baseUrl}
              placeholder="https://api.deepseek.com/v1"
              onChange={(e) => {
                setBaseUrl(e.target.value);
                persistApi(e.target.value, model, apiKey);
              }}
            />
          </div>

          <div className="field-group">
            <label className="field-label">模型名称</label>
            <input
              type="text"
              className="text-input"
              value={model}
              placeholder="deepseek-chat"
              onChange={(e) => {
                setModel(e.target.value);
                persistApi(baseUrl, e.target.value, apiKey);
              }}
            />
          </div>

          <div className="field-group">
            <label className="field-label">API Key</label>
            <div style={{ position: 'relative' }}>
              <input
                type={showKey ? 'text' : 'password'}
                className="text-input"
                style={{ paddingRight: 42 }}
                value={apiKey}
                placeholder="sk-..."
                onChange={(e) => {
                  setApiKey(e.target.value);
                  persistApi(baseUrl, model, e.target.value);
                }}
              />
              <button
                type="button"
                style={{
                  position: 'absolute',
                  right: 8,
                  top: '50%',
                  transform: 'translateY(-50%)',
                  border: 'none',
                  background: 'transparent',
                  color: 'var(--muted)',
                  cursor: 'pointer',
                  padding: 4,
                }}
                onClick={() => setShowKey((v) => !v)}
                aria-label="切换密钥可见性"
              >
                {showKey ? <EyeOff size={17} /> : <Eye size={17} />}
              </button>
            </div>
          </div>

          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: 6,
              fontSize: 12,
              color: 'var(--muted)',
              marginBottom: 14,
            }}
          >
            <HarmonyIcon name="shield" size={14} color="var(--ok)" />
            <span>API Key 仅保存在本机，通过 Android 原生 HTTPS 直连模型服务，不写入代码或同步</span>
          </div>

          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              gap: 10,
            }}
          >
            <div style={{ minWidth: 0 }}>
              <div style={{ fontSize: 12, color: 'var(--muted)' }}>连接状态</div>
              <div
                style={{
                  fontSize: 14,
                  fontWeight: 600,
                  color: connStatus.startsWith('连接失败') ? 'var(--danger)' : 'var(--text)',
                  marginTop: 2,
                }}
              >
                {connStatus}
              </div>
            </div>
            <button
              type="button"
              className="btn-primary"
              style={{ borderRadius: 12, padding: '10px 18px', flexShrink: 0 }}
              disabled={testing}
              onClick={handleTest}
            >
              {testing ? '测试中…' : '测试连接'}
            </button>
          </div>
        </div>

        {/* 2. 思考过程卡片 */}
        <div className="card">
          <div className="mine-card-head">
            <div className="mine-card-icon">
              <HarmonyIcon name="consult" size={16} />
            </div>
            <h2 className="mine-card-title">思考过程</h2>
          </div>

          <div className="toggle-row">
            <div>
              <div style={{ fontSize: 14.5, fontWeight: 600 }}>显示思考过程</div>
              <div style={{ fontSize: 12, color: 'var(--muted)', marginTop: 2 }}>
                模型返回思考内容时，在回答上方显示
              </div>
            </div>
            <button
              type="button"
              className={`toggle-switch ${settings.showReasoning ? 'on' : ''}`}
              aria-label="显示思考过程"
              onClick={() =>
                onSaveSettings({ ...settings, showReasoning: !settings.showReasoning })
              }
            >
              <span className="toggle-switch-knob" />
            </button>
          </div>

          <div className="toggle-row" style={{ borderTop: '1px solid var(--line)', marginTop: 6, paddingTop: 12 }}>
            <div>
              <div style={{ fontSize: 14.5, fontWeight: 600 }}>思考中自动展开</div>
              <div style={{ fontSize: 12, color: 'var(--muted)', marginTop: 2 }}>
                关闭后只显示「正在思考」，不展开内容
              </div>
            </div>
            <button
              type="button"
              className={`toggle-switch ${settings.autoExpandReasoning ? 'on' : ''}`}
              aria-label="思考中自动展开"
              onClick={() =>
                onSaveSettings({
                  ...settings,
                  autoExpandReasoning: !settings.autoExpandReasoning,
                })
              }
            >
              <span className="toggle-switch-knob" />
            </button>
          </div>
        </div>

        {/* 3. 外观卡片 */}
        <div className="card">
          <div className="mine-card-head">
            <div className="mine-card-icon">
              <HarmonyIcon name="theme" size={16} />
            </div>
            <h2 className="mine-card-title">外观</h2>
          </div>

          <div className="mine-seg-track">
            {(
              [
                { id: 'system', label: '跟随系统' },
                { id: 'light', label: '浅色' },
                { id: 'dark', label: '深色' },
              ] as const
            ).map((opt) => (
              <button
                key={opt.id}
                type="button"
                className={`mine-seg-btn ${settings.theme === opt.id ? 'active' : ''}`}
                onClick={() => handleTheme(opt.id)}
              >
                {opt.label}
              </button>
            ))}
          </div>
        </div>

        {/* 4. 本地法规库卡片 */}
        <div className="card">
          <div className="mine-card-head">
            <div className="mine-card-icon">
              <HarmonyIcon name="book" size={16} />
            </div>
            <h2 className="mine-card-title">本地法规库</h2>
          </div>
          <div className="mine-kv-row">
            <span className="mine-kv-label">收录资料</span>
            <span className="mine-kv-val">
              {kbState.documentCount > 0 ? `${kbState.documentCount} 份` : '加载中…'}
            </span>
          </div>
          <div className="mine-kv-row">
            <span className="mine-kv-label">可检索文档</span>
            <span className="mine-kv-val">
              {kbState.searchableDocumentCount > 0
                ? `${kbState.searchableDocumentCount} 份`
                : '加载中…'}
            </span>
          </div>
          <div className="mine-kv-row">
            <span className="mine-kv-label">检索方式</span>
            <span className="mine-kv-val">仅本地 · 不联网</span>
          </div>
        </div>

        {/* 5. 本机记录卡片 */}
        <div className="card">
          <div className="mine-card-head">
            <div className="mine-card-icon">
              <HarmonyIcon name="folder" size={16} />
            </div>
            <h2 className="mine-card-title">本机记录</h2>
          </div>
          <div className="mine-kv-row">
            <span className="mine-kv-label">普法咨询</span>
            <span className="mine-kv-val">{quickCount} 段历史</span>
          </div>
          <div className="mine-kv-row">
            <span className="mine-kv-label">维权案件</span>
            <span className="mine-kv-val">{caseCount} 个</span>
          </div>
          <div className="mine-kv-row">
            <span className="mine-kv-label">合同报告</span>
            <span className="mine-kv-val">{contractCount} 份</span>
          </div>
          <div className="mine-kv-row">
            <span className="mine-kv-label">证据库</span>
            <span className="mine-kv-val">{evidenceCount} 份材料</span>
          </div>
          <div style={{ marginTop: 12 }}>
            <button
              type="button"
              className="btn-danger"
              style={{ width: '100%' }}
              onClick={handleClear}
            >
              清空本机记录
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
