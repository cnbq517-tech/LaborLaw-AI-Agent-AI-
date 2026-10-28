// Contract review rule cases. Each case lists the exact findings expected as
// ruleId@anchorId. Compliant cases expect none, so they catch false positives;
// the others catch misses. R014 (missing required clauses) is ignored for
// snippets that are not whole contracts.

import { readFileSync } from 'node:fs';
import { AI_RULE_ID, ContractAi, ReviewLaw } from './ContractAi.ts';
import { ContractDocument, DocLine, DocSegment } from './ContractDocument.ts';
import { ContractLaws } from './ContractLaws.ts';
import { ContractPrivacy } from './ContractPrivacy.ts';
import { ContractRules } from './ContractRules.ts';
import { ContractStructure } from './ContractStructure.ts';
import { SAMPLE_CONTRACT_CITY, SAMPLE_CONTRACT_TEXT } from './SampleContract.ts';
import { FactSheet, Finding, StructureAudit, TERM_OPEN, TERM_TASK } from './ContractTypes.ts';

interface Case {
  name: string;
  text: string;
  expect: string[];
  wholeContract?: boolean;
  facts?: Partial<FactSheet>;
  warnings?: Record<string, number>;
}

// The desktop client's selftest contract, with its two table rows as
// python-docx reads them.
const SELFTEST: string = [
  '劳动合同书',
  '甲方（用人单位）：某某科技有限公司',
  '乙方（劳动者）：张三',
  '第一条 合同期限', '本合同为固定期限劳动合同，期限一年。',
  '第二条 试用期', '试用期三个月，试用期工资为约定工资的70%。',
  '第三条 工作内容和工作地点', '乙方担任操作工，工作地点为公司经营所在地及全国，并服从公司安排的其他工作。',
  '第四条 工作时间和休息休假', '实行标准工时制，每日工作8小时，每周工作40小时。',
  '第五条 劳动报酬', '月薪5000元，其中已包含全部加班费。乙方自愿放弃社会保险，公司按月发放社保补贴500元。',
  '第六条 违约金', '乙方提前解除劳动合同的，应向甲方支付违约金20000元。',
  '第七条 竞业限制', '乙方离职后三年内不得从事同类业务，竞业限制范围为公司经营区域。',
  '第八条 规章制度', '乙方应遵守公司员工手册及各项规章制度。',
  '第九条 争议解决', '双方发生争议，提交某某仲裁委员会仲裁。',
  '第十条 其他', '乙方入职需交纳押金1000元，详见第十一条。',
  '根据《劳动合同法》第二十五条之规定，双方确认上述条款。',
  '第十一条 保密义务 ｜ 乙方应对在职期间知悉的商业秘密承担保密义务。',
  '第十二条 培训服务期 ｜ 甲方提供专项培训的，服务期五年，违约金为培训费的两倍。'
].join('\n');

