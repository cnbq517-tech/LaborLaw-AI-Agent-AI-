import { ExtractedField } from '../models/Evidence';

// Rule-based understanding of recognized evidence text: categories, table
// rows rebuilt from OCR line positions, dossier fields, and the 证据清单
// section of AI answers. Pure functions so they can be tested off device.

export const CAT_WAGE: string = '工资';
export const CAT_CONTRACT: string = '合同';
export const CAT_DISMISSAL: string = '解除通知';
export const CAT_ATTENDANCE: string = '考勤';
export const CAT_SOCIAL: string = '社保';
export const CAT_CHAT: string = '聊天';
export const CAT_OTHER: string = '其他';
export const EVIDENCE_CATEGORIES: string[] =
  [CAT_WAGE, CAT_CONTRACT, CAT_ATTENDANCE, CAT_CHAT, CAT_DISMISSAL, CAT_SOCIAL, CAT_OTHER];

// Dossier field indexes, matching the order of the 卷宗 inputs.
export const FIELD_LOCATION: number = 0;
export const FIELD_COMPANY: number = 1;
export const FIELD_SALARY: number = 2;
export const FIELD_TIMELINE: number = 3;

class CategoryRule {
  category: string;
  keywords: string[];
  // At least one of these must appear: words that only show up in the
  // document itself, not in text that merely talks about it (an AI answer
  // mentioning 劳动合同 is not a contract).
  anchors: string[];

  constructor(category: string, keywords: string[], anchors: string[] = []) {
    this.category = category;
    this.keywords = keywords;
    this.anchors = anchors;
  }
}

// Words that identify a document type in OCR text.
const DOCUMENT_RULES: CategoryRule[] = [
  new CategoryRule(CAT_WAGE, ['工资条', '应发', '实发', '基本工资', '岗位津贴', '代发工资', '工资单'],
    ['应发', '实发', '工资条', '工资单']),
  new CategoryRule(CAT_CONTRACT, ['劳动合同', '甲方', '乙方', '合同期限', '试用期', '用人单位'],
    ['甲方', '乙方', '劳动合同书', '合同编号']),
  new CategoryRule(CAT_DISMISSAL, ['解除劳动合同', '解除通知', '辞退', '终止劳动合同', '即日起'],
    ['解除劳动合同通知', '解除通知书', '辞退通知', '终止劳动合同通知']),
  new CategoryRule(CAT_ATTENDANCE, ['打卡', '考勤', '出勤', '上班', '下班', '签到'], ['打卡', '考勤', '签到']),
  new CategoryRule(CAT_SOCIAL, ['社会保险', '社保', '缴费基数', '参保'], ['缴费基数', '参保证明', '社会保险费'])
];

// Words in a 证据清单 item that point to an evidence category.
const CHECKLIST_RULES: CategoryRule[] = [
  new CategoryRule(CAT_CONTRACT, ['劳动合同', '劳动关系', '工牌', '入职', '合同']),
  new CategoryRule(CAT_WAGE, ['工资', '流水', '薪', '报酬', '工资条']),
  new CategoryRule(CAT_ATTENDANCE, ['考勤', '打卡', '排班', '加班', '门禁', '工时']),
  new CategoryRule(CAT_CHAT, ['聊天', '微信', '短信', '邮件', '沟通', '录音']),
  new CategoryRule(CAT_DISMISSAL, ['解除', '辞退', '通知书', '开除']),
  new CategoryRule(CAT_SOCIAL, ['社保', '社会保险', '参保', '缴费'])
];

export class LineBox {
  text: string;
  left: number;
  centerY: number;
  height: number;

  constructor(text: string, left: number, centerY: number, height: number) {
    this.text = text;
    this.left = left;
    this.centerY = centerY;
    this.height = height;
  }
}

export class ChecklistItem {
  name: string = '';
  detail: string = '';
  // Evidence categories that satisfy this item; empty when none applies.
  categories: string[] = [];
  terms: string[] = [];
}

