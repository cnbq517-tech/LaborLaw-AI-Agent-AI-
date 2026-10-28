import { ContractStructure } from './ContractStructure';
import { MINIMUM_WAGE_AS_OF, MINIMUM_WAGE_SOURCE, MinimumWages, ProvinceWage } from './MinimumWages';
import {
  BARGAIN_MUST,
  BARGAIN_SHOULD,
  BARGAIN_YIELD,
  ClauseAnchor,
  ContractTerms,
  FACT_NO,
  FACT_UNKNOWN,
  FactSheet,
  Finding,
  LEVEL_ARTICLE,
  LEVEL_ITEM,
  LEVEL_PARAGRAPH,
  NATURE_BARGAIN,
  NATURE_FLAW,
  NATURE_INVALID,
  NATURE_MISSING,
  NATURE_PENDING,
  RuleResult,
  SEVERITIES,
  SEVERITY_HIGH,
  SEVERITY_MEDIUM,
  SEVERITY_NOTE,
  SEVERITY_REDLINE,
  TERM_OPEN,
  TERM_TASK,
  TERM_UNKNOWN,
  WHOLE_CONTRACT
} from './ContractTypes';

// Deterministic red-line rules, ported from the desktop client's
// contract_review/rules.py, with these changes:
// - Findings bind to the clause where the pattern matched, not to the first
//   clause containing a keyword.
// - Patterns that describe something the employer must not do are skipped
//   when the contract states it as a prohibition ("甲方不得收取押金").
// - Contract term and probation are read from the text; the user's facts only
//   override them. A three-year contract allows six months of probation.
// - Durations in months, 百分之N and full-width digits are recognized.
// - Each rule only waits on the facts it depends on.
// - R019 (marriage and childbirth restrictions), R020 (fines), R021 (overtime
//   on the minimum wage), R022 (minimum social insurance base) and R023 (wage
//   below the local minimum wage) are new.
// - Absence treated as resignation (R015a) waits on the workplace rules
//   instead of being called void.

// 《劳动合同法》第十七条 required clauses.
const REQUIRED_CLAUSES: string[][] = [
  ['用人单位名称', '用人单位', '甲方', '公司名称', '公司（'],
  ['劳动者姓名', '劳动者', '乙方', '姓名'],
  ['劳动合同期限', '合同期限', '固定期限', '无固定期限', '以完成一定工作'],
  ['工作内容和工作地点', '工作内容', '工作地点', '工作岗位', '岗位'],
  ['工作时间和休息休假', '工时', '工作时间', '休息', '休假', '年休假'],
  ['劳动报酬', '劳动报酬', '工资', '薪资', '月薪'],
  ['社会保险', '社会保险', '社保', '五险一金', '公积金'],
  ['劳动保护与职业危害防护', '劳动保护', '职业危害', '安全生产', '职业病']
];

const NUM: string = '[0-9零〇一二三四五六七八九十两半]+';
// Gaps inside a pattern stay within one sentence. TIGHT also stops at commas,
// for patterns where the next phrase is often a separate statement
// ("缴纳社会保险，不得以现金补贴代替社保").
const GAP: string = '[^。；\\n]';
const TIGHT: string = '[^，,。；\\n]';
const NEGATORS: RegExp = /(不得|不能|不应|禁止|严禁|不准|不会|不予|无权|不再|杜绝|不允许)/;
const PENDING_CITY: string = '适用城市';
const PENDING_CONFIDENTIAL: string = '是否涉密';
const PENDING_TERM: string = '合同期限';

class Wage {
  amount: number;
  at: number;
  len: number;
  probation: boolean;

  constructor(amount: number, at: number, len: number, probation: boolean) {
    this.amount = amount;
    this.at = at;
    this.len = len;
    this.probation = probation;
  }
}

class Rule {
  ruleId: string;
  severity: string;
  nature: string;
  bargain: string;
  topic: string;
  confidence: number;
  lawRefs: string[];

  constructor(ruleId: string, severity: string, nature: string, bargain: string, topic: string,
    confidence: number, lawRefs: string[]) {
    this.ruleId = ruleId;
    this.severity = severity;
    this.nature = nature;
    this.bargain = bargain;
    this.topic = topic;
    this.confidence = confidence;
    this.lawRefs = lawRefs;
  }
}

