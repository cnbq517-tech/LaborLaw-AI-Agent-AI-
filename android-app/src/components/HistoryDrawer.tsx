import React, { useMemo, useRef, useState } from 'react';
import { MAX_QUICK_SESSIONS, type QuickSession } from '@harmony/models/ChatState';
import { ConversationText } from '@harmony/services/ConversationText';
import { HarmonyIcon } from './HarmonyIcon';

interface HistoryDrawerProps {
  open: boolean;
  sessions: QuickSession[];
  activeSessionId: string;
  onClose: () => void;
  onNewChat: () => void;
  onSelectSession: (session: QuickSession) => void;
  onDeleteSession: (id: string) => void;
}

export const HistoryDrawer: React.FC<HistoryDrawerProps> = ({
  open,
  sessions,
  activeSessionId,
  onClose,
  onNewChat,
  onSelectSession,
  onDeleteSession,
}) => {
  const [search, setSearch] = useState('');
  const [swipedId, setSwipedId] = useState<string>('');
  const touchStartX = useRef<number>(0);
  const drawerTouchStartX = useRef<number>(0);

  const groups = useMemo(
    () => ConversationText.historyGroups(sessions, search),
    [sessions, search]
  );

  return (
    <div
      className={`drawer-backdrop ${open ? 'open' : ''}`}
      onClick={() => {
        setSwipedId('');
        onClose();
      }}
      aria-hidden={!open}
    >
      <aside
        className={`history-drawer ${open ? 'open' : ''}`}
        onClick={(e) => e.stopPropagation()}
        onTouchStart={(e) => {
          drawerTouchStartX.current = e.touches[0].clientX;
        }}
        onTouchEnd={(e) => {
          const dx = e.changedTouches[0].clientX - drawerTouchStartX.current;
          if (dx < -70 && !swipedId) {
            onClose();
          }
        }}
      >
        {/* 顶部标题 + 段数胶囊 */}
        <div className="drawer-header">
          <div>
            <h2 className="drawer-title">历史咨询</h2>
            <div className="drawer-gold-bar" />
          </div>
          <span className="drawer-count-pill">{sessions.length} 段</span>
        </div>

        {/* 搜索框 */}
        <div className="drawer-search-box">
          <HarmonyIcon name="search" size={16} color="var(--faint)" />
          <input
            type="text"
            className="drawer-search-input"
            value={search}
            placeholder="搜索咨询记录"
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>

        {/* 鎏金「新建咨询」按钮 */}
        <button
          type="button"
          className="drawer-new-btn"
          onClick={() => {
            setSwipedId('');
            onNewChat();
          }}
        >
          <HarmonyIcon name="compose" size={17} color="var(--on-gold)" />
          <span>新建咨询</span>
        </button>

        {/* 分组历史列表 */}
        <div className="drawer-list" onClick={() => swipedId && setSwipedId('')}>
          {groups.length === 0 ? (
            <div className="drawer-empty">
              {search.trim() ? '未找到匹配的咨询记录' : '暂无历史咨询记录'}
            </div>
          ) : (
            groups.map((group) => (
              <div key={group.label} className="drawer-group">
                <div className="drawer-group-label">{group.label}</div>
                {group.sessions.map((s) => {
                  const isActive = s.id === activeSessionId;
                  const isSwiped = s.id === swipedId;
                  return (
                    <div
                      key={s.id}
                      className="drawer-item-wrap"
                      onTouchStart={(e) => {
                        touchStartX.current = e.touches[0].clientX;
                      }}
                      onTouchEnd={(e) => {
                        const dx = e.changedTouches[0].clientX - touchStartX.current;
                        if (dx < -40) {
                          e.stopPropagation();
                          setSwipedId(s.id);
                        } else if (dx > 30 && isSwiped) {
                          e.stopPropagation();
                          setSwipedId('');
                        }
                      }}
                    >
                      <button
                        type="button"
                        className={`drawer-item ${isActive ? 'active' : ''} ${
                          isSwiped ? 'swiped' : ''
                        }`}
                        onClick={() => {
                          if (isSwiped) {
                            setSwipedId('');
                            return;
                          }
                          onSelectSession(s);
                        }}
                      >
                        <div className="drawer-item-title">{s.title}</div>
                        <div className={`drawer-item-meta ${isActive ? 'active' : ''}`}>
                          {ConversationText.sessionMeta(s)}
                        </div>
                      </button>

                      {isSwiped && (
                        <button
                          type="button"
                          className="drawer-delete-btn"
                          onClick={(e) => {
                            e.stopPropagation();
                            setSwipedId('');
                            onDeleteSession(s.id);
                          }}
                        >
                          删除
                        </button>
                      )}
                    </div>
                  );
                })}
              </div>
            ))
          )}
        </div>

        {/* 底部状态栏 */}
        <div className="drawer-footer">
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5 }}>
            <HarmonyIcon name="shield" size={13} color="var(--ok)" />
            仅保存在本机 · {sessions.length} / {MAX_QUICK_SESSIONS} 段
          </span>
          <span style={{ color: 'var(--faint)' }}>左滑可删除</span>
        </div>
      </aside>
    </div>
  );
};
