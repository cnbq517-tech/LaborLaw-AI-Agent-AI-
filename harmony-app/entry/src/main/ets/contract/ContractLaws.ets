// Maps the short law names used in contract review findings to the titles of
// the bundled legal index, so every reference can be opened and checked
// against the original text. tools/harmony/contract-rules checks that each
// rule reference resolves to an article in the index, except those listed in
// NOT_IN_INDEX.

export class LawLocation {
  title: string;
  // 第二十五条; empty when the reference names the whole regulation.
  article: string;
  label: string;

  constructor(title: string, article: string, label: string) {
    this.title = title;
    this.article = article;
    this.label = label;
  }
}

const TITLES: string[][] = [
  ['劳动合同法', '中华人民共和国劳动合同法（2012修正）'],
  ['劳动法', '中华人民共和国劳动法（2018修正）'],
  ['社会保险法', '中华人民共和国社会保险法（2018修正）'],
  ['劳动争议调解仲裁法', '中华人民共和国劳动争议调解仲裁法'],
  ['劳动争议司法解释（一）', '最高人民法院关于审理劳动争议案件适用法律问题的解释（一）'],
  ['劳动争议司法解释（二）', '最高人民法院关于审理劳动争议案件适用法律问题的解释（二）'],
  ['工伤保险条例', '工伤保险条例（2010修订）'],
  ['妇女权益保障法', '中华人民共和国妇女权益保障法（2022修订）'],
  ['工资支付暂行规定', '工资支付暂行规定'],
  ['关于企业实行不定时工作制和综合计算工时工作制的审批办法', '关于企业实行不定时工作制和综合计算工时工作制的审批办法']
];

// Cited by rules but not in the bundled index; shown as 本地库未收录. Empty
// since tools/kb_builder/supplements.json added the missing texts.
export const NOT_IN_INDEX: string[] = [];

export class ContractLaws {
  // 《劳动合同法》第十九条第四款 → 中华人民共和国劳动合同法（2012修正）, 第十九条.
  static resolve(ref: string): LawLocation | undefined {
    const m: RegExpExecArray | null = /《([^》]+)》\s*(第[零〇一二三四五六七八九十百千两0-9]+条)?/.exec(ref);
    if (m === null) {
      return undefined;
    }
    const name: string = m[1];
    const article: string = m[2] ?? '';
    for (const pair of TITLES) {
      if (pair[0] === name || pair[1] === name) {
        return new LawLocation(pair[1], article, ref);
      }
    }
    return undefined;
  }

  static isKnownMissing(ref: string): boolean {
    const m: RegExpExecArray | null = /《([^》]+)》/.exec(ref);
    return m !== null && NOT_IN_INDEX.includes(m[1]);
  }
}
