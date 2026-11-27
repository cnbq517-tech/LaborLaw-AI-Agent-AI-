import React from 'react';
import icArrowDown from '@harmony-media/ic_arrow_down.svg?raw';
import icBook from '@harmony-media/ic_book.svg?raw';
import icCheck from '@harmony-media/ic_check.svg?raw';
import icClock from '@harmony-media/ic_clock.svg?raw';
import icCoin from '@harmony-media/ic_coin.svg?raw';
import icCompose from '@harmony-media/ic_compose.svg?raw';
import icConsult from '@harmony-media/ic_consult.svg?raw';
import icCopy from '@harmony-media/ic_copy.svg?raw';
import icDoc from '@harmony-media/ic_doc.svg?raw';
import icFlame from '@harmony-media/ic_flame.svg?raw';
import icFolder from '@harmony-media/ic_folder.svg?raw';
import icGear from '@harmony-media/ic_gear.svg?raw';
import icHome from '@harmony-media/ic_home.svg?raw';
import icMenu from '@harmony-media/ic_menu.svg?raw';
import icPerson from '@harmony-media/ic_person.svg?raw';
import icPhoto from '@harmony-media/ic_photo.svg?raw';
import icPlus from '@harmony-media/ic_plus.svg?raw';
import icScale from '@harmony-media/ic_scale.svg?raw';
import icScan from '@harmony-media/ic_scan.svg?raw';
import icSearch from '@harmony-media/ic_search.svg?raw';
import icSend from '@harmony-media/ic_send.svg?raw';
import icShield from '@harmony-media/ic_shield.svg?raw';
import icStop from '@harmony-media/ic_stop.svg?raw';
import icTheme from '@harmony-media/ic_theme.svg?raw';

const ICONS = {
  arrow_down: icArrowDown,
  book: icBook,
  check: icCheck,
  clock: icClock,
  coin: icCoin,
  compose: icCompose,
  consult: icConsult,
  copy: icCopy,
  doc: icDoc,
  flame: icFlame,
  folder: icFolder,
  gear: icGear,
  home: icHome,
  menu: icMenu,
  person: icPerson,
  photo: icPhoto,
  plus: icPlus,
  scale: icScale,
  scan: icScan,
  search: icSearch,
  send: icSend,
  shield: icShield,
  stop: icStop,
  theme: icTheme,
} as const;

export type HarmonyIconName = keyof typeof ICONS;

function prepareSvg(raw: string): string {
  return raw
    .replace(/#000000|#000(?=["'\s/>])/gi, 'currentColor')
    .replace(/<svg\b([^>]*)>/i, (_match, attrs: string) => {
      const cleaned = attrs
        .replace(/\swidth="[^"]*"/gi, '')
        .replace(/\sheight="[^"]*"/gi, '');
      return `<svg${cleaned} width="100%" height="100%" style="display:block">`;
    });
}

const PREPARED: Record<HarmonyIconName, string> = Object.fromEntries(
  (Object.entries(ICONS) as Array<[HarmonyIconName, string]>).map(([k, v]) => [k, prepareSvg(v)])
) as Record<HarmonyIconName, string>;

interface HarmonyIconProps {
  name: HarmonyIconName;
  size?: number;
  color?: string;
  className?: string;
  style?: React.CSSProperties;
}

export const HarmonyIcon: React.FC<HarmonyIconProps> = ({
  name,
  size = 20,
  color = 'currentColor',
  className,
  style,
}) => {
  return (
    <span
      className={className}
      aria-hidden="true"
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
        width: size,
        height: size,
        color,
        flexShrink: 0,
        ...style,
      }}
      dangerouslySetInnerHTML={{ __html: PREPARED[name] }}
    />
  );
};