const CASES: Case[] = [
  {
    name: '桌面版自检合同',
    text: SELFTEST,
    wholeContract: true,
    expect: ['R014@C00', 'R001@C02', 'R003@C02', 'R005@C06', 'R007@C07', 'R008@C07', 'R010@C05', 'R011@C05',
      'R012@C03', 'R013@C10', 'R017@C08', 'R016@C09'],
    warnings: {}
  },
  {
    // The built-in sample on the 合同 page: each red line it is meant to show.
    name: '内置示例合同',
    text: SAMPLE_CONTRACT_TEXT,
    wholeContract: true,
    facts: { city: SAMPLE_CONTRACT_CITY },
    expect: ['R001@C01', 'R003@C04', 'R005@C08', 'R007@C09', 'R010@C05', 'R013@C07', 'R019@C10', 'R023@C04',
      'R008@C09', 'R011@C04', 'R018@C03', 'R012@C02', 'R015a@C06', 'R017@C13', 'R016@C12', 'R020@C06', 'R023@C04'],
    warnings: {}
  },
  // Probation (第十九条).
  { name: '三年合同 + 六个月试用期（合法）', text: '第一条 合同期限\n本合同期限三年。\n第二条 试用期\n试用期六个月。', expect: [] },
  { name: '一年合同 + 三个月试用期', text: '第一条 合同期限\n本合同期限一年。\n第二条 试用期\n试用期三个月。', expect: ['R001@C02'] },
  { name: '一年合同 + 90 天试用期', text: '第一条 合同期限\n本合同期限一年。\n第二条 试用期\n试用期90天。', expect: ['R001@C02'] },
  { name: '一年合同 + 60 天试用期（合法）', text: '第一条 合同期限\n本合同期限一年。\n第二条 试用期\n试用期60天。', expect: [] },
  { name: '同一句里的期限和试用期', text: '第一条 合同期限\n本合同期限为一年半，其中试用期三个月。', expect: ['R001@C01'] },
  { name: '一年半合同 + 两个月试用期（合法）', text: '第一条 合同期限\n本合同期限为一年半，其中试用期两个月。', expect: [] },
  {
    name: '日期区间算期限（合法）',
    text: '第一条 合同期限\n本合同自2024年1月1日起至2024年12月31日止。\n第二条 试用期\n试用期两个月。', expect: []
  },
  {
    name: '识别时断行的日期区间（合法）',
    text: '第一条 合同期限\n本合同为固定期限劳动合同,期限自 2024年3月1日起\n至2027年2月28日止,其中试用期3个月。', expect: []
  },
  {
    name: '试用期的日期区间不算合同期限',
    text: '第一条 试用期\n试用期自2024年3月1日至2024年8月31日。', expect: ['R001@C01']
  },
  { name: '无固定期限 + 六个月（合法）', text: '第一条 合同期限\n本合同为无固定期限劳动合同。\n第二条 试用期\n试用期六个月。', expect: [] },
  { name: '以完成工作任务为期限 + 试用期', text: '第一条 合同期限\n本合同以完成一定工作任务为期限。\n第二条 试用期\n试用期一个月。', expect: ['R001@C02'] },
  { name: '用户填的期限覆盖正文', text: '第一条 试用期\n试用期六个月。', facts: { termMonths: 12 }, expect: ['R001@C01'] },
  { name: '只有试用期，没有期限', text: '第一条 试用期\n试用期两个月。', expect: ['R001@C01'] },
  { name: '竞业期限不算合同期限', text: '第一条 竞业限制\n竞业限制期限为二年，甲方按月支付经济补偿。\n第二条 试用期\n试用期六个月。', expect: ['R001@C02'] },
  // Probation pay (第二十条).
  { name: '全角百分比', text: '第一条 试用期\n试用期工资为约定工资的７０％。', expect: ['R003@C01'] },
  { name: '百分之七十', text: '第一条 试用期\n试用期间工资按约定工资的百分之七十发放。', expect: ['R003@C01'] },
  { name: '试用期工资八成（合法）', text: '第一条 试用期\n试用期工资为约定工资的80%。', expect: [] },
  // Restated prohibitions are not violations.
  {
    name: '复述法律的禁止性规定（合法）',
    text: '第一条 甲方义务\n甲方不得扣押乙方身份证等证件，不得向乙方收取押金，不得要求乙方提供担保。\n第二条 社会保险\n甲方依法为乙方缴纳社会保险，不得以现金补贴代替社保。',
    expect: []
  },
  { name: '不扣证件但收押金', text: '第一条 入职\n甲方不扣押证件，乙方入职需交纳押金500元。', expect: ['R013@C01'] },
  { name: '不包含加班费（合法）', text: '第一条 劳动报酬\n月工资6000元，不包含加班费，加班费另行计算。', expect: [] },
  // Clause-level binding.
  {
    name: '培训条款不豁免别处的违约金',
    text: '第一条 培训\n甲方提供专项培训，服务期三年。\n第二条 违约金\n乙方提前离职须支付违约金5万元。', expect: ['R005@C02']
  },
  {
    name: '风险挂到命中的条款',
    text: '第一条 劳动报酬\n月工资6000元。\n第二条 社会保险\n乙方自愿放弃社保。', expect: ['R010@C02']
  },
  // Non-compete (第二十三、二十四条).
  { name: '竞业 36 个月', text: '第一条 竞业限制\n乙方离职后36个月内不得到竞争对手处工作，甲方按月支付经济补偿。', expect: ['R007@C01'] },
  { name: '竞业二年（合法）', text: '第一条 竞业限制\n乙方离职后二年内不得到竞争对手处工作，甲方按月支付经济补偿。', expect: [] },
  {
    name: '竞业补偿另行签订',
    text: '第一条 竞业限制\n乙方离职后一年内不得到竞争对手处工作，具体另行签订竞业限制协议。', expect: ['R008@C01']
  },
  {
    name: '违约金倍数不当竞业期限',
    text: '第一条 竞业限制\n乙方离职后一年内不得到竞争对手处工作，甲方按月支付经济补偿；违反的，支付相当于36个月补偿的违约金。',
    expect: []
  },
  { name: '前台签竞业', text: '第一条 竞业限制\n乙方离职后一年内不得到竞争对手处工作，甲方按月支付经济补偿。', facts: { position: '前台' }, expect: ['R009@C01'] },
  // Marriage and childbirth (new rule).
  { name: '婚育限制', text: '第一条 特别约定\n乙方在合同期内不得结婚生育，否则视为严重违纪。', expect: ['R019@C01'] },
  { name: '怀孕视为自动离职', text: '第一条 特别约定\n女职工怀孕的，视为自动离职。', expect: ['R019@C01'] },
  { name: '女职工保护的复述（合法）', text: '第一条 女职工保护\n甲方不得因乙方结婚、怀孕、生育降低其工资。', expect: [] },
  // Other rules, so every law reference they cite is checked.
  { name: '单独约定试用期', text: '第一条 试用期\n双方的试用期另行单独约定。', expect: ['R002@C01'] },
  { name: '落户违约金', text: '第一条 服务期\n甲方为乙方办理落户，乙方服务未满五年离职的，支付违约金10万元。', expect: ['R006@C01'] },
  { name: '旷工视为解除（待确认）', text: '第一条 解除\n乙方连续旷工3日的，视为乙方自动解除劳动合同。', expect: ['R015a@C01'] },
  { name: '放弃经济补偿', text: '第一条 解除\n乙方主动离职的，甲方不支付任何补偿。', expect: ['R015@C01'] },
  { name: '迟到罚款', text: '第一条 劳动纪律\n乙方迟到一次罚款200元，从当月工资中扣除。', expect: ['R020@C01'] },
  { name: '不得罚款（合法）', text: '第一条 劳动纪律\n甲方不得对乙方罚款。', expect: [] },
  { name: '加班费按最低工资', text: '第一条 加班\n加班费以当地最低工资标准为基数计算。', expect: ['R021@C01'] },
  { name: '社保按最低基数', text: '第一条 社会保险\n甲方为乙方缴纳社会保险，按当地最低缴费基数缴纳。', expect: ['R022@C01'] },
  { name: '工伤自负', text: '第一条 安全\n乙方在工作中受伤的，属于工伤的由乙方自行承担。', expect: ['R015@C01'] },
  { name: '不交接扣工资', text: '第一条 离职\n乙方不办理工作交接的，甲方扣发当月工资。', expect: ['R015b@C01'] },
  { name: '不定时工作制未审批', text: '第一条 工作时间\n乙方实行不定时工作制。', expect: ['R018@C01'] },
  { name: '不定时工作制已审批（合法）', text: '第一条 工作时间\n乙方岗位经人社部门审批实行不定时工作制。', expect: [] },
  { name: '规章制度已公示（合法）', text: '第一条 规章制度\n乙方应遵守经民主程序制定并已公示的规章制度。', expect: [] },
  { name: '直接起诉', text: '第一条 争议\n发生争议的，双方可直接向人民法院起诉。', expect: ['R016@C01'] },
  { name: '工资包含绩效（合法）', text: '第一条 劳动报酬\n月工资包含基本工资和绩效，加班费另行计算。', expect: [] },
  // Minimum wage (R023), with the provincial tiers in MinimumWages.
  { name: '北京月薪低于最低工资', text: '第一条 劳动报酬\n乙方月工资为2300元。', facts: { city: '北京' }, expect: ['R023@C01'] },
  { name: '广州月薪介于各档之间', text: '第一条 劳动报酬\n乙方月工资为2500元。', facts: { city: '广州市' }, expect: ['R023@C01'] },
  { name: '广州月薪 8,500 元（合法）', text: '第一条 劳动报酬\n乙方月工资为人民币 8,500 元，于每月15日前支付。', facts: { city: '广州' }, expect: [] },
  { name: '未填城市、月薪 1500 元', text: '第一条 劳动报酬\n乙方月薪1500元。', expect: ['R023@C01'] },
  { name: '未填城市、月薪 2500 元', text: '第一条 劳动报酬\n乙方月薪2500元。', expect: ['R023@C01'] },
  {
    name: '上海试用期八折低于最低工资',
    text: '第一条 劳动报酬\n乙方月工资3000元，试用期工资为约定工资的80%。', facts: { city: '上海' }, expect: ['R023@C01']
  },
  { name: '违约金金额不算工资', text: '第一条 违约金\n乙方提前离职，按工资标准支付违约金2000元。', facts: { city: '北京' }, expect: ['R005@C01'] },
  { name: '月薪 1.2 万元（合法）', text: '第一条 劳动报酬\n乙方月薪1.2万元。', facts: { city: '深圳' }, expect: [] },
  // Structure.
  { name: '悬空引用只报一次', text: '第一条 其他\n双方的权利义务详见第五条。', expect: [], warnings: { '悬空引用': 1 } },
  { name: '全角条号', text: '第１条 合同期限\n本合同期限三年。\n第３条 其他\n无。', expect: [], warnings: { '断号': 1 } }
];