export class EvidenceExtractor {
  // Groups OCR lines whose vertical centers are within half a line height
  // into one row, then orders each row left to right. This pairs table
  // labels with their values (应发合计 8,500.00元), which plain OCR text splits.
  static rows(lines: LineBox[]): string[] {
    const sorted: LineBox[] = lines.filter((line: LineBox) => line.text.trim().length > 0)
      .sort((a: LineBox, b: LineBox) => a.centerY - b.centerY);
    const rows: LineBox[][] = [];
    sorted.forEach((line: LineBox) => {
      const row: LineBox[] | undefined = rows.length > 0 ? rows[rows.length - 1] : undefined;
      if (row !== undefined) {
        const anchor: LineBox = row[0];
        const tolerance: number = Math.max(anchor.height, line.height) * 0.5;
        if (Math.abs(line.centerY - anchor.centerY) <= tolerance) {
          row.push(line);
          return;
        }
      }
      rows.push([line]);
    });
    return rows.map((row: LineBox[]) => row.sort((a: LineBox, b: LineBox) => a.left - b.left)
      .map((line: LineBox) => line.text.trim()).join('  '));
  }

  // Highest-scoring document category, or '' when no rule matches.
  static classify(text: string): string {
    return EvidenceExtractor.bestCategory(text, DOCUMENT_RULES);
  }

  static checklistCategories(text: string): string[] {
    return CHECKLIST_RULES.filter((rule: CategoryRule) =>
      rule.keywords.some((keyword: string) => text.includes(keyword))).map((rule: CategoryRule) => rule.category);
  }

  // Dossier values found in the rows. `places` and `dates` are entities from
  // Natural Language Kit, used when no rule matches.
  static extract(rows: string[], category: string, places: string[], dates: string[]): ExtractedField[] {
    const text: string = rows.join('\n');
    const fields: ExtractedField[] = [];
    const add = (field: number, value: string, source: string): void => {
      if (value.length > 0 && !fields.some((item: ExtractedField) => item.field === field)) {
        const item: ExtractedField = new ExtractedField();
        item.field = field;
        item.value = value;
        item.source = source;
        fields.push(item);
      }
    };

    const employer: RegExpMatchArray | null =
      text.match(/(?:甲方|用人单位)[^：:\n]{0,8}[：:]\s*([一-龥A-Za-z（）()]{2,30}?(?:有限责任公司|股份有限公司|有限公司|公司|集团|厂))/);
    if (employer !== null) {
      add(FIELD_COMPANY, employer[1], '「甲方（用人单位）」');
    } else {
      for (let index: number = 0; index < Math.min(rows.length, 4); index++) {
        const header: RegExpMatchArray | null =
          rows[index].match(/([一-龥A-Za-z（）()]{2,30}?(?:有限责任公司|股份有限公司|有限公司))/);
        if (header !== null) {
          add(FIELD_COMPANY, header[1], '抬头');
          break;
        }
      }
    }

    // Severance is based on wages payable, so 应发 wins over 实发.
    for (let index: number = 0; index < rows.length; index++) {
      const row: string = rows[index];
      if (/应发(?:合计|工资|金额)?/.test(row)) {
        const amount: string = EvidenceExtractor.amountAfter(row, /应发(?:合计|工资|金额)?/);
        if (amount.length > 0) {
          add(FIELD_SALARY, amount, '「' + row.replace(/\s+/g, ' ').substring(0, 14) + '」');
          break;
        }
      }
    }
    const monthly: RegExpMatchArray | null =
      text.match(/(?:月工资|月薪|月平均工资)[^\d\n]{0,8}([\d,，]+(?:\.\d+)?)\s*元/);
    if (monthly !== null) {
      add(FIELD_SALARY, EvidenceExtractor.formatAmount(monthly[1]), '「月工资」条款');
    }

    const workplace: RegExpMatchArray | null =
      text.match(/工作地点[^\n]{0,6}?([一-龥]{2,8}?(?:省|市|自治区))(?:[一-龥]{2,6}?(?:市|区|县))?/);
    if (workplace !== null) {
      add(FIELD_LOCATION, workplace[0].replace(/^工作地点[^一-龥]*(?:为|在|是)?/, '')
        .replace(/^为/, ''), '「工作地点」');
    } else if (places.length > 0) {
      add(FIELD_LOCATION, places[0], '识别出的地点');
    }

    const start: RegExpMatchArray | null =
      text.match(/(?:期限)?自\s*(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日\s*起/);
    if (start !== null) {
      add(FIELD_TIMELINE, start[1] + '年' + start[2] + '月' + start[3] + '日 入职（合同起始）', '「合同期限」');
    }
    if (category === CAT_WAGE) {
      const month: RegExpMatchArray | null = text.match(/(\d{4})\s*年\s*(\d{1,2})\s*月(?!\s*\d{1,2}\s*日)/);
      if (month !== null) {
        add(FIELD_TIMELINE, month[1] + '年' + month[2] + '月 工资', '「发放月份」');
      }
    }
    if (category === CAT_CHAT || category === CAT_ATTENDANCE) {
      const day: RegExpMatchArray | null = text.match(/(?:(\d{4})\s*年\s*)?(\d{1,2})\s*月\s*(\d{1,2})\s*日/);
      if (day !== null) {
        add(FIELD_TIMELINE, (day[1] !== undefined ? day[1] + '年' : '') + day[2] + '月' + day[3] + '日 '
          + (category === CAT_CHAT ? '聊天记录' : '考勤记录'), '材料上的日期');
      }
    }
    if (dates.length > 0) {
      add(FIELD_TIMELINE, dates[0], '识别出的日期');
    }
    return fields;
  }

  // Items of the 证据清单 section of an AI answer, with search terms.
  static checklist(answer: string): ChecklistItem[] {
    const lines: string[] = answer.split('\n');
    let start: number = -1;
    for (let index: number = 0; index < lines.length; index++) {
      const line: string = lines[index].trim();
      if (line.includes('证据清单') && line.length <= 16) {
        start = index + 1;
        break;
      }
    }
    if (start < 0) {
      return [];
    }
    const items: ChecklistItem[] = [];
    for (let index: number = start; index < lines.length; index++) {
      const line: string = lines[index].trim();
      if (/^[一二三四五六七八九十]+[、.．]/.test(line)) {
        break;
      }
      const numbered: RegExpMatchArray | null = line.match(/^\d+\s*[.、．)）]\s*(.+)$/);
      if (numbered === null) {
        continue;
      }
      const content: string = numbered[1].replace(/\[K\d+\]/g, '').trim();
      const colon: number = content.search(/[：:]/);
      const item: ChecklistItem = new ChecklistItem();
      item.name = (colon > 0 ? content.substring(0, colon) : content.substring(0, 12)).trim();
      item.detail = colon > 0 ? content.substring(colon + 1).trim() : content;
      // The item name decides the category. The detail only helps when the name
      // is generic, and chat words there usually describe how something was
      // reported (向单位报告的微信), not a chat record, so they are ignored.
      item.categories = EvidenceExtractor.checklistCategories(item.name);
      if (item.categories.length === 0) {
        item.categories = EvidenceExtractor.checklistCategories(item.detail)
          .filter((category: string) => category !== CAT_CHAT);
      }
      const parts: string[] = item.detail.split(/[、，,；;。和及或]/)
        .map((part: string) => part.trim().replace(/等(?:材料|证据)?$/, ''))
        .filter((part: string) => part.length >= 2 && part.length <= 8);
      item.terms = [item.name].concat(parts.slice(0, 6));
      items.push(item);
    }
    return items;
  }

