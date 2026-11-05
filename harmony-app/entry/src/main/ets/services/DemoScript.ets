import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { ChatMessage, ChatRole, LawCitation } from '../models/AppModels';

// 引导式演示: the story of 张三, a salesman let go by word of mouth with no
// overtime pay and no social insurance, told in five steps across the app.
// Each step says what to do, can fill in the sample input, and leaves sending
// to the presenter, so the model is really called. When it is slow, a
// backup answer recorded from a real call earlier can stand in, marked so.

export const DEMO_STEP_INTRO: number = -1;
export const DEMO_STEP_QUICK: number = 1;
export const DEMO_STEP_CASE: number = 2;
export const DEMO_STEP_EVIDENCE: number = 3;
export const DEMO_STEP_REPORT: number = 4;
export const DEMO_STEP_CONTRACT: number = 5;
export const DEMO_STEP_SUMMARY: number = 6;
// After the summary, looking back at the pages.
export const DEMO_STEP_REVIEW: number = 7;
export const DEMO_STEP_COUNT: number = 5;
// No output from the model this long after sending: offer the backup.
export const DEMO_BACKUP_AFTER_MS: number = 5000;
// Starts a backup answer, so it is never taken for a live one.
export const DEMO_BACKUP_MARK: string = '【备用结果 · 事先真实调用生成】\n\n';

export const DEMO_QUESTION: string = '试用期被辞退，公司需要给补偿吗？';
export const DEMO_STORY: string = '我在某某示例科技有限公司做销售，2026年1月1日入职，合同期一年，试用期三个月。' +
  '工作地点在深圳。每月实际到手6000元左右，合同上写的是2600元。10月15日人事口头通知我下个月起不用来了，没有书面通知，也没说补偿。' +
  '平时经常加班到晚上九十点，没有加班费，社保也一直没交，公司让我签过“自愿放弃社保”的声明。';
export const DEMO_LOCATION: string = '广东省深圳市';
export const DEMO_COMPANY: string = '某某示例科技有限公司';
export const DEMO_SALARY: string = '6000';
export const DEMO_TIMELINE: string = '2026年1月1日入职；2026年10月15日被口头通知下月起不再用工';
export const DEMO_REQUEST: string = '要求公司支付违法解除劳动合同的赔偿金、拖欠的加班费，并补缴社会保险。';
export const DEMO_DETAILS: string = '2026年1月1日入职，任销售专员，签订一年期劳动合同。合同约定月工资2600元并“包含全部加班费”，' +
  '实际每月发放约6000元。工作日经常加班至21时以后，未支付加班费。入职时被要求签署“自愿放弃社保”声明，公司未缴纳社保。' +
  '2026年10月15日，人事经理口头通知下月起不再用工，未出具书面解除通知，未支付经济补偿。';

export class DemoStepText {
  title: string;
  page: string;
  body: string;
  fill: string;
  done: string;

  constructor(title: string, page: string, body: string, fill: string, done: string) {
    this.title = title;
    this.page = page;
    this.body = body;
    this.fill = fill;
    this.done = done;
  }
}

export const DEMO_STEPS: DemoStepText[] = [
  new DemoStepText('普法咨询', '普法', '先问一个法律问题。点「填入示例」，再点发送：回答会附上法条依据，点角标可看原文。',
    '填入示例问题', '回答好了，点角标看看法条原文。'),
  new DemoStepText('梳理案件', '维权 · 梳理', '把张三的经历像聊天一样告诉应用，它会分析问题并追问还缺什么。点「填入示例」，再点发送。',
    '填入张三的经历', '分析好了。接下来整理证据。'),
  new DemoStepText('整理证据', '维权 · 证据', '导入三张示例证据（工资条、考勤、聊天截图），在本机识别文字并自动分类。识别完打开工资条，把月薪一键填入卷宗。',
    '导入示例证据', '证据已整理，月薪已进卷宗。'),
  new DemoStepText('生成分析报告', '维权 · 卷宗', '点「填入示例」补齐卷宗其余几项，再滑到页面底部点「生成案件分析报告」，在弹出的窗口里点「开始生成报告」。',
    '补齐卷宗', '报告生成好了。最后看看合同。'),
  new DemoStepText('合同体检', '合同', '打开示例合同，事实已填好、AI 深度审查已打开。点「开始审查」，完成后点一处红线看详情。',
    '打开示例合同', '审查完成，点标红处看问题详情。')
];

// Backup answers recorded from real calls, packaged in rawfile, with the
// law articles their citation marks point at.
export class DemoBackups {
  quick: ChatMessage | undefined = undefined;
  caseReply: ChatMessage | undefined = undefined;
  report: string = '';
  reportCitations: LawCitation[] = [];

  static async load(context: common.Context): Promise<DemoBackups> {
    const backups: DemoBackups = new DemoBackups();
    try {
      const bytes: Uint8Array = await context.resourceManager.getRawFileContent('demo/backups.json');
      const raw: RecordedBackups = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(bytes)) as RecordedBackups;
      backups.quick = DemoBackups.message(raw.quick);
      backups.caseReply = DemoBackups.message(raw.caseReply);
      backups.report = raw.report ?? '';
      backups.reportCitations = raw.reportCitations ?? [];
    } catch (error) {
      // Without the file there are no backups; the steps still work live.
    }
    return backups;
  }

  // Marked as a backup, so it is never taken for a live answer.
  private static message(recorded: RecordedMessage | undefined): ChatMessage | undefined {
    if (recorded === undefined || recorded.content.length === 0) {
      return undefined;
    }
    const message: ChatMessage = new ChatMessage(ChatRole.ASSISTANT, DEMO_BACKUP_MARK + recorded.content,
      recorded.citations ?? []);
    message.reasoning = recorded.reasoning ?? '';
    message.thinkMs = recorded.thinkMs ?? 0;
    return message;
  }
}

interface RecordedMessage {
  content: string;
  reasoning?: string;
  thinkMs?: number;
  citations?: LawCitation[];
}

interface RecordedBackups {
  quick?: RecordedMessage;
  caseReply?: RecordedMessage;
  report?: string;
  reportCitations?: LawCitation[];
}