function findingKeys(findings: Finding[], whole: boolean): string[] {
  return findings.filter((f: Finding) => whole || f.ruleId !== 'R014')
    .map((f: Finding) => f.ruleId + '@' + f.anchorId).sort();
}

function lawArticles(): Map<string, Set<string>> {
  const index = JSON.parse(readFileSync(process.env.LAW_INDEX ?? '', 'utf8'));
  const titleById: Map<string, string> = new Map();
  for (const d of index.documents) {
    titleById.set(d.documentId, d.title);
  }
  const articles: Map<string, Set<string>> = new Map();
  for (const c of index.chunks) {
    const title: string = titleById.get(c.documentId) ?? '';
    if (!articles.has(title)) {
      articles.set(title, new Set());
    }
    articles.get(title)?.add(c.article);
  }
  return articles;
}

// --dump prints the cases as JSON, for running the same inputs through the
// desktop client's Python rules.
if (process.argv.includes('--dump')) {
  console.log(JSON.stringify(CASES));
  process.exit(0);
}

let failed: number = 0;
const refs: Set<string> = new Set();
for (const c of CASES) {
  const facts: FactSheet = Object.assign(new FactSheet(), c.facts ?? {});
  const audit: StructureAudit = ContractStructure.audit(c.text, false);
  const result = ContractRules.run(audit.anchors, c.text, facts);
  result.findings.forEach((f: Finding) => f.lawRefs.forEach((r: string) => refs.add(r)));
  const got: string[] = findingKeys(result.findings, c.wholeContract === true);
  const want: string[] = c.expect.slice().sort();
  const problems: string[] = [];
  if (got.join(',') !== want.join(',')) {
    problems.push(`findings ${got.join(', ') || '无'}，期望 ${want.join(', ') || '无'}`);
  }
  if (c.warnings !== undefined) {
    const counts: Record<string, number> = {};
    audit.warnings.forEach((w) => {
      counts[w.kind] = (counts[w.kind] ?? 0) + 1;
    });
    if (JSON.stringify(counts, Object.keys(counts).sort()) !== JSON.stringify(c.warnings, Object.keys(c.warnings).sort())) {
      problems.push(`warnings ${JSON.stringify(counts)}，期望 ${JSON.stringify(c.warnings)}`);
    }
  }
  if (problems.length > 0) {
    failed++;
    console.log(`✗ ${c.name}\n    ${problems.join('\n    ')}`);
  } else {
    console.log(`✓ ${c.name}`);
  }
}