export class ContractRules {
  static run(anchors: ClauseAnchor[], text: string, facts: FactSheet): RuleResult {
    const t: string = ContractStructure.normalize(text);
    const out: Finding[] = [];
    const terms: ContractTerms = ContractRules.extractTerms(t);

    // R014 required clauses missing (第十七条).
    for (const entry of REQUIRED_CLAUSES) {
      if (!entry.slice(1).some((key: string) => t.includes(key))) {
        const f: Finding = ContractRules.add(out, new Rule('R014', SEVERITY_HIGH, NATURE_MISSING, BARGAIN_MUST,
          '必备条款', 0.9, ['《劳动合同法》第十七条']), WHOLE_CONTRACT, `全文未发现「${entry[0]}」的相关约定`,
          `补充「${entry[0]}」条款；必备条款缺失会影响合同成立与举证`);
        f.trace = [`全文没有找到「${entry.slice(1).join('」「')}」等表述`,
          `《劳动合同法》第十七条：劳动合同应当具备「${entry[0]}」`, '结论：缺少法定必备条款'];
      }
    }

    ContractRules.probation(out, anchors, t, facts, terms);

    // R002 probation agreed on its own.
    ContractRules.onHits(out, anchors, t, `试用期${GAP}{0,10}(单独|另行)${GAP}{0,6}(约定|签订)|单独的试用期`, false,
      new Rule('R002', SEVERITY_REDLINE, NATURE_INVALID, BARGAIN_MUST, '试用期', 0.85, ['《劳动合同法》第十九条第四款']),
      '试用期不能单独约定；单独约定的试用期不成立，该期限视为劳动合同期限',
      '将试用期并入正式合同期限条款中约定', true);

    ContractRules.probationPay(out, anchors, t);
    ContractRules.penalties(out, anchors, t);
    ContractRules.nonCompete(out, anchors, t, facts);

    // R010 waiving social insurance or taking it as cash.
    ContractRules.onHits(out, anchors, t,
      `(自愿)?放弃${TIGHT}{0,8}(社保|社会保险)|(社保|社会保险)${TIGHT}{0,6}(折现|补贴|现金)|以${TIGHT}{0,6}补贴${TIGHT}{0,6}代替${TIGHT}{0,6}(社保|社会保险)`,
      true, new Rule('R010', SEVERITY_REDLINE, NATURE_INVALID, BARGAIN_MUST, '社会保险', 0.95,
        ['《劳动法》第七十二条', '《社会保险法》第五十八条']),
      '「自愿放弃社保 / 社保折现」约定一律无效，住房公积金亦为法定义务', '删除该约定，依法足额缴纳社保与公积金', true);

    // R011 overtime pay folded into a fixed wage.
    const r011: Finding | undefined = ContractRules.onHits(out, anchors, t,
      `(已包含|包含|已含|含)${TIGHT}{0,10}加班费|加班费${TIGHT}{0,6}(已计入|并入)`, true,
      new Rule('R011', SEVERITY_HIGH, NATURE_INVALID, BARGAIN_MUST, '工时加班', 0.85,
        ['《劳动合同法》第二十六条', '《工资支付暂行规定》第十三条']),
      '将加班费打包进固定工资，属免除法定责任、排除劳动者权利的无效约定',
      '拆分固定工资与加班费，明确加班费计算基数不低于正常工作时间工资', true);
    if (r011 !== undefined) {
      r011.evidenceGap = '加班审批记录、考勤记录、工资条';
    }

    // R018 comprehensive or flexible working hours without approval.
    if (!ContractRules.has(t, `(经|已)${GAP}{0,10}(审批|批准|备案|行政许可)`)) {
      const r018: Finding | undefined = ContractRules.onHits(out, anchors, t, '综合计算工时|不定时工作制|不定时工时', false,
        new Rule('R018', SEVERITY_MEDIUM, NATURE_PENDING, BARGAIN_SHOULD, '工时加班', 0.7,
          ['《关于企业实行不定时工作制和综合计算工时工作制的审批办法》第七条']),
        '约定综合计算工时或不定时工作制，但未见行政审批/备案表述，否则按标准工时认定',
        '补充「已依法办理审批/备案」表述并留存批文', true);
      if (r018 !== undefined) {
        r018.pendingFacts = [PENDING_CITY, '是否已办理审批'];
      }
    }

    // R012 unlimited unilateral changes of workplace or job.
    ContractRules.onHits(out, anchors, t,
      `工作地点为[^。；\\n]{0,16}(全国|公司经营所在地|公司所在)|公司安排的其他工作|随时${GAP}{0,6}(调整|调动)${GAP}{0,6}(岗位|地点)`,
      true, new Rule('R012', SEVERITY_MEDIUM, NATURE_BARGAIN, BARGAIN_SHOULD, '工作地点', 0.8, ['《劳动合同法》第三十五条']),
      '单方无限调岗调地授权：字面合法，实际可能被用来变相逼退，对劳动者不利',
      '加入合理性限制：限定城市/区域、需协商一致、赋予书面异议期与拒绝权', true);

    // R013 deposits, guarantees, withheld documents (第九条).
    ContractRules.onHits(out, anchors, t,
      `押金|保证金|扣押${TIGHT}{0,8}(证件|身份证|毕业证)|(提供|交纳|缴纳)${TIGHT}{0,4}担保`, true,
      new Rule('R013', SEVERITY_REDLINE, NATURE_INVALID, BARGAIN_MUST, '用工禁止', 0.95, ['《劳动合同法》第九条']),
      '用人单位不得扣押劳动者证件、要求担保或以其他名义收取财物',
      '删除并要求退还；可改为合法的物品交接与赔偿责任约定', false);

    // R015 waived severance or work-injury liability.
    ContractRules.onHits(out, anchors, t,
      `主动离职${GAP}{0,8}(无|不)${GAP}{0,6}补偿|(放弃|不要求)${GAP}{0,6}经济补偿|工伤${GAP}{0,6}(自负|自行承担)`,
      true, new Rule('R015', SEVERITY_REDLINE, NATURE_INVALID, BARGAIN_MUST, '解除终止', 0.9,
        ['《劳动合同法》第四十六条', '《工伤保险条例》第二条']),
      '约定放弃法定经济补偿或工伤责任由劳动者自负，属免除用人单位法定责任的无效约定',
      '删除该条款；经济补偿和工伤待遇按法律规定执行', true);

    // R015a absence treated as resignation. Lawful when the workplace rules
    // that define it are, so this waits on those rules instead of calling it
    // void.
    const r015a: Finding | undefined = ContractRules.onHits(out, anchors, t,
      `(自动离职|连续旷工|旷工)${GAP}{0,10}(视为|按)${GAP}{0,8}(解除|辞退|自动离职|离职)`, true,
      new Rule('R015a', SEVERITY_MEDIUM, NATURE_PENDING, BARGAIN_SHOULD, '解除终止', 0.7,
        ['《劳动合同法》第三十九条', '《劳动合同法》第四条']),
      '把旷工约定为自动离职或解除：只有规章制度经民主程序制定并公示，且旷工确属严重违纪时，单位才能据此解除；否则属违法解除',
      '确认规章制度对旷工的定义是否合法、是否已公示；请假或因故缺勤的保留请假记录和沟通记录', true);
    if (r015a !== undefined) {
      r015a.pendingFacts = ['规章制度是否经民主程序并公示'];
      r015a.evidenceGap = '请假申请、考勤记录、与单位的沟通记录';
    }

    ContractRules.onHits(out, anchors, t,
      `不${GAP}{0,4}(办理|完成)${GAP}{0,6}交接${GAP}{0,10}(扣发|不发|扣除)${GAP}{0,6}工资`, false,
      new Rule('R015b', SEVERITY_MEDIUM, NATURE_FLAW, BARGAIN_SHOULD, '解除终止', 0.8, ['《工资支付暂行规定》第十五条']),
      '离职交接义务可以约定，但不得约定不交接即扣发全部工资', '改为「因未交接造成实际损失的，依法另行主张赔偿」', true);

    // R017 workplace rules without a democratic procedure.
    if (!ContractRules.has(t, '民主程序|职工代表大会|全体职工讨论|公示|签收|告知')) {
      const r017: Finding | undefined = ContractRules.onHits(out, anchors, t, '员工手册|规章制度|公司制度', false,
        new Rule('R017', SEVERITY_MEDIUM, NATURE_PENDING, BARGAIN_SHOULD, '规章制度', 0.75, ['《劳动合同法》第四条']),
        '规章制度作为附件或解除依据，但未体现民主程序与公示签收；未经民主程序与公示的制度不能作为解除依据',
        '补充民主程序与公示签收表述，并同步留存证据', true);
      if (r017 !== undefined) {
        r017.pendingFacts = ['是否实际履行民主程序'];
        r017.evidenceGap = '民主程序会议纪要、公示照片、员工签收记录';
      }
    }

    // R016 commercial arbitration or court instead of labor arbitration.
    ContractRules.onHits(out, anchors, t,
      `(提交|提请|申请)${GAP}{0,12}(商事仲裁|仲裁委员会${GAP}{0,8}仲裁)|直接向(人民)?法院(起诉|提起诉讼)`, false,
      new Rule('R016', SEVERITY_MEDIUM, NATURE_FLAW, BARGAIN_SHOULD, '争议解决', 0.8,
        ['《劳动争议调解仲裁法》第五条', '《劳动争议调解仲裁法》第二十七条']),
      '劳动争议仲裁前置，约定商事仲裁或直接起诉通常无法实现；注意一年仲裁时效',
      '改为「依法向有管辖权的劳动争议仲裁委员会申请仲裁，对裁决不服的向人民法院起诉」', true);

    // R020 fines. Employers have no power to fine; deducting them from wages
    // can be withholding pay.
    ContractRules.onHits(out, anchors, t, '罚款|罚金|扣罚|处以罚', true,
      new Rule('R020', SEVERITY_MEDIUM, NATURE_FLAW, BARGAIN_SHOULD, '劳动报酬', 0.75, ['《劳动法》第五十条', '《工资支付暂行规定》第十五条']),
      '用人单位没有罚款的法定权力；以罚款名义从工资中扣钱，可能构成克扣工资',
      '删除罚款约定；违纪处理应依照经民主程序制定并公示的规章制度进行', true);

    // R021 overtime pay computed on the minimum wage.
    const r021: Finding | undefined = ContractRules.onHits(out, anchors, t,
      `加班(费|工资)${GAP}{0,12}(以|按)${GAP}{0,8}最低工资`, false,
      new Rule('R021', SEVERITY_MEDIUM, NATURE_PENDING, BARGAIN_SHOULD, '工时加班', 0.7, ['《劳动法》第四十四条']),
      '加班费应以正常工作时间工资为基数计算；约定按最低工资计算通常会低于法定标准，各地对约定基数的认可口径不一',
      '将加班费计算基数改为本人正常工作时间工资', true);
    if (r021 !== undefined) {
      r021.pendingFacts = [PENDING_CITY];
    }

    // R022 social insurance paid on the minimum base.
    ContractRules.onHits(out, anchors, t,
      `(社保|社会保险|五险一金)${GAP}{0,10}(按|以)${GAP}{0,8}(最低|下限)${GAP}{0,4}(缴费)?基数`, false,
      new Rule('R022', SEVERITY_MEDIUM, NATURE_FLAW, BARGAIN_SHOULD, '社会保险', 0.75, ['《社会保险法》第十二条']),
      '社会保险应按本人工资缴纳；约定一律按最低基数缴纳，会减少日后的养老金、失业金和工伤待遇',
      '要求按实际工资申报缴费基数，并定期查询个人社保缴费记录', true);

    // R019 restrictions on marriage or childbirth.
    ContractRules.onHits(out, anchors, t,
      `(乙方|员工|劳动者|女职工)${GAP}{0,10}(不得|不准|禁止|不允许)[^，,。；\\n因]{0,4}(结婚|怀孕|生育)|(结婚|怀孕|生育)[^。；\\n]{0,10}(视为|按)${GAP}{0,8}(自动离职|解除|辞退|违纪)`,
      false, new Rule('R019', SEVERITY_REDLINE, NATURE_INVALID, BARGAIN_MUST, '女职工保护', 0.9, ['《妇女权益保障法》第四十四条', '《妇女权益保障法》第四十八条']),
      '劳动合同不得规定限制女职工结婚、生育的内容，以结婚、怀孕、生育为由解除合同也属违法',
      '删除该条款', false);

    ContractRules.minimumWage(out, anchors, t, facts);

    ContractRules.settlePending(out, facts, terms);
    const ordered: Finding[] = out.sort((a: Finding, b: Finding) =>
      SEVERITIES.indexOf(a.severity) - SEVERITIES.indexOf(b.severity));
    ordered.forEach((f: Finding, i: number) => {
      f.findingId = 'F' + (i < 9 ? '00' : i < 99 ? '0' : '') + (i + 1).toString();
    });
    return new RuleResult(ordered, terms);
  }

