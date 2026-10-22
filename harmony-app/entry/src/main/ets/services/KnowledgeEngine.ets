import { util } from '@kit.ArkTS';
import {
  KnowledgeResult,
  LawChunk,
  LawCitation,
  LawDocumentIndex,
  LawIndexPayload
} from '../models/AppModels';

// Per-document values every query needs. They are computed once at load time
// so a search no longer runs regex normalization across 50k+ chunks.
class DocumentKeys {
  lowerTitle: string;
  normalizedTitle: string;
  coreLaborContractLaw: boolean;
  normalizedRegion: string;
  shortRegion: string;

  constructor(title: string, region: string) {
    this.lowerTitle = title.toLowerCase();
    this.normalizedTitle = KnowledgeEngine.normalize(title);
    this.coreLaborContractLaw = KnowledgeEngine.isCoreLaborContractLaw(this.normalizedTitle);
    if (region.length === 0 || region === '全国') {
      this.normalizedRegion = '';
      this.shortRegion = '';
    } else {
      this.normalizedRegion = KnowledgeEngine.normalize(region);
      this.shortRegion = this.normalizedRegion
        .replace('特别行政区', '')
        .replace('维吾尔自治区', '')
        .replace('壮族自治区', '')
        .replace('回族自治区', '')
        .replace('自治区', '')
        .replace('省', '')
        .replace('市', '');
    }
  }
}

class IndexedChunk {
  chunk: LawChunk;
  keys: DocumentKeys;
  lowerText: string;

  constructor(chunk: LawChunk, keys: DocumentKeys) {
    this.chunk = chunk;
    this.keys = keys;
    const lower: string = chunk.text.toLowerCase();
    // Most chunks are Chinese and unchanged by toLowerCase(); keep a single
    // string in that case instead of holding two copies of the corpus.
    this.lowerText = lower === chunk.text ? chunk.text : lower;
  }
}

class RankedChunk {
  item: IndexedChunk;
  score: number;

  constructor(item: IndexedChunk, score: number) {
    this.item = item;
    this.score = score;
  }
}

export class KnowledgeLoadStats {
  documentCount: number;
  searchableDocumentCount: number;

  constructor(documentCount: number, searchableDocumentCount: number) {
    this.documentCount = documentCount;
    this.searchableDocumentCount = searchableDocumentCount;
  }
}

// Pure retrieval logic. It runs inside KnowledgeWorker so that parsing the
// 50MB index and scanning every chunk never blocks the UI thread.
export class KnowledgeEngine {
  private static items: IndexedChunk[] = [];
  private static documentCount: number = 0;
  private static searchableDocumentCount: number = 0;

  static loadFromBytes(bytes: Uint8Array): KnowledgeLoadStats {
    if (KnowledgeEngine.items.length > 0) {
      return new KnowledgeLoadStats(KnowledgeEngine.documentCount, KnowledgeEngine.searchableDocumentCount);
    }
    const raw: string = new util.TextDecoder().decodeToString(bytes);
    const payload: LawIndexPayload = JSON.parse(raw) as LawIndexPayload;
    if (payload.version < 1 || payload.documentCount < 1 ||
      payload.chunkCount !== payload.chunks.length || payload.chunks.length === 0) {
      throw new Error('本地法律索引不完整');
    }
    if (payload.version >= 3) {
      const documents: Map<string, LawDocumentIndex> = new Map<string, LawDocumentIndex>();
      payload.documents.forEach((document: LawDocumentIndex) => {
        documents.set(document.documentId, document);
      });
      payload.chunks.forEach((chunk: LawChunk) => {
        const document: LawDocumentIndex | undefined = documents.get(chunk.documentId);
        if (document === undefined) {
          throw new Error('本地法律索引引用关系不完整');
        }
        chunk.title = document.title;
        chunk.category = document.category;
        chunk.subcategory = document.subcategory;
        chunk.region = document.region;
        chunk.source = document.source;
        chunk.status = document.status;
        chunk.effectiveDate = document.effectiveDate;
      });
    }
    const keysByDocument: Map<string, DocumentKeys> = new Map<string, DocumentKeys>();
    const items: IndexedChunk[] = [];
    payload.chunks.forEach((chunk: LawChunk) => {
      const cacheKey: string = chunk.documentId + '\u0000' + chunk.title + '\u0000' + chunk.region;
      let keys: DocumentKeys | undefined = keysByDocument.get(cacheKey);
      if (keys === undefined) {
        keys = new DocumentKeys(chunk.title, chunk.region);
        keysByDocument.set(cacheKey, keys);
      }
      items.push(new IndexedChunk(chunk, keys));
    });
    KnowledgeEngine.items = items;
    KnowledgeEngine.documentCount = payload.documentCount;
    KnowledgeEngine.searchableDocumentCount =
      payload.searchableDocumentCount > 0 ?
      payload.searchableDocumentCount : payload.documentCount;
    return new KnowledgeLoadStats(KnowledgeEngine.documentCount, KnowledgeEngine.searchableDocumentCount);
  }

