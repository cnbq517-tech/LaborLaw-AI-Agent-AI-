// Replaces personal information with placeholders before clause text is sent
// to the model. Clause wording is what gets reviewed; who signed it is not
// needed, so names, ID numbers, phone numbers, bank cards and addresses never
// leave the phone.

export class MaskResult {
  text: string;
  // Placeholder → how many values it replaced, for the 将发送的内容 preview.
  counts: Map<string, number>;

  constructor(text: string, counts: Map<string, number>) {
    this.text = text;
    this.counts = counts;
  }
}

class MaskRule {
  placeholder: string;
  pattern: RegExp;
  // Keep group 1 (a label such as 姓名：) and replace the rest.
  keepLabel: boolean;

  constructor(placeholder: string, pattern: RegExp, keepLabel: boolean) {
    this.placeholder = placeholder;
    this.pattern = pattern;
    this.keepLabel = keepLabel;
  }
}

const RULES: MaskRule[] = [
  new MaskRule('【身份证号】', /\d{17}[\dXx]|\d{15}(?!\d)/g, false),
  new MaskRule('【银行卡号】', /(?<!\d)\d{16,19}(?!\d)/g, false),
  new MaskRule('【手机号】', /(?<!\d)1[3-9]\d{9}(?!\d)/g, false),
  new MaskRule('【电话】', /(?<!\d)0\d{2,3}-?\d{7,8}(?!\d)/g, false),
  new MaskRule('【邮箱】', /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, false),
  // Labelled fields: the label stays so the model still sees the structure.
  new MaskRule('【姓名】', /((?:乙方|劳动者|员工|姓名|法定代表人|委托代理人|联系人)(?:（[^）]{0,6}）)?\s*[:：]\s*)[一-龥·]{2,5}(?=[\s，,。；;（(]|$)/gm, true),
  new MaskRule('【住址】', /((?:住址|住所|家庭住址|现住址|户籍地址|联系地址|通讯地址)\s*[:：]\s*)[^\n，,。；;]{2,60}/g, true),
  new MaskRule('【证件号】', /((?:身份证号码?|证件号码?|护照号码?)\s*[:：]\s*)[A-Za-z0-9]{6,20}/g, true)
];

export class ContractPrivacy {
  static mask(text: string): MaskResult {
    let out: string = text;
    const counts: Map<string, number> = new Map<string, number>();
    for (const rule of RULES) {
      let n: number = 0;
      let rebuilt: string = '';
      let cursor: number = 0;
      rule.pattern.lastIndex = 0;
      let m: RegExpExecArray | null = rule.pattern.exec(out);
      while (m !== null) {
        rebuilt += out.substring(cursor, m.index) + (rule.keepLabel ? m[1] : '') + rule.placeholder;
        cursor = m.index + m[0].length;
        n++;
        m = rule.pattern.exec(out);
      }
      if (n > 0) {
        out = rebuilt + out.substring(cursor);
        counts.set(rule.placeholder, (counts.get(rule.placeholder) ?? 0) + n);
      }
    }
    return new MaskResult(out, counts);
  }
}
