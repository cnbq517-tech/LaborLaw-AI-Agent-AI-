import { ChatMessage, ChatRole } from '../models/AppModels';
import { QuickSession } from '../models/ChatState';

// Titles, times and grouping for the 普法 history drawer, and which errors
// 我的 can fix. Pure logic, tested in tools/harmony/logic-tests.

export class HistoryGroup {
  label: string;
  sessions: QuickSession[];

  constructor(label: string, sessions: QuickSession[]) {
    this.label = label;
    this.sessions = sessions;
  }
}

const DAY: number = 24 * 60 * 60 * 1000;
// Ends every "model not configured" error.
export const CONFIG_HINT: string = '，请先在「我的」中配置模型服务';

export class ConversationText {
  // The first line of the first question.
  static sessionTitle(messages: ChatMessage[]): string {
    const first: ChatMessage | undefined =
      messages.find((message: ChatMessage) => message.role === ChatRole.USER);
    const content: string = first !== undefined ? first.content.trim() : '';
    const firstLine: string = content.split('\n')[0].trim();
    if (firstLine.length === 0) {
      return '普法咨询';
    }
    return firstLine.length > 40 ? firstLine.substring(0, 40) + '…' : firstLine;
  }

  // 今天 09:05, 3月2日 09:05, or 2025年3月2日 09:05.
  static sessionTime(timestamp: number, now: Date = new Date()): string {
    if (timestamp <= 0) {
      return '';
    }
    const date: Date = new Date(timestamp);
    const pad = (value: number): string => value < 10 ? '0' + value.toString() : value.toString();
    const time: string = pad(date.getHours()) + ':' + pad(date.getMinutes());
    if (date.toDateString() === now.toDateString()) {
      return '今天 ' + time;
    }
    const prefix: string = date.getFullYear() === now.getFullYear() ? '' : date.getFullYear().toString() + '年';
    return prefix + (date.getMonth() + 1).toString() + '月' + date.getDate().toString() + '日 ' + time;
  }

  static sessionMeta(session: QuickSession, now: Date = new Date()): string {
    const rounds: number =
      session.messages.filter((message: ChatMessage) => message.role === ChatRole.USER).length;
    return ConversationText.sessionTime(session.updatedAt, now) + ' · ' + rounds.toString() + ' 轮问答';
  }

  // Sessions matching the search, grouped into 今天 / 昨天 / 近 7 天 / 更早.
  static historyGroups(sessions: QuickSession[], search: string, now: Date = new Date()): HistoryGroup[] {
    const query: string = search.trim().toLowerCase();
    const matched: QuickSession[] = query.length === 0 ? sessions :
      sessions.filter((session: QuickSession) =>
        session.title.toLowerCase().includes(query) ||
        session.messages.some((message: ChatMessage) => message.content.toLowerCase().includes(query)));
    const startOfToday: number = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    const labels: string[] = ['今天', '昨天', '近 7 天', '更早'];
    const buckets: QuickSession[][] = [[], [], [], []];
    matched.forEach((session: QuickSession) => {
      if (session.updatedAt >= startOfToday) {
        buckets[0].push(session);
      } else if (session.updatedAt >= startOfToday - DAY) {
        buckets[1].push(session);
      } else if (session.updatedAt >= startOfToday - 6 * DAY) {
        buckets[2].push(session);
      } else {
        buckets[3].push(session);
      }
    });
    const groups: HistoryGroup[] = [];
    buckets.forEach((bucket: QuickSession[], index: number) => {
      if (bucket.length > 0) {
        groups.push(new HistoryGroup(labels[index], bucket));
      }
    });
    return groups;
  }

  // Errors the user fixes in 我的: no model configured, or the service
  // rejected the key. Network, index and permission errors are not.
  static needsModelSettings(message: string): boolean {
    return message.endsWith(CONFIG_HINT) || message.includes('认证失败') || message.includes('接口或模型不存在');
  }

  // 12 秒, or 1 分 5 秒.
  static thinkLabel(milliseconds: number): string {
    const seconds: number = Math.max(1, Math.round(milliseconds / 1000));
    return seconds < 60 ? seconds.toString() + ' 秒' :
      Math.floor(seconds / 60).toString() + ' 分 ' + (seconds % 60).toString() + ' 秒';
  }
}
