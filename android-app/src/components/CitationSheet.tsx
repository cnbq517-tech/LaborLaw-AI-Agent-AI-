import React from 'react';
import { X } from 'lucide-react';
import type { LawCitation } from '@harmony/models/AppModels';
import { CitationText } from '@harmony/services/CitationText';
import { HarmonyIcon } from './HarmonyIcon';

interface CitationSheetProps {
  citation: LawCitation | null;
  citationsList?: LawCitation[];
  lead?: string;
  onSelectCitation?: (citation: LawCitation) => void;
  onClose: () => void;
}

export const CitationSheet: React.FC<CitationSheetProps> = ({
  citation,
  citationsList = [],
  lead = '',
  onSelectCitation,
  onClose,
}) => {
  if (!citation && citationsList.length === 0) return null;

  const hl = citation && lead ? CitationText.highlight(citation.excerpt, lead) : undefined;

  return (
    <div className="sheet-backdrop" onClick={onClose}>
      <div className="sheet-panel" onClick={(e) => e.stopPropagation()}>
        <div className="sheet-header">
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
            <HarmonyIcon name="book" size={18} color="var(--gold)" />
            <div style={{ minWidth: 0 }}>
              <div
                style={{
                  fontWeight: 700,
                  fontSize: 15,
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                  whiteSpace: 'nowrap',
                }}
              >
                {citation ? citation.title : `本轮检索依据（${citationsList.length} 条）`}
              </div>
              {citation && (
                <div style={{ fontSize: 12, color: 'var(--muted)' }}>
                  {citation.id ? `[${citation.id}] ` : ''}
                  {citation.article || '相关条款'}
                </div>
              )}
            </div>
          </div>
          <button
            type="button"
            className="btn-secondary"
            style={{ padding: '6px 10px' }}
            onClick={onClose}
            aria-label="关闭"
          >
            <X size={16} />
          </button>
        </div>

        <div className="sheet-body">
          {citation ? (
            <>
              <div
                style={{
                  display: 'flex',
                  flexWrap: 'wrap',
                  gap: 6,
                  marginBottom: 12,
                  fontSize: 12,
                }}
              >
                {citation.status && (
                  <span className="sev-badge sev-中">效力状态：{citation.status}</span>
                )}
                {citation.effectiveDate && (
                  <span className="sev-badge sev-提示">生效日期：{citation.effectiveDate}</span>
                )}
                {citation.region && (
                  <span className="sev-badge sev-提示">地区：{citation.region}</span>
                )}
              </div>

              <div
                className="card"
                style={{
                  background: 'var(--surface-2)',
                  whiteSpace: 'pre-wrap',
                  fontSize: 14,
                  lineHeight: 1.75,
                  boxShadow: 'none',
                }}
              >
                {hl ? (
                  <>
                    {citation.excerpt.slice(0, hl.start)}
                    <span className="excerpt-highlight">
                      {citation.excerpt.slice(hl.start, hl.end)}
                    </span>
                    {citation.excerpt.slice(hl.end)}
                  </>
                ) : (
                  citation.excerpt
                )}
              </div>

              {citation.source && (
                <p style={{ fontSize: 12, color: 'var(--faint)', marginTop: 10 }}>
                  来源文件：{citation.source}
                </p>
              )}

              <div className="disclaimer-bar" style={{ marginTop: 10 }}>
                时效提示：本地内置法规库可能包含尚未完成效力更新的历史文件，请在正式主张权利或仲裁前核对最新现行有效条文。
              </div>
            </>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              {citationsList.map((item, idx) => (
                <button
                  key={item.id + idx}
                  type="button"
                  className="card"
                  style={{
                    width: '100%',
                    textAlign: 'left',
                    cursor: 'pointer',
                    background: 'var(--surface-2)',
                    boxShadow: 'none',
                  }}
                  onClick={() => onSelectCitation?.(item)}
                >
                  <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 4 }}>
                    <span className="citation-chip">{idx + 1}</span>
                    <strong style={{ fontSize: 14 }}>{item.title}</strong>
                  </div>
                  <div style={{ fontSize: 12, color: 'var(--brand)', marginBottom: 4 }}>
                    {item.article}
                    {item.status ? ` · ${item.status}` : ''}
                  </div>
                  <div
                    style={{
                      fontSize: 12.5,
                      color: 'var(--muted)',
                      display: '-webkit-box',
                      WebkitLineClamp: 3,
                      WebkitBoxOrient: 'vertical',
                      overflow: 'hidden',
                    }}
                  >
                    {item.excerpt}
                  </div>
                </button>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