  // Reads the contract term and probation from the text. Sentences about
  // non-compete, service periods and confidentiality have their own periods
  // and are skipped. Line breaks do not end a sentence: text recognized from a
  // photo wraps mid-sentence.
  static extractTerms(t: string): ContractTerms {
    const terms: ContractTerms = new ContractTerms();
    const sentences: RegExp = /[^。；]+/g;
    let s: RegExpExecArray | null = sentences.exec(t);
    while (s !== null) {
      const sentence: string = s[0];
      const at: number = s.index;
      if (!/竞业|服务期|保密|培训/.test(sentence)) {
        if (terms.termMonths === TERM_UNKNOWN) {
          ContractRules.readTerm(sentence, at, terms);
        }
        if (terms.probationDays < 0) {
          ContractRules.readProbation(sentence, at, terms);
        }
      }
      s = sentences.exec(t);
    }
    return terms;
  }

  private static readTerm(sentence: string, at: number, terms: ContractTerms): void {
    if (!sentence.includes('合同') && !sentence.includes('期限')) {
      return;
    }
    const open: RegExpExecArray | null = /无固定期限(劳动)?合同/.exec(sentence);
    if (open !== null && !/[□☐]\s*无固定期限/.test(sentence)) {
      terms.termMonths = TERM_OPEN;
      terms.termAt = at + open.index;
      return;
    }
    const task: RegExpExecArray | null = /以完成一定工作(任务)?为期限/.exec(sentence);
    if (task !== null && !/[□☐]\s*以完成/.test(sentence)) {
      terms.termMonths = TERM_TASK;
      terms.termAt = at + task.index;
      return;
    }
    const range: RegExpExecArray | null = ContractRules.dateRange(sentence);
    const probation: number = sentence.indexOf('试用');
    if (range !== null && (probation < 0 || probation > range.index)) {
      terms.termMonths = Math.round(ContractRules.rangeDays(range) / 30.44);
      terms.termAt = at + range.index;
      return;
    }
    const re: RegExp = new RegExp(`期限[为是：:]?\\s*(${NUM})\\s*(个月|年)`, 'g');
    let m: RegExpExecArray | null = re.exec(sentence);
    while (m !== null) {
      if (m.index < 2 || sentence.substring(m.index - 2, m.index) !== '试用') {
        const amount: number = ContractRules.amount(m[1]);
        if (amount > 0) {
          terms.termMonths = Math.round(m[2] === '年' ? amount * 12 : amount);
          terms.termAt = at + m.index;
          return;
        }
      }
      m = re.exec(sentence);
    }
  }