  static formatAmount(raw: string): string {
    const value: number = Number(raw.replace(/[,，]/g, ''));
    if (!Number.isFinite(value) || value <= 0) {
      return '';
    }
    const fixed: string = Number.isInteger(value) ? value.toString() : value.toFixed(2).replace(/\.?0+$/, '');
    const parts: string[] = fixed.split('.');
    const grouped: string = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    return (parts.length > 1 ? grouped + '.' + parts[1] : grouped) + ' 元';
  }

  private static amountAfter(row: string, label: RegExp): string {
    const match: RegExpMatchArray | null = row.match(label);
    if (match === null || match.index === undefined) {
      return '';
    }
    const after: string = row.substring(match.index + match[0].length);
    const amount: RegExpMatchArray | null = after.match(/(\d[\d,，]*(?:\.\d+)?)/);
    return amount !== null ? EvidenceExtractor.formatAmount(amount[1]) : '';
  }

  private static bestCategory(text: string, rules: CategoryRule[]): string {
    let best: string = '';
    let bestScore: number = 0;
    rules.forEach((rule: CategoryRule) => {
      if (rule.anchors.length > 0 && !rule.anchors.some((anchor: string) => text.includes(anchor))) {
        return;
      }
      let score: number = 0;
      rule.keywords.forEach((keyword: string) => {
        if (text.includes(keyword)) {
          score += keyword.length >= 3 ? 2 : 1;
        }
      });
      if (score > bestScore) {
        best = rule.category;
        bestScore = score;
      }
    });
    return best;
  }
}