// Every law reference must open an article in the bundled index.
const articles: Map<string, Set<string>> = lawArticles();
for (const ref of [...refs].sort()) {
  if (ContractLaws.isKnownMissing(ref)) {
    console.log(`· ${ref}：本地库未收录`);
    continue;
  }
  const at = ContractLaws.resolve(ref);
  if (at === undefined || !articles.has(at.title) ||
    (at.article.length > 0 && !articles.get(at.title)?.has(at.article))) {
    failed++;
    console.log(`✗ 法条 ${ref} 在本地法规库中找不到`);
  }
}


// Model reply handling and privacy masking.
function check(name: string, ok: boolean, detail: string): void {
  if (ok) {
    console.log(`✓ ${name}`);
  } else {
    failed++;
    console.log(`✗ ${name}\n    ${detail}`);
  }
}

const masked: string = ContractPrivacy.mask('乙方（劳动者）：张三\n身份证号码：11010519900307123X\n联系电话 13812345678，' +
  '住址：北京市朝阳区某某路1号\n月薪5000元，工资卡 6222021234567890123。').text;
check('个人信息脱敏', !/张三|11010519900307123X|13812345678|朝阳区|6222021234567890123/.test(masked) &&
  masked.includes('月薪5000元') && masked.includes('乙方（劳动者）：【姓名】'), masked);