  // Tries each 试用期 in the sentence: a clause heading such as 第二条 试用期
  // can come before the one with the period.
  private static readProbation(sentence: string, at: number, terms: ContractTerms): void {
    let p: number = sentence.indexOf('试用期');
    while (p >= 0) {
      const rest: string = sentence.substring(p);
      const range: RegExpExecArray | null = ContractRules.dateRange(rest);
      if (range !== null && range.index < 12) {
        terms.probationDays = ContractRules.rangeDays(range);
        terms.probationAt = at + p;
        terms.probationEnd = at + p + range.index + range[0].length;
        return;
      }
      const m: RegExpExecArray | null =
        new RegExp(`^试用期${GAP}{0,6}?(${NUM})\\s*(个月|个自然月|月|天|日|周|个星期)`).exec(rest);
      const amount: number = m !== null ? ContractRules.amount(m[1]) : -1;
      if (m !== null && amount > 0) {
        const unit: string = m[2];
        terms.probationDays = Math.round(unit === '天' || unit === '日' ? amount :
          unit === '周' || unit === '个星期' ? amount * 7 : amount * 30);
        terms.probationAt = at + p;
        terms.probationEnd = at + p + m[0].length;
        return;
      }
      p = sentence.indexOf('试用期', p + 3);
    }
  }

  // R001 probation longer than the legal cap for the contract term (第十九条).
  private static probation(out: Finding[], anchors: ClauseAnchor[], t: string, facts: FactSheet,
    terms: ContractTerms): void {
    const term: number = facts.termMonths !== TERM_UNKNOWN ? facts.termMonths : terms.termMonths;
    const days: number = facts.probationMonths >= 0 ? facts.probationMonths * 30 : terms.probationDays;
    if (days <= 0) {
      return;
    }
    const anchorId: string = terms.probationAt >= 0 ? ContractRules.anchorAt(anchors, terms.probationAt) :
      ContractRules.anchorFor(anchors, ['试用期']);
    const label: string = days % 30 === 0 ? `${days / 30}个月` : `${days}天`;
    if (term === TERM_UNKNOWN) {
      const f: Finding = ContractRules.add(out, new Rule('R001', SEVERITY_MEDIUM, NATURE_PENDING, BARGAIN_SHOULD,
        '试用期', 0.5, ['《劳动合同法》第十九条']), anchorId, '缺少合同期限，无法校验试用期上限', '');
      f.pendingFacts = [PENDING_TERM];
      return;
    }
    const cap: number = ContractRules.probationCap(term);
    // Months are compared as 31 days so 二个月 and 60 天 both pass a two-month cap.
    if (days > cap * 31) {
      const termLabel: string = term === TERM_OPEN ? '无固定期限' :
        term === TERM_TASK ? '以完成一定工作任务为期限' : `合同期限${term}个月`;
      const reason: string = cap === 0 ? `${termLabel}的劳动合同不得约定试用期，实际约定${label}` :
        `${termLabel}，法定试用期上限为${cap}个月，实际约定${label}，超出部分无效`;
      const f: Finding = ContractRules.add(out, new Rule('R001', SEVERITY_REDLINE, NATURE_INVALID, BARGAIN_MUST,
        '试用期', 0.95, ['《劳动合同法》第十九条']), anchorId, reason,
        cap === 0 ? '删除试用期约定' : `将试用期改为不超过${cap}个月；超出部分视为已履行正式期`);
      if (terms.probationAt >= 0) {
        f.start = terms.probationAt;
        f.end = terms.probationEnd;
      }
      const band: string = cap === 0 ? '以完成一定工作任务为期限或不满三个月' : cap === 1 ? '三个月以上不满一年' :
        cap === 2 ? '一年以上不满三年' : '三年以上或无固定期限';
      f.trace = [
        `合同期限：${term === TERM_OPEN ? '无固定期限' : term === TERM_TASK ? '以完成一定工作任务为期限' : term.toString() + ' 个月'}` +
          (facts.termMonths !== TERM_UNKNOWN ? '（你填写的）' : '（从正文识别）'),
        `试用期：${label}` + (facts.probationMonths >= 0 ? '（你填写的）' : '（从正文识别）'),
        cap === 0 ? `《劳动合同法》第十九条：${band}的，不得约定试用期` :
          `《劳动合同法》第十九条：${band}的，试用期不得超过 ${cap} 个月`,
        `结论：${label} 超过 ${cap} 个月，超出部分无效`];
    }
  }

