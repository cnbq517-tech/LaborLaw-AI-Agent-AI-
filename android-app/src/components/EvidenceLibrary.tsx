import React, { useMemo, useRef, useState } from 'react';
import { Loader2, RefreshCw, Trash2, X } from 'lucide-react';
import {
  EVIDENCE_DONE,
  EVIDENCE_FAILED,
  EVIDENCE_RECOGNIZING,
  EVIDENCE_SOURCE_SHARED,
} from '@harmony/models/Evidence';
import {
  CAT_OTHER,
  EVIDENCE_CATEGORIES,
  FIELD_COMPANY,
  FIELD_LOCATION,
  FIELD_SALARY,
  FIELD_TIMELINE,
} from '@harmony/services/EvidenceExtractor';
import { HarmonyIcon } from './HarmonyIcon';
import type { LocalEvidence } from '../services/evidenceStore';

interface EvidenceLibraryProps {
  items: LocalEvidence[];
  onImportFiles: (files: FileList) => void;
  onRetryOcr: (item: LocalEvidence) => void;
  onUpdateCategory: (id: string, category: string) => void;
  onDelete: (id: string) => void;
  onApplyDossierField: (fieldIndex: number, value: string, label: string) => void;
  onToast: (msg: string) => void;
}

const FIELD_NAMES: Record<number, string> = {
  [FIELD_LOCATION]: '案件发生地',
  [FIELD_COMPANY]: '单位名称',
  [FIELD_SALARY]: '平均月薪',
  [FIELD_TIMELINE]: '时间节点',
};

