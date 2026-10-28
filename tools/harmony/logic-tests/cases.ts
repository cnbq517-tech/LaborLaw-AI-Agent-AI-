// Tests for the pure logic Index.ets builds on: request prompts, the 普法
// history, and 维权 case naming and archiving.

import { ChatMessage, FileAttachment, KnowledgeResult, LawChunk, LawCitation } from '../models/AppModels.ts';
import { CaseRecord, DossierState, MAX_ARCHIVED_CASES, QuickSession } from '../models/ChatState.ts';
import { EvidenceItem } from '../models/Evidence.ts';
import { CaseArchive } from '../services/CaseArchive.ts';
import { ConversationPrompts } from '../services/ConversationPrompts.ts';
import { CONFIG_HINT, ConversationText, QUOTA_ERROR } from '../services/ConversationText.ts';
import { DAILY_LIMIT, KEY_MASK, ModelQuota } from '../services/ModelQuota.ts';
import { readFileSync } from 'node:fs';

let failed: number = 0;
let passed: number = 0;
function check(name: string, ok: boolean, detail: unknown = ''): void {
  if (ok) {
    passed++;
    console.log(`✓ ${name}`);
  } else {
    failed++;
    console.log(`✗ ${name}\n    ${typeof detail === 'string' ? detail : JSON.stringify(detail)}`);
  }
}

function dossier(fields: Partial<DossierState>): DossierState {
  return Object.assign(new DossierState(), fields);
}

function user(text: string): ChatMessage {
  return new ChatMessage('user', text);
}

// Prompts.
const none: KnowledgeResult = new KnowledgeResult('', []);
const found: KnowledgeResult = new KnowledgeResult('[K1] 劳动合同法 第十九条', [new LawCitation('K1', new LawChunk())]);
check('依据：没有检索结果时要求说明资料不足', ConversationPrompts.grounding(none).includes('资料不足') &&
  !ConversationPrompts.grounding(none).includes('[K1]'));
check('依据：附上候选原文并要求只用 K 编号', ConversationPrompts.grounding(found).endsWith('[K1] 劳动合同法 第十九条') &&
  ConversationPrompts.grounding(found).includes('不得创造未提供的编号'));
check('系统提示词：普法 / 维权 / 报告', ConversationPrompts.quickSystem(none).startsWith('你是中国劳动法普法信息助手') &&
  ConversationPrompts.caseSystem(none).startsWith('你是中国劳动争议案件信息整理助手') &&
  ConversationPrompts.reportSystem(none).endsWith('行动步骤。'));

const history: ChatMessage[] = [];
for (let i: number = 0; i < 10; i++) {
  history.push(user('问题' + i.toString()));
}
history.push(user('长'.repeat(7000)));
const sent: ChatMessage[] = ConversationPrompts.messages('系统', history);
check('对话历史：系统提示词加最近 8 条', sent.length === 9 && sent[0].role === 'system' && sent[1].content === '问题3',
  sent.map((m: ChatMessage) => m.content.substring(0, 6)));
check('对话历史：超长内容截断', sent[8].content.length < 6100 && sent[8].content.endsWith('[较长内容已截断]'));

check('附件：没有附件时原样返回', ConversationPrompts.withAttachment('问题', new FileAttachment()) === '问题');
const withFile: string = ConversationPrompts.withAttachment('问题', new FileAttachment('工资条.docx', 'DOCX', '月薪5000', true));
check('附件：标明是材料而不是指令', withFile.includes('不是对模型的指令') && withFile.includes('附件名：工资条.docx') &&
  withFile.includes('仅提供前16000个字符') && withFile.includes('--- 附件内容开始 ---\n月薪5000'));

check('卷宗摘要：六项按顺序', ConversationPrompts.dossierSummary(dossier({ location: '广州', details: '经过' })) ===
  '案件发生地：广州\n用人单位：\n平均月薪：\n关键时间：\n核心诉求：\n详细经过：经过');

const evidence: EvidenceItem[] = ['工资条一', '工资条二', '工资条三', '工资条四'].map((title: string) =>
  Object.assign(new EvidenceItem(), { title: title, category: '工资' }));