  // 三个月以上不满一年: 1; 一年以上不满三年: 2; 三年以上固定期限和无固定期限:
  // 6; 以完成一定工作任务为期限或不满三个月: none. 以上 includes the number itself.
  static probationCap(termMonths: number): number {
    if (termMonths === TERM_TASK || termMonths < 3) {
      return 0;
    }
    if (termMonths < 12) {
      return 1;
    }
    if (termMonths < 36) {
      return 2;
    }
    return 6;
  }

  // R003 probation pay below 80% (第二十条).
  private static probationPay(out: Finding[], anchors: ClauseAnchor[], t: string): void {
    const re: RegExp = new RegExp(
      `试用期${GAP}{0,8}?工资${GAP}{0,20}?(?:(\\d{2,3})\\s*%|百分之([一二三四五六七八九十]+)|([五六七八九])折)`, 'g');
    let m: RegExpExecArray | null = re.exec(t);
    while (m !== null) {
      const pct: number = m[1] !== undefined ? parseInt(m[1], 10) :
        m[2] !== undefined ? ContractStructure.cn2int(m[2]) : ContractStructure.cn2int(m[3] ?? '') * 10;
      if (pct > 0 && pct < 80) {
        const anchorId: string = ContractRules.anchorAt(anchors, m.index);
        const f: Finding = ContractRules.add(out, new Rule('R003', SEVERITY_REDLINE, NATURE_INVALID, BARGAIN_MUST,
          '试用期', 0.9, ['《劳动合同法》第二十条']), anchorId,
          `试用期工资为约定工资的${pct}%，低于法定的80%下限`,
          '试用期工资不低于本单位同岗位最低档工资或约定工资的80%，且不低于当地最低工资');
        ContractRules.mark(f, m.index, m.index + m[0].length);
        f.trace = [`在${ContractRules.label(anchors, anchorId)}找到「${ContractRules.excerpt(t, f)}」`,
          '《劳动合同法》第二十条：试用期工资不得低于约定工资的 80%', `结论：${pct}% 低于 80%，无效`];
        return;
      }
      m = re.exec(t);
    }
  }

  // R023 monthly wage, or probation wage, below the local minimum wage
  // (《劳动法》第四十八条). Provinces publish tiers by county; below the lowest
  // tier is certain, between the tiers depends on where the job is.
  private static minimumWage(out: Finding[], anchors: ClauseAnchor[], t: string, facts: FactSheet): void {
    const wages: Wage[] = ContractRules.monthlyWages(t);
    const base: Wage | undefined = wages.find((w: Wage) => !w.probation);
    const pct: RegExpExecArray | null = new RegExp(
      `试用期${GAP}{0,8}?工资${GAP}{0,20}?(\\d{2,3})\\s*%`).exec(t);
    if (base !== undefined && pct !== null && !wages.some((w: Wage) => w.probation)) {
      wages.push(new Wage(Math.round(base.amount * parseInt(pct[1], 10) / 100), pct.index, pct[0].length, true));
    }
    const province: ProvinceWage | undefined = MinimumWages.forPlace(facts.city);
    const note: string = `（最低工资数据来自${MINIMUM_WAGE_SOURCE}，截至 ${MINIMUM_WAGE_AS_OF}，以当地人社部门公布为准）`;
    const reported: string[] = [];
    for (const w of wages) {
      const key: string = w.probation ? 'probation' : 'base';
      if (reported.includes(key)) {
        continue;
      }
      const found: number = out.length;
      const what: string = w.probation ? `试用期工资约${w.amount}元/月` : `约定月工资${w.amount}元`;
      const refs: string[] = w.probation ? ['《劳动合同法》第二十条', '《劳动法》第四十八条'] : ['《劳动法》第四十八条'];
      const anchorId: string = ContractRules.anchorAt(anchors, w.at);
      if (province !== undefined) {
        const range: string = province.tiers.length > 1 ?
          `分 ${province.tiers.length} 档（${province.lowest()}–${province.highest()}元）` : `为 ${province.highest()}元`;
        if (w.amount < province.lowest()) {
          ContractRules.add(out, new Rule('R023', SEVERITY_REDLINE, NATURE_INVALID, BARGAIN_MUST, '最低工资', 0.9, refs),
            anchorId, `${what}，低于${province.province}最低工资标准（${province.effective}起执行，${range}）${note}`,
            '工资不得低于当地最低工资标准；要求按当地标准补足，并保留工资条和银行流水');
          reported.push(key);
        } else if (w.amount < province.highest()) {
          const f: Finding = ContractRules.add(out, new Rule('R023', SEVERITY_MEDIUM, NATURE_PENDING, BARGAIN_SHOULD,
            '最低工资', 0.6, refs), anchorId,
            `${what}。${province.province}最低工资${range}，是否达标取决于工作地所在区县适用的档次${note}`,
            '查询工作地所在区县适用的最低工资档次；低于该档次的，可以要求补足');
          f.pendingFacts = ['所在区县档次'];
          reported.push(key);
        }
      } else if (w.amount < MinimumWages.nationalLowest()) {
        ContractRules.add(out, new Rule('R023', SEVERITY_REDLINE, NATURE_INVALID, BARGAIN_MUST, '最低工资', 0.85, refs),
          anchorId, `${what}，低于全国各省份最低工资的最低一档（${MinimumWages.nationalLowest()}元）${note}`,
          '工资不得低于当地最低工资标准；要求按当地标准补足');
        reported.push(key);
      } else if (w.amount < MinimumWages.nationalHighest()) {
        const f: Finding = ContractRules.add(out, new Rule('R023', SEVERITY_NOTE, NATURE_PENDING, BARGAIN_SHOULD,
          '最低工资', 0.5, refs), anchorId, `${what}，是否达到当地最低工资标准取决于工作城市${note}`,
          '填写工作城市后可自动比对');
        f.pendingFacts = [PENDING_CITY];
        reported.push(key);
      }
      if (out.length > found) {
        const f: Finding = out[out.length - 1];
        ContractRules.mark(f, w.at, w.at + w.len);
        const where: string = ContractRules.label(anchors, f.anchorId);
        const steps: string[] = w.probation && base !== undefined && pct !== null && w.at === pct.index ?
          [`在${where}找到「${ContractRules.excerpt(t, f)}」`, `${base.amount} 元 × ${pct[1]}% ≈ ${w.amount} 元`] :
          [`在${where}找到月工资 ${w.amount} 元`];
        steps.push(province !== undefined ?
          `${province.province}最低工资：${province.tiers.join(' / ')} 元（${province.effective} 起执行）` :
          `未填工作城市，按全国各省最低一档 ${MinimumWages.nationalLowest()} 元、最高一档 ${MinimumWages.nationalHighest()} 元比较`);
        steps.push(`结论：${f.nature === NATURE_INVALID ? '低于标准' : '需要确认'}（${f.severity}）`);
        f.trace = steps;
      }
    }
  }

