import {
  ClauseAnchor,
  LEVEL_ARTICLE,
  LEVEL_CHAPTER,
  LEVEL_ITEM,
  LEVEL_PARAGRAPH,
  StructureAudit,
  StructureWarning,
  WHOLE_CONTRACT
} from './ContractTypes';

// Structure audit, ported from the desktop client's contract_review/structure.py:
// clause numbering is recognized with a family of patterns, a level state
// machine and negative filters, never a single regex. Anomalies become
// warnings instead of passing silently.

const CN_DIGITS: string = '零〇一二三四五六七八九十百千两';
const NUM: string = `[${CN_DIGITS}0-9]+`;

const RE_CHAPTER: RegExp = new RegExp(`^\\s*第${NUM}章`);
const RE_ARTICLE: RegExp = new RegExp(`^\\s*第${NUM}条`);
const RE_PARAGRAPH: RegExp = new RegExp(`^\\s*第${NUM}款`);
const RE_ITEM: RegExp = new RegExp(`^\\s*[（(]\\s*${NUM}\\s*[)）]`);
const RE_DOTTED: RegExp = /^\s*\d+(?:\.\d+){1,3}(?=[\s、.])/;

// Numbers that look like clause numbers but are not (amounts, dates, legal
// citations, references to other clauses, attachment lists).
const RE_MONEY_DATE_SOURCE: string = '(元|万元|人民币|%|\\d{4}\\s*年|\\d{1,2}\\s*月|\\d{1,2}\\s*日|二[〇零○]\\d{2}\\s*年)';
const RE_MONEY_DATE: RegExp = new RegExp(RE_MONEY_DATE_SOURCE);
const RE_LAW_CITE: RegExp = new RegExp(`《[^》]{2,30}》\\s*第${NUM}条`);
const RE_SELF_REF: RegExp = new RegExp(`(?:详见|见|参见|依据|按照|根据|适用|除)[^。；\\n]{0,15}第${NUM}[条款项]`);
const RE_ATTACH_LIST: RegExp = /^\s*\d+[.、]\s*\S{1,12}$/;
const CROSS_REF_SOURCE: string = `((?:详见|见|参见|依据|按照|根据|适用)[^。；\\n]{0,15})(第${NUM}条)`;
const STRIP_CHARS: string = ' ，,。;；:、';

const LEVELS: string[] = [LEVEL_CHAPTER, LEVEL_ARTICLE, LEVEL_PARAGRAPH, LEVEL_ITEM];

const TERM_ALIASES: string[][] = [
  ['标准工资', '基本工资'], ['商业秘密', '保密信息'], ['甲方', '用人单位'], ['乙方', '劳动者'], ['月工资', '基本工资']
];

class DetectedNumber {
  level: string;
  rawNo: string;

  constructor(level: string, rawNo: string) {
    this.level = level;
    this.rawNo = rawNo;
  }
}

export class ContractStructure {
  // Full-width digits and percent signs become ASCII so every pattern sees one
  // form. Each replacement is one UTF-16 unit for one, so offsets are kept.
  static normalize(text: string): string {
    let out: string = '';
    for (let i: number = 0; i < text.length; i++) {
      const code: number = text.charCodeAt(i);
      if (code >= 0xFF10 && code <= 0xFF19) {
        out += String.fromCharCode(code - 0xFF10 + 48);
      } else if (code === 0xFF05) {
        out += '%';
      } else if (code === 0xFF0E) {
        out += '.';
      } else if (code === 0x3000) {
        out += ' ';
      } else {
        out += text.charAt(i);
      }
    }
    return out;
  }