export const EvidenceLibrary: React.FC<EvidenceLibraryProps> = ({
  items,
  onImportFiles,
  onRetryOcr,
  onUpdateCategory,
  onDelete,
  onApplyDossierField,
  onToast,
}) => {
  const fileRef = useRef<HTMLInputElement | null>(null);
  const [search, setSearch] = useState('');
  const [activeCategory, setActiveCategory] = useState('全部');
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const selected = useMemo(
    () => items.find((i) => i.id === selectedId) ?? null,
    [items, selectedId]
  );

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return items.filter((item) => {
      const cat = item.category || CAT_OTHER;
      if (activeCategory !== '全部' && cat !== activeCategory) return false;
      if (!q) return true;
      return (
        item.title.toLowerCase().includes(q) ||
        cat.toLowerCase().includes(q) ||
        item.text.toLowerCase().includes(q) ||
        item.rowsText.toLowerCase().includes(q)
      );
    });
  }, [items, search, activeCategory]);

  return (
    <div className="scroll-area">
      <input
        ref={fileRef}
        type="file"
        accept="image/*"
        multiple
        style={{ display: 'none' }}
        onChange={(e) => {
          if (e.target.files && e.target.files.length > 0) {
            onImportFiles(e.target.files);
          }
          e.target.value = '';
        }}
      />

      {/* 顶部导入与隐私说明 */}
      <div className="card" style={{ marginBottom: 12 }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10 }}>
          <div>
            <div style={{ fontSize: 15.5, fontWeight: 700 }}>端侧 OCR 证据库（{items.length}）</div>
            <div style={{ fontSize: 11.5, color: 'var(--muted)', marginTop: 3 }}>
              图片仅保存在本机并离线识别，永不上传；支持从相册/微信直接分享存入
            </div>
          </div>
          <button
            type="button"
            className="btn-gold"
            style={{ flexShrink: 0, padding: '8px 13px', fontSize: 13 }}
            onClick={() => fileRef.current?.click()}
          >
            <HarmonyIcon name="photo" size={15} color="var(--on-gold)" />
            导入照片
          </button>
        </div>
      </div>

      {/* 搜索与分类筛选 */}
      {items.length > 0 && (
        <>
          <div className="drawer-search-box" style={{ marginBottom: 10 }}>
            <HarmonyIcon name="search" size={16} color="var(--faint)" />
            <input
              type="text"
              className="drawer-search-input"
              value={search}
              placeholder="搜索已识别的文字、类别或名称"
              onChange={(e) => setSearch(e.target.value)}
            />
          </div>

          <div
            style={{
              display: 'flex',
              gap: 6,
              overflowX: 'auto',
              paddingBottom: 8,
              marginBottom: 8,
            }}
          >
            {['全部', ...EVIDENCE_CATEGORIES].map((cat) => {
              const active = activeCategory === cat;
              return (
                <button
                  key={cat}
                  type="button"
                  className={`answer-pill-btn ${active ? 'gold-soft' : 'tint-muted'}`}
                  style={{
                    flexShrink: 0,
                    border: active ? '1px solid var(--gold)' : '1px solid transparent',
                  }}
                  onClick={() => setActiveCategory(cat)}
                >
                  {cat}
                </button>
              );
            })}
          </div>
        </>
      )}

      {/* 证据列表 */}
      {filtered.length === 0 ? (
        <div className="card" style={{ textAlign: 'center', padding: '28px 18px' }}>
          <div
            style={{
              width: 50,
              height: 50,
              borderRadius: 16,
              background: 'var(--tint)',
              color: 'var(--brand)',
              display: 'inline-flex',
              alignItems: 'center',
              justifyContent: 'center',
              marginBottom: 10,
            }}
          >
            <HarmonyIcon name="scan" size={24} />
          </div>
          <div style={{ fontSize: 15, fontWeight: 700, marginBottom: 6 }}>
            {items.length === 0 ? '还没有保存证据照片' : '没有匹配的证据'}
          </div>
          <p style={{ margin: 0, fontSize: 12.5, color: 'var(--muted)', lineHeight: 1.6 }}>
            {items.length === 0
              ? '导入工资条、劳动合同、打卡考勤或聊天截图，手机本地离线识别文字并自动提取可回填卷宗的关键要素。'
              : '换个关键词或分类试试。'}
          </p>
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {filtered.map((item) => (
            <button
              key={item.id}
              type="button"
              className="card"
              style={{
                display: 'flex',
                alignItems: 'flex-start',
                gap: 12,
                textAlign: 'left',
                cursor: 'pointer',
                marginTop: 0,
              }}
              onClick={() => setSelectedId(item.id)}
            >
              <img
                src={item.dataUrl}
                alt={item.title}
                style={{
                  width: 64,
                  height: 64,
                  borderRadius: 12,
                  objectFit: 'cover',
                  flexShrink: 0,
                  border: '1px solid var(--line)',
                }}
              />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
                  <strong
                    style={{
                      fontSize: 14.5,
                      overflow: 'hidden',
                      textOverflow: 'ellipsis',
                      whiteSpace: 'nowrap',
                      maxWidth: '60%',
                    }}
                  >
                    {item.title}
                  </strong>
                  <span className="sev-badge sev-中">{item.category || CAT_OTHER}</span>
                  {item.source === EVIDENCE_SOURCE_SHARED && (
                    <span className="sev-badge sev-高">分享存入</span>
                  )}
                </div>

                <div style={{ fontSize: 12, color: 'var(--muted)', marginTop: 5, lineHeight: 1.45 }}>
                  {item.status === EVIDENCE_RECOGNIZING ? (
                    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, color: 'var(--brand)' }}>
                      <Loader2 size={12} style={{ animation: 'spin 1s linear infinite' }} />
                      正在本机离线识别文字…
                    </span>
                  ) : item.status === EVIDENCE_FAILED ? (
                    <span style={{ color: 'var(--danger)' }}>识别失败：{item.error || '点击重试'}</span>
                  ) : item.rowsText || item.text ? (
                    <span
                      style={{
                        display: '-webkit-box',
                        WebkitLineClamp: 2,
                        WebkitBoxOrient: 'vertical',
                        overflow: 'hidden',
                      }}
                    >
                      {item.rowsText || item.text}
                    </span>
                  ) : (
                    <span>未识别到明显文字</span>
                  )}
                </div>

                {item.extracted.length > 0 && (
                  <div style={{ display: 'flex', flexWrap: 'wrap', gap: 5, marginTop: 6 }}>
                    {item.extracted.map((ex, idx) => (
                      <span key={idx} className="case-field-chip filled">
                        可回填 {FIELD_NAMES[ex.field] ?? '要素'}：{ex.value.slice(0, 12)}
                      </span>
                    ))}
                  </div>
                )}
              </div>
            </button>
          ))}
        </div>
      )}

      {/* 证据详情弹窗（含手动分类、确认回填卷宗、OCR 原文复制） */}
      {selected && (
        <div className="sheet-backdrop" onClick={() => setSelectedId(null)}>
          <div className="sheet-panel" onClick={(e) => e.stopPropagation()}>
            <div className="sheet-header">
              <strong style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                {selected.title}
              </strong>
              <div style={{ display: 'flex', gap: 6 }}>
                <button
                  type="button"
                  className="btn-secondary"
                  style={{ padding: '6px 9px', color: 'var(--danger)' }}
                  aria-label="删除证据"
                  onClick={() => {
                    const id = selected.id;
                    setSelectedId(null);
                    onDelete(id);
                  }}
                >
                  <Trash2 size={15} />
                </button>
                <button
                  type="button"
                  className="btn-secondary"
                  style={{ padding: '6px 10px' }}
                  onClick={() => setSelectedId(null)}
                >
                  <X size={16} />
                </button>
              </div>
            </div>

            <div className="sheet-body">
              <img
                src={selected.dataUrl}
                alt={selected.title}
                style={{
                  width: '100%',
                  maxHeight: 240,
                  objectFit: 'contain',
                  borderRadius: 14,
                  background: 'var(--surface-2)',
                  marginBottom: 12,
                }}
              />

              {/* 分类选择 */}
              <div style={{ marginBottom: 12 }}>
                <div className="field-label">证据分类</div>
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
                  {EVIDENCE_CATEGORIES.map((cat) => {
                    const active = (selected.category || CAT_OTHER) === cat;
                    return (
                      <button
                        key={cat}
                        type="button"
                        className={`answer-pill-btn ${active ? 'gold-soft' : 'tint-muted'}`}
                        style={{
                          border: active ? '1px solid var(--gold)' : '1px solid transparent',
                        }}
                        onClick={() => onUpdateCategory(selected.id, cat)}
                      >
                        {cat}
                      </button>
                    );
                  })}
                </div>
              </div>

              {/* 识别出的卷宗建议：必须由用户逐项确认才写入卷宗 */}
              {selected.extracted.length > 0 && (
                <div className="card" style={{ background: 'var(--surface-2)', boxShadow: 'none', marginBottom: 12 }}>
                  <div style={{ fontSize: 12.5, fontWeight: 700, marginBottom: 6 }}>
                    识别到的卷宗要素（请核对后手动确认填入）
                  </div>
                  {selected.extracted.map((ex, idx) => (
                    <div
                      key={idx}
                      style={{
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'space-between',
                        gap: 8,
                        padding: '6px 0',
                        borderTop: idx > 0 ? '1px solid var(--line)' : 'none',
                      }}
                    >
                      <div style={{ minWidth: 0 }}>
                        <div style={{ fontSize: 12, color: 'var(--muted)' }}>
                          {FIELD_NAMES[ex.field] ?? '要素'}（来自 {ex.source}）
                        </div>
                        <div style={{ fontSize: 14, fontWeight: 600 }}>{ex.value}</div>
                      </div>
                      <button
                        type="button"
                        className="btn-gold"
                        style={{ padding: '6px 11px', fontSize: 12, flexShrink: 0 }}
                        onClick={() =>
                          onApplyDossierField(ex.field, ex.value, FIELD_NAMES[ex.field] ?? '要素')
                        }
                      >
                        填入卷宗
                      </button>
                    </div>
                  ))}
                </div>
              )}

              {/* OCR 识别文本 */}
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 6 }}>
                <span className="field-label" style={{ margin: 0 }}>
                  端侧 OCR 识别文本
                </span>
                <div style={{ display: 'flex', gap: 6 }}>
                  {selected.status !== EVIDENCE_RECOGNIZING && (
                    <button
                      type="button"
                      className="answer-pill-btn tint-muted"
                      style={{ height: 26 }}
                      onClick={() => onRetryOcr(selected)}
                    >
                      <RefreshCw size={12} />
                      重新识别
                    </button>
                  )}
                  {(selected.rowsText || selected.text) && (
                    <button
                      type="button"
                      className="answer-pill-btn gold-soft"
                      style={{ height: 26 }}
                      onClick={async () => {
                        await navigator.clipboard
                          .writeText(selected.rowsText || selected.text)
                          .catch(() => {});
                        onToast('已复制识别文字');
                      }}
                    >
                      <HarmonyIcon name="copy" size={12} color="var(--gold)" />
                      复制
                    </button>
                  )}
                </div>
              </div>

              <div
                className="card"
                style={{
                  background: 'var(--surface-2)',
                  boxShadow: 'none',
                  fontSize: 13,
                  lineHeight: 1.65,
                  whiteSpace: 'pre-wrap',
                }}
              >
                {selected.status === EVIDENCE_RECOGNIZING
                  ? '正在本机离线识别文字…'
                  : selected.status === EVIDENCE_DONE
                    ? selected.rowsText || selected.text || '（图片中未检测到明显文字）'
                    : selected.error || '识别失败，请点击重新识别'}
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