  // Monthly wage figures (月工资、月薪、基本工资……) with their offsets;
  // probation wages are marked. Overtime pay, allowances and penalties are not
  // wages here.
  static monthlyWages(t: string): Wage[] {
    const re: RegExp = new RegExp(
      `(?:月工资|月薪|月基本工资|基本工资|工资标准|每月工资|月收入|工资)(?:为|是|按|：|:)?([^。；\\n\\d]{0,12}?)` +
        `(\\d{1,3}(?:,\\d{3})+|\\d+)(?:\\.(\\d{1,2}))?\\s*(万)?\\s*元`, 'g');
    const out: Wage[] = [];
    let m: RegExpExecArray | null = re.exec(t);
    while (m !== null) {
      const gap: string = m[1];
      let amount: number = parseFloat(m[2].replace(/,/g, '') + (m[3] !== undefined ? '.' + m[3] : ''));
      if (m[4] !== undefined) {
        amount *= 10000;
      }
      if (!/违约|补贴|奖金|补偿|加班|押金|罚|赔|日|小时|年/.test(gap) && amount >= 300 && amount <= 1000000) {
        let start: number = m.index;
        while (start > 0 && !'。；\n'.includes(t.charAt(start - 1))) {
          start--;
        }
        out.push(new Wage(Math.round(amount), m.index, m[0].length,
          t.substring(start, m.index + m[0].length).includes('试用')));
      }
      m = re.exec(t);
    }
    return out;
  }

  // R005 penalties paid by the worker (第二十五条), judged clause by clause:
  // a non-compete or training clause elsewhere does not make another penalty
  // lawful. R006 hukou or housing benefits tied to a service period.
  private static penalties(out: Finding[], anchors: ClauseAnchor[], t: string): void {
    if (!t.includes('违约金')) {
      return;
    }
    const clauses: ClauseAnchor[] = anchors.filter((a: ClauseAnchor) => a.text.includes('违约金') &&
      (a.level === LEVEL_ARTICLE || a.level === LEVEL_PARAGRAPH || a.level === LEVEL_ITEM));
    const segments: string[] = clauses.length > 0 ? clauses.map((a: ClauseAnchor) => a.text) : [t];
    segments.forEach((segment: string, i: number) => {
      if (/专项培训|专业技术培训|服务期|培训费/.test(segment) || /竞业限制|竞业/.test(segment)) {
        return;
      }
      const anchorId: string = clauses.length > 0 ? clauses[i].anchorId : ContractRules.anchorAt(anchors, t.indexOf('违约金'));
      const f: Finding = ContractRules.add(out, new Rule('R005', SEVERITY_REDLINE, NATURE_INVALID, BARGAIN_MUST,
        '违约金', 0.9, ['《劳动合同法》第二十五条']), anchorId,
        '约定由劳动者承担违约金，且不属于「专项培训服务期」或「竞业限制」两种法定情形，原则上无效',
        '删除该违约金条款；确需约束的，改签专项培训服务期协议并留存培训费凭证');
      f.evidenceGap = '若主张服务期，需专项培训发票与付款凭证';
      ContractRules.markSentence(f, t, '违约金', clauses.length > 0 ? clauses[i] : undefined);
      f.trace = [`在${ContractRules.label(anchors, anchorId)}找到「${ContractRules.excerpt(t, f)}」`,
        '《劳动合同法》第二十五条：只有专项培训服务期和竞业限制可以约定由劳动者承担违约金',
        '本条不属于这两种情形，结论：原则上无效'];
    });
    const r006: Finding | undefined = ContractRules.onHits(out, anchors, t, '落户|户口|住房补贴|安家费', false,
      new Rule('R006', SEVERITY_MEDIUM, NATURE_PENDING, BARGAIN_SHOULD, '违约金', 0.6, ['《劳动合同法》第二十五条']),
      '落户指标/住房补贴/安家费绑定服务期的违约金，各地裁审口径不一：有的按违约金无效处理，有的按不当得利或实际损失返还处理',
      '核查当地最新判例后再定性，不得一刀切标注无效', true);
    if (r006 !== undefined) {
      r006.pendingFacts = [PENDING_CITY];
    }
  }