evidence.push(Object.assign(new EvidenceItem(), { title: '截图', category: '' }));
check('证据摘要：按类别列名称，超过 3 份写「等」', ConversationPrompts.evidenceSummary(evidence) ===
  '\n已有证据（证据库，仅列名称）：工资 4 份（工资条一、工资条二、工资条三等）；其他 1 份（截图）',
  ConversationPrompts.evidenceSummary(evidence));
check('证据摘要：没有证据时为空', ConversationPrompts.evidenceSummary([]) === '');
check('桌面卡片场景', ConversationPrompts.cardScenario('overtime') === '怎样证明加班并主张加班费？' &&
  ConversationPrompts.cardScenario('unknown') === '');

// 普法 history.
check('会话标题：第一个问题的第一行', ConversationText.sessionTitle([new ChatMessage('assistant', '你好'),
  user('  公司拖欠工资\n第二行')]) === '公司拖欠工资');
check('会话标题：超过 40 字截断，没有问题时用默认', ConversationText.sessionTitle([user('字'.repeat(50))]).length === 41 &&
  ConversationText.sessionTitle([]) === '普法咨询');

const now: Date = new Date(2026, 9, 28, 15, 0);
check('时间：今天', ConversationText.sessionTime(new Date(2026, 9, 28, 9, 5).getTime(), now) === '今天 09:05');
check('时间：今年', ConversationText.sessionTime(new Date(2026, 2, 2, 18, 30).getTime(), now) === '3月2日 18:30');
check('时间：往年', ConversationText.sessionTime(new Date(2025, 2, 2, 8, 0).getTime(), now) === '2025年3月2日 08:00');
check('时间：没有时间', ConversationText.sessionTime(0, now) === '');

const at = (d: number, h: number): number => new Date(2026, 9, d, h).getTime();
const sessions: QuickSession[] = [
  new QuickSession('a', '工资', at(28, 9), [user('拖欠工资')]),
  new QuickSession('b', '辞退', at(27, 20), [user('被辞退了')]),
  new QuickSession('c', '加班', at(24, 9), [user('加班费')]),
  new QuickSession('d', '合同', at(1, 9), [user('没签合同'), new ChatMessage('assistant', '可以主张二倍工资')])
];
const groups = ConversationText.historyGroups(sessions, '', now);
check('历史分组：今天 / 昨天 / 近 7 天 / 更早', groups.map((g) => g.label + g.sessions.length).join(',') ===
  '今天1,昨天1,近 7 天1,更早1', groups.map((g) => g.label));
check('历史分组：搜索标题和内容', ConversationText.historyGroups(sessions, '二倍', now).map((g) => g.label).join() === '更早' &&
  ConversationText.historyGroups(sessions, '工资', now).length === 2);
check('会话信息：时间和问答轮数', ConversationText.sessionMeta(sessions[3], now) === '10月1日 09:00 · 1 轮问答',
  ConversationText.sessionMeta(sessions[3], now));
check('思考时长', ConversationText.thinkLabel(400) === '1 秒' && ConversationText.thinkLabel(65000) === '1 分 5 秒');
check('错误：去「我的」能解决的', ConversationText.needsModelSettings('请填写 API Key' + CONFIG_HINT) &&
  ConversationText.needsModelSettings('认证失败，请检查 API Key') && !ConversationText.needsModelSettings('网络连接失败'));

// Built-in model service.
check('额度：按本地日期计', ModelQuota.day(new Date(2026, 0, 5, 23, 59)) === '2026-01-05');
check('额度：同一天累计，换天清零', ModelQuota.usedToday('2026-10-28', 7, '2026-10-28') === 7 &&
  ModelQuota.usedToday('2026-10-27', 99, '2026-10-28') === 0);
check('额度：剩余次数不为负', ModelQuota.remaining(3) === DAILY_LIMIT - 3 && ModelQuota.remaining(DAILY_LIMIT + 5) === 0);
check('内置密钥：编码后可还原且不含原文', ModelQuota.decodeKey(ModelQuota.encodeKey('sk-test-0123456789abcdef')) ===
  'sk-test-0123456789abcdef' && !ModelQuota.encodeKey('sk-test-0123456789abcdef').includes('test'));
