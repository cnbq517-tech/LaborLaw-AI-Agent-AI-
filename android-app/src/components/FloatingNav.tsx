import React from 'react';
import { HarmonyIcon } from './HarmonyIcon';

export type NavTab = 'quick' | 'case' | 'contract' | 'mine';

interface FloatingNavProps {
  active: NavTab;
  onChange: (tab: NavTab) => void;
}

export const FloatingNav: React.FC<FloatingNavProps> = ({ active, onChange }) => {
  return (
    <nav className="floating-nav-wrap" aria-label="主导航">
      <div className="floating-nav-pill">
        <button
          type="button"
          className={`floating-nav-item ${active === 'quick' ? 'active' : ''}`}
          onClick={() => onChange('quick')}
        >
          <HarmonyIcon name="consult" size={active === 'quick' ? 22 : 21} />
          <span>普法</span>
        </button>
        <button
          type="button"
          className={`floating-nav-item ${active === 'case' ? 'active' : ''}`}
          onClick={() => onChange('case')}
        >
          <HarmonyIcon name="scale" size={active === 'case' ? 22 : 21} />
          <span>维权</span>
        </button>
        <button
          type="button"
          className={`floating-nav-item ${active === 'contract' ? 'active' : ''}`}
          onClick={() => onChange('contract')}
        >
          <HarmonyIcon name="shield" size={active === 'contract' ? 22 : 21} />
          <span>合同</span>
        </button>
      </div>
      <button
        type="button"
        className={`floating-mine-btn ${active === 'mine' ? 'active' : ''}`}
        onClick={() => onChange('mine')}
        aria-label="我的"
      >
        <HarmonyIcon name="person" size={21} />
        <span>我的</span>
      </button>
    </nav>
  );
};