  // R007 term over two years, R008 no monthly compensation (第二十三、二十四条),
  // R009 people who cannot be bound (司法解释（二）第十三条). Judged on the
  // non-compete clauses themselves.
  private static nonCompete(out: Finding[], anchors: ClauseAnchor[], t: string, facts: FactSheet): void {
    if (!t.includes('竞业')) {
      return;
    }
    let clauses: ClauseAnchor[] = anchors.filter((a: ClauseAnchor) => a.text.includes('竞业') &&
      (a.level === LEVEL_ARTICLE || a.level === LEVEL_PARAGRAPH || a.level === LEVEL_ITEM));
    if (clauses.length === 0) {
      const window: RegExpExecArray | null = /竞业限制[^。；]{0,120}/.exec(t);
      if (window === null) {
        return;
      }
      clauses = [new ClauseAnchor(ContractRules.anchorAt(anchors, window.index), '', LEVEL_ARTICLE, window[0], 0, 0, '')];
    }
    const first: string = clauses[0].anchorId;
    const duration: RegExp = new RegExp(
      `(?:期限为?|离职后|离职之日起|终止劳动合同后|解除劳动合同后)${GAP}{0,6}?(${NUM})\\s*(年|个月)|(${NUM})\\s*(年|个月)\\s*(?:内|以内)`, 'g');
    for (const clause of clauses) {
      // Scan the clause in the contract text itself, so hits have offsets.
      const from: number = clause.end > clause.start ? clause.start : t.indexOf(clause.text);
      const segment: string = clause.end > clause.start ? t.substring(clause.start, clause.end) : clause.text;
      duration.lastIndex = 0;
      let m: RegExpExecArray | null = duration.exec(segment);
      while (m !== null) {
        const amount: number = ContractRules.amount(m[1] ?? m[3] ?? '');
        const months: number = (m[2] ?? m[4]) === '年' ? amount * 12 : amount;
        if (months > 24) {
          const f: Finding = ContractRules.add(out, new Rule('R007', SEVERITY_REDLINE, NATURE_INVALID, BARGAIN_MUST,
            '竞业限制', 0.95, ['《劳动合同法》第二十四条']), clause.anchorId,
            `竞业限制期限约定${months % 12 === 0 ? (months / 12).toString() + '年' : months.toString() + '个月'}，超过法定二年上限，超出部分无效`,
            '期限改为不超过二年；范围、地域、期限应与所接触秘密相适应');
          if (from >= 0) {
            ContractRules.mark(f, from + m.index, from + m.index + m[0].length);
          }
          f.trace = [`在${ContractRules.label(anchors, clause.anchorId)}找到「${m[0]}」，即 ${months} 个月`,
            '《劳动合同法》第二十四条：竞业限制期限不得超过二年', `结论：${months} 个月超过 24 个月，超出部分无效`];
          break;
        }
        m = duration.exec(segment);
      }
    }
    const all: string = clauses.map((a: ClauseAnchor) => a.text).join('\n');
    if (!/经济补偿|补偿金|按月.{0,4}补偿/.test(all)) {
      if (/(另行|另|单独)(签订|签署|约定)[^。；\n]{0,8}竞业/.test(all)) {
        const f: Finding = ContractRules.add(out, new Rule('R008', SEVERITY_MEDIUM, NATURE_PENDING, BARGAIN_SHOULD,
          '竞业限制', 0.7, ['《劳动合同法》第二十三条']), first,
          '竞业限制约定另行签订协议，需核对协议中是否约定离职后按月支付经济补偿', '签署竞业限制协议时确认按月支付经济补偿及标准');
        f.pendingFacts = ['竞业限制协议内容'];
        ContractRules.markSentence(f, t, '竞业', clauses[0]);
        ContractRules.genericTrace(f, t, anchors);
      } else {
        const f: Finding = ContractRules.add(out, new Rule('R008', SEVERITY_HIGH, NATURE_FLAW, BARGAIN_MUST, '竞业限制',
          0.9, ['《劳动合同法》第二十三条']), first, '竞业限制未约定离职后按月支付经济补偿',
          '补充离职后在竞业限制期限内按月支付经济补偿的约定，并写明补偿标准');
        f.evidenceGap = '需留存补偿支付凭证；单位三个月未付补偿的，劳动者可请求解除竞业限制约定';
        ContractRules.markSentence(f, t, '竞业', clauses[0]);
        f.trace = [`在${ContractRules.label(anchors, first)}找到竞业限制约定，但没有找到「经济补偿」「补偿金」等字样`,
          '《劳动合同法》第二十三条：竞业限制须在离职后按月给予劳动者经济补偿', '结论：缺少补偿约定'];
      }
    }
    if (facts.confidential === FACT_NO || /(前台|保安|保洁|普工|操作工|实习生)/.test(facts.position) ||
      ContractRules.has(t, '(前台|保安|保洁|普工|操作工|实习生).{0,20}竞业')) {
      const f: Finding = ContractRules.add(out, new Rule('R009', SEVERITY_NOTE, NATURE_PENDING, BARGAIN_YIELD,
        '竞业限制', 0.7, ['《劳动争议司法解释（二）》第十三条']), first,
        '非高管、非高级技术人员且未接触商业秘密的人员签署竞业限制，条款对其不生效（部分无效/对人不生效，并非整条自始无效）',
        '限定适用主体为高管、高技及负有保密义务人员；其余人员可删除');
      ContractRules.markSentence(f, t, '竞业', clauses[0]);
      f.trace = [facts.confidential === FACT_NO ? '你填写的事实：不接触商业秘密' :
        `岗位为${facts.position.length > 0 ? facts.position : '普通岗位'}，不属于高管或高级技术人员`,
        '司法解释（二）第十三条：未接触商业秘密的劳动者，可以请求确认竞业限制不生效', '结论：条款对你可能不生效'];
    }
  }

  // Drops pending facts the user has answered.
  private static settlePending(out: Finding[], facts: FactSheet, terms: ContractTerms): void {
    const known: string[] = [];
    if (facts.city.length > 0) {
      known.push(PENDING_CITY);
    }
    if (facts.confidential !== FACT_UNKNOWN) {
      known.push(PENDING_CONFIDENTIAL);
    }
    if (facts.termMonths !== TERM_UNKNOWN || terms.termMonths !== TERM_UNKNOWN) {
      known.push(PENDING_TERM);
    }
    out.forEach((f: Finding) => {
      f.pendingFacts = f.pendingFacts.filter((fact: string) => !known.includes(fact));
    });
  }

