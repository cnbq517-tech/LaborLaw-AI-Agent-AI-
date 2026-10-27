// Data model for contract review, ported from the desktop client's
// contract_review/schema.py. Pure logic: no @kit imports, so the engine can be
// tested with Node.
//
// Findings only carry an anchorId, never a clause number string: every "第X条"
// shown to the user is looked up from the frozen anchor table.

export const LEVEL_CHAPTER: string = '章';
export const LEVEL_ARTICLE: string = '条';
export const LEVEL_PARAGRAPH: string = '款';
export const LEVEL_ITEM: string = '项';

export const SEVERITY_REDLINE: string = '红线';
export const SEVERITY_HIGH: string = '高';
export const SEVERITY_MEDIUM: string = '中';
export const SEVERITY_LOW: string = '低';
export const SEVERITY_NOTE: string = '提示';
export const SEVERITIES: string[] =
  [SEVERITY_REDLINE, SEVERITY_HIGH, SEVERITY_MEDIUM, SEVERITY_LOW, SEVERITY_NOTE];

export const NATURE_INVALID: string = '无效';
export const NATURE_FLAW: string = '瑕疵';
export const NATURE_MISSING: string = '缺失';
export const NATURE_CONFLICT: string = '冲突';
export const NATURE_PENDING: string = '待确认';
export const NATURE_BARGAIN: string = '谈判点';
export const NATURES: string[] =
  [NATURE_INVALID, NATURE_FLAW, NATURE_MISSING, NATURE_CONFLICT, NATURE_PENDING, NATURE_BARGAIN];

export const BARGAIN_MUST: string = '必改项';
export const BARGAIN_SHOULD: string = '应谈项';
export const BARGAIN_YIELD: string = '可让项';
export const BARGAIN_NONE: string = '-';
export const BARGAINS: string[] = [BARGAIN_MUST, BARGAIN_SHOULD, BARGAIN_YIELD, BARGAIN_NONE];

// Anchor for findings about the whole contract, such as a missing clause.
export const WHOLE_CONTRACT: string = 'C00';

export const FACT_YES: string = '是';
export const FACT_NO: string = '否';
export const FACT_UNKNOWN: string = '未定';

// Contract term in months; special values for terms without a month count.
export const TERM_UNKNOWN: number = -1;
export const TERM_TASK: number = -2;
export const TERM_OPEN: number = 1000;

export class ClauseAnchor {
  anchorId: string;
  rawNo: string;
  level: string;
  // The clause line plus any unnumbered lines merged into it.
  text: string;
  // Offsets into the normalized contract text; a rule hit at an offset belongs
  // to the last anchor starting at or before it.
  start: number;
  end: number;
  parentId: string;
  refsOut: string[] = [];

  constructor(anchorId: string, rawNo: string, level: string, text: string, start: number, end: number,
    parentId: string) {
    this.anchorId = anchorId;
    this.rawNo = rawNo;
    this.level = level;
    this.text = text;
    this.start = start;
    this.end = end;
    this.parentId = parentId;
  }
}

export class StructureWarning {
  kind: string;
  detail: string;
  anchorId: string;

  constructor(kind: string, detail: string, anchorId: string = '') {
    this.kind = kind;
    this.detail = detail;
    this.anchorId = anchorId;
  }
}

export class Finding {
  findingId: string = '';
  anchorId: string = WHOLE_CONTRACT;
  severity: string = SEVERITY_NOTE;
  nature: string = NATURE_FLAW;
  bargain: string = BARGAIN_NONE;
  topic: string = '';
  reason: string = '';
  // References like 《劳动合同法》第二十五条; ContractLaws resolves them to
  // the bundled legal index.
  lawRefs: string[] = [];
  suggestion: string = '';
  altClause: string = '';
  pendingFacts: string[] = [];
  evidenceGap: string = '';
  confidence: number = 0;
  ruleId: string = '';
}

// Facts the user confirms before review. The user is always the worker, so the
// desktop client's 委托方立场 question is gone.
export class FactSheet {
  city: string = '';
  position: string = '';
  confidential: string = FACT_UNKNOWN;
  // Whether the contract is already signed: unsigned contracts are about what
  // to ask to change, signed ones about what is void anyway and what to keep.
  signed: string = FACT_UNKNOWN;
  termMonths: number = TERM_UNKNOWN;
  probationMonths: number = -1;
}

// Contract term and probation as read from the contract text.
export class ContractTerms {
  termMonths: number = TERM_UNKNOWN;
  termAt: number = -1;
  probationDays: number = -1;
  probationAt: number = -1;
}

export class StructureAudit {
  anchors: ClauseAnchor[];
  warnings: StructureWarning[];
  terms: Map<string, string>;

  constructor(anchors: ClauseAnchor[], warnings: StructureWarning[], terms: Map<string, string>) {
    this.anchors = anchors;
    this.warnings = warnings;
    this.terms = terms;
  }
}

export class RuleResult {
  findings: Finding[];
  terms: ContractTerms;

  constructor(findings: Finding[], terms: ContractTerms) {
    this.findings = findings;
    this.terms = terms;
  }
}
