import React from 'react';
import { RefreshCw } from 'lucide-react';
import type { KnowledgeStateSnapshot } from '../services/knowledgeClient';
import { HarmonyIcon, type HarmonyIconName } from './HarmonyIcon';

interface BrandHeaderProps {
  title: string;
  subtitle: string;
  kbState: KnowledgeStateSnapshot;
  onRetryKb: () => void;
  leftIcon?: HarmonyIconName;
  onLeftClick?: () => void;
  rightAction?: React.ReactNode;
  showKbBar?: boolean;
}

export const BrandHeader: React.FC<BrandHeaderProps> = ({
  title,
  subtitle,
  kbState,
  onRetryKb,
  leftIcon = 'scale',
  onLeftClick,
  rightAction,
  showKbBar = false,
}) => {
  return (
    <header className="brand-header">
      <HarmonyIcon name="scale" size={96} className="brand-header-watermark" />

      <div className="brand-header-row">
        <div className="brand-header-left">
          <button
            type="button"
            className="brand-header-circle"
            onClick={onLeftClick}
            style={{ cursor: onLeftClick ? 'pointer' : 'default' }}
            aria-label={title}
          >
            <HarmonyIcon name={leftIcon} size={20} />
          </button>
          <div style={{ minWidth: 0 }}>
            <h1 className="brand-title">{title}</h1>
            <p className="brand-subtitle">{subtitle}</p>
          </div>
        </div>
        {rightAction && <div>{rightAction}</div>}
      </div>

      {showKbBar && kbState.status === 'error' && (
        <div
          style={{
            position: 'relative',
            zIndex: 1,
            marginTop: 8,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            gap: 8,
            fontSize: 12,
            color: '#FFE5E2',
          }}
        >
          <span>本地法规库加载失败：{kbState.error || '请重试'}</span>
          <button type="button" className="header-action-btn" onClick={onRetryKb}>
            <RefreshCw size={12} />
            重试
          </button>
        </div>
      )}
    </header>
  );
};