  static isReady(): boolean {
    return KnowledgeEngine.items.length > 0;
  }

  static search(query: string, limit: number = 6): KnowledgeResult {
    if (!KnowledgeEngine.isReady()) {
      throw new Error('本地法律资料尚未加载完成');
    }
    const terms: string[] = KnowledgeEngine.queryTerms(query);
    const normalizedQuery: string = KnowledgeEngine.normalize(query);
    const ranked: RankedChunk[] = [];
    const maxCandidates: number = Math.max(limit * 24, 144);

    KnowledgeEngine.items.forEach((item: IndexedChunk) => {
      const title: string = item.keys.lowerTitle;
      const text: string = item.lowerText;
      let score: number = 0;
      if (normalizedQuery.length >= 4 && text.includes(normalizedQuery)) {
        score += 30;
      }
      terms.forEach((term: string) => {
        if (title.includes(term)) {
          score += 14 + term.length;
        }
        const occurrences: number = KnowledgeEngine.countOccurrences(text, term);
        score += Math.min(occurrences, 5) * (2 + Math.min(term.length, 6));
      });
      score += KnowledgeEngine.topicBonus(normalizedQuery, item);
      score += KnowledgeEngine.regionBonus(normalizedQuery, item.keys);
      if (score > 0) {
        KnowledgeEngine.insertCandidate(ranked, new RankedChunk(item, score), maxCandidates);
      }
    });

    const selected: LawChunk[] = [];
    const documentHits: Map<string, number> = new Map<string, number>();
    const titleHits: Map<string, number> = new Map<string, number>();
    for (let index: number = 0; index < ranked.length && selected.length < limit; index++) {
      const candidate: LawChunk = ranked[index].item.chunk;
      const hitCount: number = documentHits.get(candidate.documentId) ?? 0;
      const title: string = ranked[index].item.keys.normalizedTitle;
      const coreLaw: boolean = ranked[index].item.keys.coreLaborContractLaw;
      const perDocumentLimit: number = coreLaw ? limit : 2;
      if (hitCount >= perDocumentLimit) {
        continue;
      }
      const sameTitleCount: number = titleHits.get(title) ?? 0;
      const perTitleLimit: number = coreLaw ? limit : 2;
      if (sameTitleCount >= perTitleLimit) {
        continue;
      }
      selected.push(candidate);
      documentHits.set(candidate.documentId, hitCount + 1);
      titleHits.set(title, sameTitleCount + 1);
    }
    if (selected.length === 0) {
      return new KnowledgeResult('', []);
    }

    const citations: LawCitation[] = [];
    const contextParts: string[] = [];
    selected.forEach((chunk: LawChunk, index: number) => {
      const citation: LawCitation = new LawCitation('K' + (index + 1).toString(), chunk);
      citations.push(citation);
      contextParts.push(
        '[' + citation.id + '] ' + citation.title + ' ' + citation.article
          + '\n状态：' + citation.status
          + (citation.effectiveDate.length > 0 ? '；生效日期：' + citation.effectiveDate : '')
          + '\n来源文件：' + citation.source
          + '\n正文：' + citation.excerpt
      );
    });
    return new KnowledgeResult(contextParts.join('\n\n'), citations);
  }