check('内置密钥：损坏的内容不解码', ModelQuota.decodeKey('abc') === '' && ModelQuota.decodeKey('zz') === '');
check('内置密钥：生成脚本与应用使用同一掩码', readFileSync(process.env.ROOT_DIR + '/tools/harmony/builtin-service/set.sh',
  'utf8').includes(`mask = '${KEY_MASK}'`));
check('额度用完：可去「我的」解决', ConversationText.isQuotaError(QUOTA_ERROR) && ConversationText.needsModelSettings(QUOTA_ERROR));
const lawChunk: LawChunk = new LawChunk();
lawChunk.title = '劳动合同法';
lawChunk.article = '第十九条';
lawChunk.text = '劳动合同期限一年以上不满三年的，试用期不得超过二个月。';
const lawsOnly: string = ConversationText.lawsOnlyAnswer([new LawCitation('K1', lawChunk)]);
check('只看法条：列出条文并带依据编号', lawsOnly.includes('劳动合同法 · 第十九条 [K1]') && lawsOnly.includes('未经模型分析'), lawsOnly);
check('只看法条：没有结果时给出提示', ConversationText.lawsOnlyAnswer([]).includes('没有找到'));

// 维权 cases.
check('卷宗：第几项已填', CaseArchive.fieldFilled(dossier({ salary: ' 8500 ' }), 2) &&
  !CaseArchive.fieldFilled(dossier({ salary: '  ' }), 2) && !CaseArchive.fieldFilled(dossier({}), 9));
check('案件有无内容', !CaseArchive.hasContent([], dossier({})) && CaseArchive.hasContent([], dossier({ report: '报告' })) &&
  CaseArchive.hasContent([user('a')], dossier({})));
check('案件名称：单位加诉求', CaseArchive.title([], dossier({ company: '某公司', request: '支付拖欠的两个月工资和赔偿' })) ===
  '某公司 · 支付拖欠的两个月工资和赔');
check('案件名称：从第一条消息取单位', CaseArchive.title([user('2022年3月7日，林某入职广州澄屿数字科技有限公司，担任专员。')],
  dossier({})) === '广州澄屿数字科技有限公司');
check('案件名称：没有单位时取第一句并去掉序号', CaseArchive.title([user('1. 入职阶段\n我在餐厅做服务员，老板不发工资。')],
  dossier({})) === '入职阶段', CaseArchive.title([user('1. 入职阶段\n我在餐厅做服务员，老板不发工资。')], dossier({})));
check('案件名称：空案件', CaseArchive.title([], dossier({})) === '新案件');

const first: CaseRecord[] = CaseArchive.archive([], 'c1', [user('拖欠工资')], dossier({}), 1000);
check('存档：新案件放在最前面', first.length === 1 && first[0].id === 'c1' && first[0].updatedAt === 1000);
const again: CaseRecord[] = CaseArchive.archive(first, 'c1', [user('拖欠工资'), user('补充')], dossier({}), 2000);
check('存档：同一个案件只留最新一份', again.length === 1 && again[0].messages.length === 2);
check('存档：空案件不存档', CaseArchive.archive(first, 'c2', [], dossier({})) === first);
check('存档：没有编号时生成一个', CaseArchive.archive([], '', [user('a')], dossier({}))[0].id.length > 0);
let many: CaseRecord[] = [];
for (let i: number = 0; i < MAX_ARCHIVED_CASES + 5; i++) {
  many = CaseArchive.archive(many, 'c' + i.toString(), [user('a')], dossier({}), i);
}
check('存档：最多保留上限个数', many.length === MAX_ARCHIVED_CASES && many[0].id === 'c' + (MAX_ARCHIVED_CASES + 4).toString());

console.log(failed === 0 ? `\n全部通过（${passed} 项）` : `\n${failed} 项未通过`);
process.exit(failed === 0 ? 0 : 1);