  // Chinese numerals to a number: 十, 十一, 二十, 一百二十. Returns -1 when
  // there is nothing to read.
  static cn2int(text: string): number {
    const s: string = text.trim();
    if (s.length === 0) {
      return -1;
    }
    if (/^\d+$/.test(s)) {
      return parseInt(s, 10);
    }
    let section: number = 0;
    let digit: number = 0;
    let found: boolean = false;
    for (let i: number = 0; i < s.length; i++) {
      const ch: string = s.charAt(i);
      const value: number = '零〇一二三四五六七八九'.indexOf(ch);
      if (value >= 0) {
        digit = value >= 2 ? value - 1 : 0;
        found = true;
      } else if (ch === '两') {
        digit = 2;
        found = true;
      } else if (ch === '十' || ch === '百' || ch === '千') {
        const unit: number = ch === '十' ? 10 : ch === '百' ? 100 : 1000;
        section += (digit === 0 ? 1 : digit) * unit;
        digit = 0;
        found = true;
      }
    }
    return found ? section + digit : -1;
  }

  static audit(text: string, scanned: boolean): StructureAudit {
    const normalized: string = ContractStructure.normalize(text);
    const anchors: ClauseAnchor[] = [];
    const warnings: StructureWarning[] = [];
    ContractStructure.buildAnchors(normalized, scanned, anchors, warnings);
    const terms: Map<string, string> = ContractStructure.buildTerms(anchors, warnings);
    return new StructureAudit(anchors, warnings, terms);
  }