  static validateAnswer(answer: string, citations: LawCitation[]): string {
    let validated: string = answer
      .replace(/\*/g, '')
      .replace(/^\s*#{1,6}\s*/gm, '')
      .replace(/`/g, '');
    let cursor: number = 0;
    while (cursor < validated.length) {
      const start: number = validated.indexOf('[K', cursor);
      if (start < 0) {
        break;
      }
      const end: number = validated.indexOf(']', start + 2);
      if (end < 0) {
        break;
      }
      const rawId: string = validated.substring(start + 2, end);
      const numericId: number = Number(rawId);
      const isInteger: boolean = Number.isInteger(numericId);
      if (!isInteger || numericId < 1 || numericId > citations.length) {
        validated = validated.substring(0, start) + validated.substring(end + 1);
        cursor = start;
      } else {
        cursor = end + 1;
      }
    }
    return validated.trim();
  }

  static normalize(value: string): string {
    return value.toLowerCase().replace(/[\s，。！？、；：“”‘’（）()《》【】,.!?;:'"]/g, '');
  }

  private static addTerm(terms: string[], term: string): void {
    const normalized: string = KnowledgeEngine.normalize(term);
    if (normalized.length >= 2 && !terms.includes(normalized)) {
      terms.push(normalized);
    }
  }

  private static queryTerms(query: string): string[] {
    const normalized: string = KnowledgeEngine.normalize(query);
    const terms: string[] = [];
    const expansions: string[][] = [
      ['拖欠', '工资', '劳动报酬', '工资支付'],
      ['辞退', '解除劳动合同', '违法解除', '经济补偿', '赔偿金'],
      ['开除', '解除劳动合同', '违法解除', '赔偿金'],
      ['未签', '书面劳动合同', '二倍工资', '双倍工资'],
      ['没有签订', '书面劳动合同', '二倍工资', '双倍工资'],
      ['未订立', '书面劳动合同', '二倍工资', '双倍工资'],
      ['加班', '延长工作时间', '加班工资', '考勤'],
      ['工伤', '工伤认定', '工伤保险', '停工留薪'],
      ['年假', '带薪年休假', '未休年休假'],
      ['仲裁', '劳动争议', '仲裁时效', '调解仲裁'],
      ['社保', '社会保险', '社会保险费'],
      ['试用期', '试用期', '解除劳动合同'],
      ['竞业', '竞业限制', '经济补偿']
    ];
    expansions.forEach((group: string[]) => {
      if (normalized.includes(KnowledgeEngine.normalize(group[0]))) {
        group.forEach((term: string) => KnowledgeEngine.addTerm(terms, term));
      }
    });
    const legalPhrases: string[] = [
      '拖欠工资', '劳动报酬', '书面劳动合同', '二倍工资', '双倍工资',
      '解除劳动合同', '违法解除', '经济补偿', '赔偿金', '劳动仲裁',
      '仲裁时效', '加班工资', '社会保险', '工伤认定', '带薪年休假'
    ];
    legalPhrases.forEach((phrase: string) => {
      if (normalized.includes(KnowledgeEngine.normalize(phrase))) {
        KnowledgeEngine.addTerm(terms, phrase);
      }
    });
    if (terms.length > 0) {
      return terms;
    }
    const fallback: string =
      normalized.length > 80 ? normalized.substring(0, 80) : normalized;
    // Long free-form case descriptions previously produced more than 200
    // n-grams. Scanning all of them across 50k+ chunks could exhaust a phone's
    // memory or block the UI thread long enough for the process to be killed.
    const maxFallbackTerms: number = 24;
    for (let size: number = 4; size >= 2 && terms.length < maxFallbackTerms; size--) {
      const available: number = Math.max(fallback.length - size + 1, 1);
      const remaining: number = maxFallbackTerms - terms.length;
      const step: number = Math.max(1, Math.floor(available / Math.max(remaining, 1)));
      for (let index: number = 0;
        index + size <= fallback.length && terms.length < maxFallbackTerms;
        index += step) {
        KnowledgeEngine.addTerm(terms, fallback.substring(index, index + size));
      }
    }
    return terms;
  }

  private static insertCandidate(
    ranked: RankedChunk[],
    candidate: RankedChunk,
    maxCandidates: number
  ): void {
    if (ranked.length >= maxCandidates &&
      candidate.score <= ranked[ranked.length - 1].score) {
      return;
    }
    let low: number = 0;
    let high: number = ranked.length;
    while (low < high) {
      const middle: number = Math.floor((low + high) / 2);
      if (ranked[middle].score >= candidate.score) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    ranked.splice(low, 0, candidate);
    if (ranked.length > maxCandidates) {
      ranked.pop();
    }
  }

  private static countOccurrences(text: string, term: string): number {
    let count: number = 0;
    let position: number = 0;
    while (position < text.length) {
      const found: number = text.indexOf(term, position);
      if (found < 0) {
        break;
      }
      count++;
      position = found + term.length;
    }
    return count;
  }

  private static articleIs(chunk: LawChunk, article: string): boolean {
    return chunk.article === article;
  }

  static isCoreLaborContractLaw(normalizedTitle: string): boolean {
    return normalizedTitle.includes('中华人民共和国劳动合同法') &&
      !normalizedTitle.includes('实施条例');
  }

  private static topicBonus(query: string, item: IndexedChunk): number {
    const chunk: LawChunk = item.chunk;
    const title: string = item.keys.normalizedTitle;
    const isCoreLaborContractLaw: boolean = item.keys.coreLaborContractLaw;
    let bonus: number = 0;
    if (query.includes('工资') || query.includes('欠薪') || query.includes('劳动报酬')) {
      if (title.includes('中华人民共和国劳动法') &&
        KnowledgeEngine.articleIs(chunk, '第五十条')) {
        bonus += 140;
      }
      if (isCoreLaborContractLaw &&
        KnowledgeEngine.articleIs(chunk, '第八十五条')) {
        bonus += 130;
      }
      if (title.includes('劳动争议调解仲裁法') &&
        KnowledgeEngine.articleIs(chunk, '第二十七条')) {
        bonus += 115;
      }
      if (title.includes('工资支付暂行规定')) {
        bonus += 45;
      }
      if (!query.includes('农民工') && title.includes('保障农民工工资支付条例')) {
        bonus -= 35;
      }
    }
    if (query.includes('辞退') || query.includes('开除') || query.includes('解除')) {
      if (isCoreLaborContractLaw) {
        if (KnowledgeEngine.articleIs(chunk, '第四十八条')) {
          bonus += 250;
        } else if (KnowledgeEngine.articleIs(chunk, '第八十七条')) {
          bonus += 245;
        } else if (KnowledgeEngine.articleIs(chunk, '第三十九条') ||
          KnowledgeEngine.articleIs(chunk, '第四十条')) {
          bonus += 210;
        } else if (KnowledgeEngine.articleIs(chunk, '第四十七条')) {
          bonus += 190;
        } else if (KnowledgeEngine.articleIs(chunk, '第四十三条')) {
          bonus += 140;
        }
      }
    }
    if (query.includes('未签') || query.includes('没有签') ||
      query.includes('未订立') || query.includes('书面合同') ||
      query.includes('书面劳动合同')) {
      if (isCoreLaborContractLaw) {
        if (KnowledgeEngine.articleIs(chunk, '第八十二条')) {
          bonus += 260;
        } else if (KnowledgeEngine.articleIs(chunk, '第十条')) {
          bonus += 230;
        } else if (KnowledgeEngine.articleIs(chunk, '第十四条')) {
          bonus += 210;
        }
      }
      if (title.includes('中华人民共和国劳动合同法实施条例') &&
        (KnowledgeEngine.articleIs(chunk, '第六条') ||
          KnowledgeEngine.articleIs(chunk, '第七条'))) {
        bonus += 190;
      }
    }
    if (query.includes('加班') || query.includes('延长工作时间')) {
      if (title.includes('中华人民共和国劳动法') &&
        (KnowledgeEngine.articleIs(chunk, '第四十一条') ||
          KnowledgeEngine.articleIs(chunk, '第四十四条'))) {
        bonus += 135;
      }
      if (isCoreLaborContractLaw &&
        KnowledgeEngine.articleIs(chunk, '第八十五条')) {
        bonus += 95;
      }
      if (title.includes('工资支付暂行规定') &&
        KnowledgeEngine.articleIs(chunk, '第十三条')) {
        bonus += 120;
      }
    }
    return bonus;
  }

  private static regionBonus(query: string, keys: DocumentKeys): number {
    if (keys.normalizedRegion.length === 0) {
      return 0;
    }
    if (query.includes(keys.normalizedRegion) ||
      (keys.shortRegion.length >= 2 && query.includes(keys.shortRegion))) {
      return 90;
    }
    return -8;
  }
}