const laws: ReviewLaw[] = [new ReviewLaw('K1', '中华人民共和国劳动合同法（2012修正）', '第二十五条', '……'),
  new ReviewLaw('K2', '中华人民共和国劳动合同法（2012修正）', '第三十五条', '……')];
const reply: string = '<think>先看条款</think>```json\n{"findings":[' +
  '{"anchor_id":"C02","quote":"工作地点为全国","topic":"调岗","nature":"谈判点","severity":"中","bargain":"应谈项","reason":"单方调岗","law_refs":["K2","K9","《劳动法》第一条"]},' +
  '{"anchor_id":"第三条","topic":"x","nature":"无效","severity":"红线","reason":"错位"},' +
  '{"anchor_id":"C03","topic":"罚则","nature":"无效","severity":"红线","bargain":"乱写","reason":"没有依据的无效"},' +
  '{"anchor_id":"C00","topic":"工资","nature":"缺失","severity":"高","reason":"未约定工资数额","confidence":7}]}\n```';
const parsed = ContractAi.parse(reply, ['C02', 'C03'], laws);
const byTopic = (t: string) => parsed.findings.find((f: Finding) => f.topic === t);
check('模型回复：错位锚点被剔除并计数', parsed.ok && parsed.misplaced === 1 && parsed.findings.length === 3,
  JSON.stringify(parsed));
check('模型回复：只保留候选法条编号', JSON.stringify(byTopic('调岗')?.lawRefs) ===
  JSON.stringify(['《中华人民共和国劳动合同法（2012修正）》第三十五条']), JSON.stringify(byTopic('调岗')?.lawRefs));
check('模型回复：无依据的「无效」降为待确认', byTopic('罚则')?.nature === '待确认' && byTopic('罚则')?.severity === '中' &&
  byTopic('罚则')?.bargain === '应谈项', JSON.stringify(byTopic('罚则')));
check('模型回复：保留原文摘录', byTopic('调岗')?.quote === '工作地点为全国', JSON.stringify(byTopic('调岗')));
check('模型回复：置信度收敛到 0–1', byTopic('工资')?.confidence === 1, JSON.stringify(byTopic('工资')));
check('模型回复：无法解析', !ContractAi.parse('抱歉，我无法完成', ['C01'], laws).ok, '');

const rule: Finding = Object.assign(new Finding(), { ruleId: 'R012', anchorId: 'C02', topic: '调岗', severity: '中' });
const merged: Finding[] = ContractAi.merge([rule], parsed.findings);
check('合并：规则结论优先', merged.filter((f: Finding) => f.anchorId === 'C02' && f.topic === '调岗').length === 1 &&
  merged.find((f: Finding) => f.anchorId === 'C02')?.ruleId === 'R012' &&
  merged.some((f: Finding) => f.ruleId === AI_RULE_ID), JSON.stringify(merged.map((f: Finding) => f.ruleId + f.anchorId)));

const prompt: string = ContractAi.reviewPrompt(new FactSheet(), laws,
  ContractStructure.audit('第一条 当事人\n乙方：李四，手机13912345678。', false).anchors, [], '');
check('提示词不含个人信息', !prompt.includes('李四') && !prompt.includes('13912345678') && prompt.includes('[C01]'), prompt);

const sh = ContractRules.run(ContractStructure.audit('第一条 劳动报酬\n乙方月工资3000元，试用期工资为约定工资的80%。', false).anchors,
  '第一条 劳动报酬\n乙方月工资3000元，试用期工资为约定工资的80%。', Object.assign(new FactSheet(), { city: '上海' }));
check('最低工资：试用期按比例折算', sh.findings.some((f: Finding) => f.ruleId === 'R023' && f.reason.includes('试用期工资约2400元')),
  JSON.stringify(sh.findings.map((f: Finding) => f.reason)));