  private static buildAnchors(text: string, scanned: boolean, anchors: ClauseAnchor[],
    warnings: StructureWarning[]): void {
    const context: Map<string, string> = new Map<string, string>();
    let paragraphCount: number = 0;
    let itemCount: number = 0;
    let chapterCount: number = 0;
    const seenRaw: Map<string, string> = new Map<string, string>();
    let lastArticle: number = 0;
    let current: ClauseAnchor | undefined = undefined;

    let pos: number = 0;
    for (const raw of text.split('\n')) {
      const line: string = raw.trim();
      // Offsets point at the stripped line, not at its leading whitespace.
      const start: number = pos + raw.indexOf(line.length > 0 ? line.charAt(0) : '');
      pos += raw.length + 1;
      if (line.length === 0) {
        continue;
      }
      const detected: DetectedNumber | undefined = ContractStructure.detect(line);

      // A filtered or unnumbered line never starts a clause, but its text joins
      // the previous one: dropping it would lose clause text and report the
      // clause as empty.
      if (detected === undefined || ContractStructure.isNegative(line)) {
        if (current !== undefined) {
          current.text += '\n' + line;
          current.end = start + line.length;
        }
        continue;
      }

      const level: string = detected.level;
      const rawNo: string = detected.rawNo;
      const num: number = ContractStructure.extractNum(rawNo);
      let anchorId: string = '';
      if (level === LEVEL_ARTICLE) {
        const index: number = num > 0 ? num : lastArticle + 1;
        if (lastArticle > 0) {
          if (index > lastArticle + 1) {
            warnings.push(new StructureWarning('断号',
              `第${lastArticle}条 → 第${index}条 之间缺号（可能漏粘贴/漏识别）`));
          } else if (index < lastArticle) {
            warnings.push(new StructureWarning('跳级', `条号回退：第${lastArticle}条 → 第${index}条`));
          }
        }
        lastArticle = index;
        paragraphCount = 0;
        itemCount = 0;
        anchorId = 'C' + ContractStructure.pad(index);
      } else if (level === LEVEL_CHAPTER) {
        chapterCount++;
        anchorId = 'CH' + ContractStructure.pad(num > 0 ? num : chapterCount);
      } else if (level === LEVEL_PARAGRAPH) {
        paragraphCount++;
        if (!context.has(LEVEL_ARTICLE)) {
          warnings.push(new StructureWarning('层级异常', `「${rawNo}」出现在任何条之外`));
        }
        anchorId = (context.get(LEVEL_ARTICLE) ?? WHOLE_CONTRACT) + '-' + ContractStructure.pad(paragraphCount);
      } else {
        itemCount++;
        if (!context.has(LEVEL_ARTICLE) && !context.has(LEVEL_PARAGRAPH)) {
          warnings.push(new StructureWarning('层级异常', `「${rawNo}」出现在任何条/款之外`));
        }
        anchorId = (context.get(LEVEL_PARAGRAPH) ?? context.get(LEVEL_ARTICLE) ?? WHOLE_CONTRACT) + '-' +
          ContractStructure.pad(itemCount);
      }

      let parent: string = '';
      if (level === LEVEL_ARTICLE) {
        parent = context.get(LEVEL_CHAPTER) ?? '';
      } else if (level === LEVEL_PARAGRAPH) {
        parent = context.get(LEVEL_ARTICLE) ?? '';
      } else if (level === LEVEL_ITEM) {
        parent = context.get(LEVEL_PARAGRAPH) ?? context.get(LEVEL_ARTICLE) ?? '';
      }

      const anchor: ClauseAnchor = new ClauseAnchor(anchorId, rawNo, level, line, start, start + line.length, parent);
      anchors.push(anchor);
      current = anchor;

      const seen: string | undefined = seenRaw.get(rawNo);
      if (seen !== undefined && seen !== anchorId) {
        warnings.push(new StructureWarning('重号', `编号重复「${rawNo}」：${seen} 与 ${anchorId}`, anchorId));
      }
      if (seen === undefined) {
        seenRaw.set(rawNo, anchorId);
      }

      context.set(level, anchorId);
      const depth: number = LEVELS.indexOf(level);
      for (let i: number = depth + 1; i < LEVELS.length; i++) {
        context.delete(LEVELS[i]);
      }
    }

    // Level consistency.
    const ids: Set<string> = new Set<string>(anchors.map((a: ClauseAnchor) => a.anchorId));
    for (const a of anchors) {
      const body: string = a.text.split(a.rawNo).join('').trim();
      if ((a.level === LEVEL_ARTICLE || a.level === LEVEL_PARAGRAPH) && body.length < 4) {
        warnings.push(new StructureWarning('空条', `${a.anchorId}（${a.rawNo}）有编号无正文`, a.anchorId));
      }
      if (a.parentId.length > 0 && !ids.has(a.parentId)) {
        warnings.push(new StructureWarning('层级异常', `${a.anchorId} 父节点 ${a.parentId} 缺失`, a.anchorId));
      }
    }

    // Dangling references. Clause-level first, then the whole text, because
    // lines that reference other clauses are filtered out of the anchor table.
    // Each missing target is reported once.
    const byRaw: Set<string> = new Set<string>();
    anchors.forEach((a: ClauseAnchor) => {
      if (a.rawNo.length > 0) {
        byRaw.add(a.rawNo);
      }
    });
    const reported: Set<string> = new Set<string>();
    for (const a of anchors) {
      const re: RegExp = new RegExp(CROSS_REF_SOURCE, 'g');
      let m: RegExpExecArray | null = re.exec(a.text);
      while (m !== null) {
        const prefix: string = m[1];
        const key: string = m[2];
        if (!prefix.includes('《') && !prefix.includes('》')) {
          a.refsOut.push(key);
          if (!byRaw.has(key) && !reported.has(key)) {
            reported.add(key);
            warnings.push(new StructureWarning('悬空引用',
              `${a.anchorId} 引用了不存在的 ${key}（条款可能已被删除）`, a.anchorId));
          }
        }
        m = re.exec(a.text);
      }
    }
    const whole: RegExp = new RegExp(CROSS_REF_SOURCE, 'g');
    let wm: RegExpExecArray | null = whole.exec(text);
    while (wm !== null) {
      const prefix: string = wm[1];
      const key: string = wm[2];
      if (!prefix.includes('《') && !prefix.includes('》') && !byRaw.has(key) && !reported.has(key)) {
        reported.add(key);
        warnings.push(new StructureWarning('悬空引用',
          `正文引用了 ${key}，但锚点表中不存在该条款（可能已被删除或漏粘贴）`));
      }
      wm = whole.exec(text);
    }

    if (scanned) {
      warnings.push(new StructureWarning('扫描件',
        '识别置信度低：仅输出条款地图与风险意见，不出修订稿；锚点表须人工校对后方可进入内容层'));
    }
  }

