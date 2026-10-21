/** Short, pre-reviewed prompts. The card never sends a question or calls a model by itself. */
export class LawCardTip {
  readonly title: string;
  readonly body: string;
  readonly scenario: string;

  constructor(title: string, body: string, scenario: string) {
    this.title = title;
    this.body = body;
    this.scenario = scenario;
  }
}

export const LAW_CARD_TIPS: LawCardTip[] = [
  new LawCardTip('工资拖欠', '先保存工资流水、考勤和催付记录，便于说明欠薪事实。', 'wage_arrears'),
  new LawCardTip('未签合同', '保留入职证明、考勤及工资记录，再核对合同签订时间。', 'unsigned_contract'),
  new LawCardTip('违法解除', '妥善保存解除通知和沟通记录，先确认解除理由及程序。', 'illegal_termination'),
  new LawCardTip('加班争议', '留存排班、考勤和工作沟通记录，核对适用的工时制度。', 'overtime')
];
