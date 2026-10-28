// A fictional labor contract with typical problems, so the review can be tried
// without a file at hand. Every party, ID and phone number is made up. Its
// expected findings are pinned in tools/harmony/contract-rules/cases.ts.

export const SAMPLE_CONTRACT_NAME: string = '示例劳动合同（虚构）';
// The contract names 深圳 as the workplace; the facts page starts from it.
export const SAMPLE_CONTRACT_CITY: string = '深圳';

export const SAMPLE_CONTRACT_TEXT: string = [
  '劳动合同书（示例）',
  '甲方（用人单位）：某某示例科技有限公司',
  '住所：深圳市南山区示例路1号',
  '乙方（劳动者）：张三',
  '身份证号码：440300199001010000',
  '联系电话：13800000000',
  '第一条 合同期限',
  '本合同为固定期限劳动合同，期限自2026年1月1日起至2026年12月31日止，其中试用期三个月。',
  '第二条 工作内容和工作地点',
  '乙方担任销售专员，工作地点为公司经营所在地及全国，乙方应服从公司安排的其他工作。',
  '第三条 工作时间和休息休假',
  '乙方实行不定时工作制，公司根据经营需要安排工作时间。',
  '第四条 劳动报酬',
  '乙方月工资为人民币2,600元，已包含全部加班费。试用期工资为约定工资的70%。',
  '第五条 社会保险',
  '乙方自愿放弃缴纳社会保险，公司每月发放社保补贴300元。',
  '第六条 劳动纪律',
  '乙方迟到一次罚款100元，从当月工资中扣除；乙方连续旷工3日的，视为自动离职。',
  '第七条 入职押金',
  '乙方入职时需交纳服装押金500元，离职时无息退还。',
  '第八条 违约金',
  '乙方在合同期内提前离职的，应向甲方支付违约金20000元。',
  '第九条 竞业限制',
  '乙方离职后三年内不得在与甲方有竞争关系的单位任职。',
  '第十条 特别约定',
  '乙方在合同期内不得怀孕生育，否则视为严重违纪。',
  '第十一条 劳动保护',
  '甲方为乙方提供符合国家规定的劳动安全卫生条件和必要的劳动保护用品。',
  '第十二条 争议解决',
  '双方发生争议的，提交深圳仲裁委员会进行商事仲裁。',
  '第十三条 其他',
  '本合同未尽事宜，按甲方规章制度执行。本合同一式两份，双方各执一份。'
].join('\n');