  // Term dictionary from definition clauses; a clause that uses a known alias
  // of a defined term is word drift.
  private static buildTerms(anchors: ClauseAnchor[], warnings: StructureWarning[]): Map<string, string> {
    const dictionary: Map<string, string> = new Map<string, string>();
    for (const a of anchors) {
      const re: RegExp = /([一-龥]{2,10})\s*(?:是指|系指|指)/g;
      let m: RegExpExecArray | null = re.exec(a.text);
      while (m !== null) {
        if (!dictionary.has(m[1])) {
          dictionary.set(m[1], m[1]);
        }
        m = re.exec(a.text);
      }
    }
    for (const a of anchors) {
      for (const pair of TERM_ALIASES) {
        if (a.text.includes(pair[0]) && dictionary.has(pair[1])) {
          warnings.push(new StructureWarning('术语漂移',
            `${a.anchorId} 使用「${pair[0]}」，而定义条款用「${pair[1]}」，属用词漂移`, a.anchorId));
          break;
        }
      }
    }
    return dictionary;
  }

  private static detect(line: string): DetectedNumber | undefined {
    const patterns: RegExp[] = [RE_CHAPTER, RE_ARTICLE, RE_PARAGRAPH, RE_ITEM];
    for (let i: number = 0; i < patterns.length; i++) {
      const m: RegExpExecArray | null = patterns[i].exec(line);
      if (m !== null) {
        return new DetectedNumber(LEVELS[i], m[0].trim());
      }
    }
    const dotted: RegExpExecArray | null = RE_DOTTED.exec(line);
    if (dotted !== null) {
      const rawNo: string = dotted[0].trim();
      const depth: number = rawNo.split('.').length;
      return new DetectedNumber(LEVELS[Math.min(depth, 3)], rawNo);
    }
    return undefined;
  }

  // Only a line that is almost nothing but an amount or a date is filtered:
  // clause text often contains them ("试用期工资为约定工资的70%"), and losing
  // a clause is worse than a misread.
  private static isNegative(line: string): boolean {
    const s: string = line.trim();
    if (RE_ATTACH_LIST.test(s)) {
      return true;
    }
    if (!RE_ARTICLE.test(s)) {
      if (RE_LAW_CITE.test(s) || RE_SELF_REF.test(s)) {
        return true;
      }
      if (s.length <= 30 && RE_MONEY_DATE.test(s)) {
        const rest: string = ContractStructure.stripChars(s.replace(new RegExp(RE_MONEY_DATE_SOURCE, 'g'), ''));
        if (rest.length <= 8) {
          return true;
        }
      }
    }
    return false;
  }

  private static extractNum(rawNo: string): number {
    const digits: RegExpExecArray | null = /(\d+)/.exec(rawNo);
    if (digits !== null) {
      return parseInt(digits[1], 10);
    }
    const chinese: RegExpExecArray | null = new RegExp(`[${CN_DIGITS}]+`).exec(rawNo);
    return chinese !== null ? ContractStructure.cn2int(chinese[0]) : -1;
  }

  private static stripChars(s: string): string {
    let start: number = 0;
    let end: number = s.length;
    while (start < end && STRIP_CHARS.includes(s.charAt(start))) {
      start++;
    }
    while (end > start && STRIP_CHARS.includes(s.charAt(end - 1))) {
      end--;
    }
    return s.substring(start, end);
  }

  private static pad(n: number): string {
    return n < 10 ? '0' + n.toString() : n.toString();
  }
}