  // One finding per clause the pattern hits. negatable skips hits stated as
  // prohibitions; firstOnly keeps only the first hit.
  private static onHits(out: Finding[], anchors: ClauseAnchor[], t: string, source: string, negatable: boolean,
    rule: Rule, reason: string, suggestion: string, firstOnly: boolean): Finding | undefined {
    const re: RegExp = new RegExp(source, 'g');
    const seen: string[] = [];
    let first: Finding | undefined = undefined;
    let m: RegExpExecArray | null = re.exec(t);
    while (m !== null) {
      if (m[0].length === 0) {
        re.lastIndex++;
      } else if (!negatable || !ContractRules.negated(t, m.index)) {
        const anchorId: string = ContractRules.anchorAt(anchors, m.index);
        if (!seen.includes(anchorId)) {
          seen.push(anchorId);
          const f: Finding = ContractRules.add(out, rule, anchorId, reason, suggestion);
          ContractRules.mark(f, m.index, m.index + m[0].length);
          ContractRules.genericTrace(f, t, anchors);
          if (first === undefined) {
            first = f;
          }
          if (firstOnly) {
            return first;
          }
        }
      }
      m = re.exec(t);
    }
    return first;
  }

  // A hit is a prohibition when a negating word comes shortly before it in the
  // same sentence, or it directly follows 不/未/无/非 ("不包含加班费"). Words
  // inside the hit do not count: "主动离职不予补偿" is the violation itself.
  private static negated(t: string, index: number): boolean {
    let start: number = index;
    const limit: number = Math.max(0, index - 12);
    while (start > limit && !'。；\n'.includes(t.charAt(start - 1))) {
      start--;
    }
    if (NEGATORS.test(t.substring(start, index))) {
      return true;
    }
    return index > 0 && '不未无非'.includes(t.charAt(index - 1));
  }

  private static mark(f: Finding, start: number, end: number): void {
    if (start >= 0 && end > start) {
      f.start = start;
      f.end = end;
    }
  }

  // Marks the sentence of the clause that contains the keyword.
  private static markSentence(f: Finding, t: string, keyword: string, clause: ClauseAnchor | undefined): void {
    const lo: number = clause !== undefined && clause.end > clause.start ? clause.start : 0;
    const hi: number = clause !== undefined && clause.end > clause.start ? clause.end : t.length;
    // Skip the heading (第八条 违约金): the body is the agreement.
    let at: number = t.indexOf(keyword, lo);
    const firstBreak: number = t.indexOf('\n', lo);
    if (at >= 0 && firstBreak >= 0 && at < firstBreak && firstBreak + 1 < hi) {
      const later: number = t.indexOf(keyword, firstBreak);
      // Only the heading names it: mark the first sentence of the clause body.
      at = later >= 0 && later < hi ? later : firstBreak + 1;
    }
    if (at < 0 || at >= hi) {
      return;
    }
    let start: number = at;
    while (start > lo && !'。；\n'.includes(t.charAt(start - 1))) {
      start--;
    }
    let end: number = at;
    while (end < hi && !'。；\n'.includes(t.charAt(end))) {
      end++;
    }
    ContractRules.mark(f, start, end);
  }

  // Three steps for pattern rules: what matched, the law, the conclusion.
  private static genericTrace(f: Finding, t: string, anchors: ClauseAnchor[]): void {
    f.trace = [
      f.start >= 0 ? `在${ContractRules.label(anchors, f.anchorId)}找到「${ContractRules.excerpt(t, f)}」` :
        `在${ContractRules.label(anchors, f.anchorId)}找到相关约定`,
      '对照' + f.lawRefs.join('、'),
      `结论：${f.nature === NATURE_PENDING ? '需要确认' : f.nature}（${f.severity}）`];
  }

  private static label(anchors: ClauseAnchor[], anchorId: string): string {
    const a: ClauseAnchor | undefined = anchors.find((x: ClauseAnchor) => x.anchorId === anchorId);
    return a !== undefined && a.rawNo.length > 0 ? a.rawNo : '合同中';
  }

  private static excerpt(t: string, f: Finding): string {
    const text: string = t.substring(f.start, f.end).replace(/\s+/g, '');
    return text.length > 30 ? text.substring(0, 30) + '…' : text;
  }

  // The clause containing an offset: the last anchor starting at or before it.
  static anchorAt(anchors: ClauseAnchor[], index: number): string {
    let found: string = WHOLE_CONTRACT;
    for (const a of anchors) {
      if (a.start > index) {
        break;
      }
      found = a.anchorId;
    }
    return found;
  }

  // Keyword lookup for findings without a match offset. The earlier keywords
  // are the more specific ones.
  private static anchorFor(anchors: ClauseAnchor[], keywords: string[]): string {
    for (const k of keywords) {
      for (const a of anchors) {
        if ((a.level === LEVEL_ARTICLE || a.level === LEVEL_PARAGRAPH) && a.text.includes(k)) {
          return a.anchorId;
        }
      }
    }
    return WHOLE_CONTRACT;
  }

  private static add(out: Finding[], rule: Rule, anchorId: string, reason: string, suggestion: string): Finding {
    const f: Finding = new Finding();
    f.ruleId = rule.ruleId;
    f.anchorId = anchorId;
    f.severity = rule.severity;
    f.nature = rule.nature;
    f.bargain = rule.bargain;
    f.topic = rule.topic;
    f.confidence = rule.confidence;
    f.lawRefs = rule.lawRefs.slice();
    f.reason = reason;
    f.suggestion = suggestion;
    out.push(f);
    return f;
  }

  private static has(t: string, source: string): boolean {
    return new RegExp(source).test(t);
  }

  // 三, 12, 半, 一年半 → 3, 12, 0.5, 1.5.
  private static amount(text: string): number {
    if (!text.includes('半')) {
      return ContractStructure.cn2int(text);
    }
    const whole: string = text.replace('半', '');
    const base: number = whole.length > 0 ? ContractStructure.cn2int(whole) : 0;
    return base < 0 ? -1 : base + 0.5;
  }

  private static dateRange(text: string): RegExpExecArray | null {
    return /(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日[^至到]{0,6}(?:至|到)\s*(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日/
      .exec(text);
  }

  // Inclusive day count of a matched date range.
  private static rangeDays(m: RegExpExecArray): number {
    const from: number = Date.UTC(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10));
    const to: number = Date.UTC(parseInt(m[4], 10), parseInt(m[5], 10) - 1, parseInt(m[6], 10));
    return Math.round((to - from) / 86400000) + 1;
  }
}