// Highlights and reasoning on the sample contract: each finding marks the
// words it is about, inside its own clause, and rule findings explain
// themselves.
{
  const facts: FactSheet = Object.assign(new FactSheet(), { city: SAMPLE_CONTRACT_CITY });
  const audit: StructureAudit = ContractStructure.audit(SAMPLE_CONTRACT_TEXT, false);
  const t: string = ContractStructure.normalize(SAMPLE_CONTRACT_TEXT);
  const findings: Finding[] = ContractRules.run(audit.anchors, SAMPLE_CONTRACT_TEXT, facts).findings;
  const marked = (rule: string): string[] => findings.filter((f: Finding) => f.ruleId === rule && f.start >= 0)
    .map((f: Finding) => t.substring(f.start, f.end));
  const expectMarks: string[][] = [
    ['R001', '试用期三个月'], ['R003', '试用期工资为约定工资的70%'], ['R005', '违约金20000元'],
    ['R007', '离职后三年'], ['R010', '自愿放弃缴纳社会保险'], ['R013', '押金'], ['R019', '不得怀孕生育'],
    ['R011', '已包含全部加班费'], ['R020', '罚款'], ['R016', '商事仲裁'], ['R008', '离职后三年内'], ['R023', '2,600元']
  ];
  for (const pair of expectMarks) {
    const got: string[] = marked(pair[0]);
    check(`标注：${pair[0]} 标在「${pair[1]}」`, got.some((m: string) => m.includes(pair[1])), JSON.stringify(got));
  }
  const outside: Finding[] = findings.filter((f: Finding) => {
    if (f.start < 0) {
      return f.anchorId !== 'C00' && !['R017', 'R018'].includes(f.ruleId) && false;
    }
    const a = audit.anchors.find((x) => x.anchorId === f.anchorId);
    return a === undefined || f.start < a.start || f.end > a.end;
  });
  check('标注都在所属条款内', outside.length === 0, JSON.stringify(outside.map((f: Finding) => f.ruleId)));
  check('每条规则结论都有审查过程', findings.every((f: Finding) => f.trace.length >= 3),
    JSON.stringify(findings.filter((f: Finding) => f.trace.length < 3).map((f: Finding) => f.ruleId)));
  // The annotated view: lines rebuild the text, and highlighted pieces carry
  // their findings.
  const lines: DocLine[] = ContractDocument.lines(t, audit.anchors, findings);
  const rebuilt: string = lines.map((l: DocLine) => l.segments.map((g: DocSegment) => g.text).join('')).join('\n');
  check('原文视图：分行后文字不变', rebuilt === t.split('\n').filter((x: string) => x.trim().length > 0).join('\n'), rebuilt);
  const r003: number = findings.findIndex((f: Finding) => f.ruleId === 'R003');
  const pay: DocSegment | undefined = lines.flatMap((l: DocLine) => l.segments)
    .find((g: DocSegment) => g.text.includes('70%'));
  check('原文视图：重叠时取更严重的那条', pay !== undefined && findings[pay.finding].severity === '红线' &&
    (pay.finding === r003 || findings[pay.finding].ruleId === 'R023'), JSON.stringify(pay));
  check('原文视图：条款标题行加粗', lines.filter((l: DocLine) => l.heading).length === 13, String(lines.filter((l) => l.heading).length));
  const order: number[] = ContractDocument.order(findings, audit.anchors);
  check('原文视图：导航按原文顺序', order.length === findings.length &&
    findings[order[0]].anchorId === 'C01' && findings[order[order.length - 1]].anchorId === 'C13',
    JSON.stringify(order.map((k: number) => findings[k].anchorId)));
  const r023: Finding | undefined = findings.find((f: Finding) => f.ruleId === 'R023' && f.reason.includes('1820'));
  check('审查过程含计算', r023 !== undefined && r023.trace.some((s: string) => s.includes('2600 元 × 70% ≈ 1820 元')),
    JSON.stringify(r023?.trace));
}

const sanity: number[] = [ContractRules.probationCap(36), ContractRules.probationCap(35),
  ContractRules.probationCap(TERM_OPEN), ContractRules.probationCap(TERM_TASK)];
if (sanity.join(',') !== '6,2,6,0') {
  failed++;
  console.log(`✗ probationCap ${sanity.join(',')}`);
}

console.log(failed === 0 ? `\n全部通过（${CASES.length} 个用例）` : `\n${failed} 项未通过`);
process.exit(failed === 0 ? 0 : 1);
