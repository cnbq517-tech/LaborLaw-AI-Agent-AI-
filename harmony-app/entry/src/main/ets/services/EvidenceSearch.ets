import { EvidenceItem } from '../models/Evidence';

// Minimum textSearchImage similarity (range -1..1) for a 画面相似 result.
// On a Mate 60 Pro (HarmonyOS 7.0.0.105) the service already applies its own
// per-query threshold (about 0.31-0.34) and only returns images above it, with
// similarities of 0.32-0.36. This floor only guards against other builds
// returning unfiltered results.
export const SEMANTIC_THRESHOLD: number = 0.15;
const SNIPPET_RADIUS: number = 16;

// Evidence categories users search for, and the words that show up in such
// documents. A query touching any word in a group also searches the others.
const SYNONYM_GROUPS: string[][] = [
  ['考勤', '打卡', '出勤', '签到', '上班', '下班'],
  ['工资', '工资条', '薪资', '薪水', '应发', '实发', '劳动报酬'],
  ['合同', '劳动合同', '甲方', '乙方', '合同期限'],
  ['加班', '加班费', '延长工作时间', '调休'],
  ['社保', '社会保险', '缴费基数'],
  ['解除', '辞退', '开除', '解除劳动合同', '通知书'],
  ['聊天', '对话', '消息', '微信']
];

export class SearchResult {
  item: EvidenceItem;
  textHit: boolean = false;
  similarity: number = -2;
  semanticHit: boolean = false;
  snippet: string = '';
  term: string = '';
  score: number = 0;

  constructor(item: EvidenceItem) {
    this.item = item;
  }
}

class TextMatch {
  count: number = 0;
  snippet: string = '';
  term: string = '';
}

export class EvidenceSearch {
  static normalize(value: string): string {
    return value.toLowerCase().replace(/\s/g, '');
  }

  // The query itself first (most specific), then its parts and synonyms.
  static terms(query: string): string[] {
    const terms: string[] = [];
    const add = (term: string): void => {
      const normalized: string = EvidenceSearch.normalize(term);
      if (normalized.length > 0 && !terms.includes(normalized)) {
        terms.push(normalized);
      }
    };
    add(query);
    const parts: string[] = query.split(/[\s,，、;；]+/).filter((part: string) => part.length > 0);
    parts.forEach((part: string) => add(part));
    const normalizedQuery: string = EvidenceSearch.normalize(query);
    SYNONYM_GROUPS.forEach((group: string[]) => {
      if (group.some((word: string) => normalizedQuery.includes(word))) {
        group.forEach((word: string) => add(word));
      }
    });
    return terms;
  }

  // Merges text matches with semantic hits (keyed by indexed file name).
  // Items matched both ways rank first, then text-only, then semantic-only.
  static merge(items: EvidenceItem[], query: string, semantic: Map<string, number>,
    threshold: number = SEMANTIC_THRESHOLD): SearchResult[] {
    const terms: string[] = EvidenceSearch.terms(query);
    const results: SearchResult[] = [];
    items.forEach((item: EvidenceItem) => {
      const result: SearchResult = new SearchResult(item);
      const match: TextMatch | undefined = EvidenceSearch.textMatch(item, terms);
      if (match !== undefined) {
        result.textHit = true;
        result.snippet = match.snippet;
        result.term = match.term;
      }
      const similarity: number | undefined =
        item.indexedFileName.length > 0 ? semantic.get(item.indexedFileName) : undefined;
      if (similarity !== undefined) {
        result.similarity = similarity;
        result.semanticHit = similarity >= threshold;
      }
      if (!result.textHit && !result.semanticHit) {
        return;
      }
      const textScore: number = match !== undefined ? 2 + Math.min(match.count, 5) * 0.1 : 0;
      const semanticScore: number = result.semanticHit ? 1 + result.similarity : 0;
      result.score = textScore + semanticScore;
      results.push(result);
    });
    return results.sort((a: SearchResult, b: SearchResult) => b.score - a.score);
  }

  private static textMatch(item: EvidenceItem, terms: string[]): TextMatch | undefined {
    const sources: string[] = [item.title, item.text, item.originalText];
    let best: TextMatch | undefined = undefined;
    for (let t: number = 0; t < terms.length && best === undefined; t++) {
      const term: string = terms[t];
      let count: number = 0;
      let snippet: string = '';
      sources.forEach((source: string) => {
        source.split('\n').forEach((line: string) => {
          const normalizedLine: string = EvidenceSearch.normalize(line);
          if (!normalizedLine.includes(term)) {
            return;
          }
          count++;
          if (snippet.length === 0) {
            snippet = EvidenceSearch.snippetAround(line.trim(), term);
          }
        });
      });
      if (count > 0) {
        const match: TextMatch = new TextMatch();
        match.count = count;
        match.snippet = snippet;
        match.term = term;
        best = match;
      }
    }
    return best;
  }

  private static snippetAround(line: string, term: string): string {
    const index: number = line.toLowerCase().indexOf(term);
    if (index < 0 || line.length <= SNIPPET_RADIUS * 2 + term.length) {
      return line;
    }
    const start: number = Math.max(0, index - SNIPPET_RADIUS);
    const end: number = Math.min(line.length, index + term.length + SNIPPET_RADIUS);
    return (start > 0 ? '…' : '') + line.substring(start, end) + (end < line.length ? '…' : '');
  }
}
