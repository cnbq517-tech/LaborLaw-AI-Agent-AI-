/**
 * 正义蓝 × 鎏金 · 浅色/深色双主题设计 Token
 *
 * 说明：颜色以语义命名，浅色（LIGHT）与深色（DARK）两套值。
 * 页面通过 mediaquery('(dark-mode: true)') 得到 isDark，再选择对应 ThemeColors。
 * 深色主色取更亮一档以保证正文与控件对比度（≥ WCAG AA）。
 * 金色仅用于点睛、光感与描边，不用于正文小字。
 */
export interface ThemeColors {
  // 背景（竖向渐变）
  bgTop: string;
  bgBottom: string;
  // 表面与分隔
  surface: string;
  surface2: string;
  line: string;
  // 文字
  text: string;
  muted: string;
  faint: string;
  // 品牌
  brand: string;
  brandStrong: string;
  tint: string;
  // 金色
  gold: string;
  goldDeep: string;
  glow: string;
  // 语义状态
  ok: string;
  okBg: string;
  danger: string;
  dangerBg: string;
  warn: string;
  // 反色文字（填充控件上的文字）
  onBrand: string;
  onGold: string;
  // 输入
  inputBg: string;
  placeholder: string;
  selection: string;
  // 沉浸头图渐变（三段）
  headerA: string;
  headerB: string;
  headerC: string;
  headerText: string;
  headerSub: string;
  // 悬浮岛导航
  navActiveBg: string;
  navBorder: string;
  navShadow: string;
  // 阴影（ARGB）
  cardShadow: string;
  softShadow: string;
}

export const LIGHT: ThemeColors = {
  bgTop: '#F7F9FC',
  bgBottom: '#EDF1F8',
  surface: '#FFFFFF',
  surface2: '#EEF2F8',
  line: '#E1E7F0',
  text: '#0F1E33',
  muted: '#54637C',
  faint: '#8593A8',
  brand: '#1D4B8F',
  brandStrong: '#12315E',
  tint: '#E8EFFA',
  gold: '#C0842A',
  goldDeep: '#9C6A18',
  glow: '#E8B85C',
  ok: '#1F8E68',
  okBg: '#E4F2EC',
  danger: '#C0483E',
  dangerBg: '#FBECEA',
  warn: '#9C6A18',
  onBrand: '#FFFFFF',
  onGold: '#FFFFFF',
  inputBg: '#EEF2F8',
  placeholder: '#8593A8',
  selection: '#33C0842A',
  headerA: '#122F5A',
  headerB: '#1D4B8F',
  headerC: '#7A6534',
  headerText: '#FFFFFF',
  headerSub: '#C9D8F0',
  navActiveBg: '#E6E8EFFA',
  navBorder: '#E6FFFFFF',
  navShadow: '#33C0842A',
  cardShadow: '#14101E33',
  softShadow: '#1F101E33'
};

export const DARK: ThemeColors = {
  bgTop: '#0E1B30',
  bgBottom: '#0A1220',
  surface: '#151F33',
  surface2: '#1A2740',
  line: '#2A3A56',
  text: '#EAF0FA',
  muted: '#9DB0CC',
  faint: '#6C7E99',
  brand: '#5B8AD6',
  brandStrong: '#A9C3E8',
  tint: '#1C2A44',
  gold: '#E0B45C',
  goldDeep: '#B48A2C',
  glow: '#E7BE6A',
  ok: '#49C39B',
  okBg: '#123329',
  danger: '#F0766B',
  dangerBg: '#3A211F',
  warn: '#E0B45C',
  onBrand: '#08111F',
  onGold: '#0A1220',
  inputBg: '#1A2740',
  placeholder: '#6C7E99',
  selection: '#33E0B45C',
  headerA: '#0C1B36',
  headerB: '#1F3F74',
  headerC: '#5B4C2B',
  headerText: '#EAF1FB',
  headerSub: '#AFC2E0',
  navActiveBg: '#B31C2A44',
  navBorder: '#33A9C3E8',
  navShadow: '#4DE0B45C',
  cardShadow: '#40000000',
  softShadow: '#59000000'
};

export function themeOf(isDark: boolean): ThemeColors {
  return isDark ? DARK : LIGHT;
}
