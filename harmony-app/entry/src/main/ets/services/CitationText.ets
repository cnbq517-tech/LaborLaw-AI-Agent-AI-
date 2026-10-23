import { LawCitation } from '../models/AppModels';

// Splits model answers into plain text and [Kn] citation markers so the UI can
// render markers as tappable chips, finds the quoted sentence in a cited
// excerpt so the detail sheet can highlight it, and builds clipboard text.

const CLAUSE_BREAKS: string = '。！？；\n';
// Source documents wrap lines mid-sentence, so newlines are not sentence breaks here.
const EXCERPT_BREAKS: string = '。！？；';
const MIN_MATCH: number = 6;
const MAX_MATCH: number = 32;
const CHIP_PADDING: string = '\u00A0';
const COPY_FOOTER: string = '—— 来自劳动权益助手，仅供参考，不构成法律意见';

export class AnswerSegment {
  text: string;
  // Zero-based index into the message's citations, or -1 for plain text.
  citationIndex: number;

  constructor(text: string, citationIndex: number) {
    this.text = text;
    this.citationIndex = citationIndex;
  }
}

export class HighlightRange {
  start: number;
  end: number;

  constructor(start: number, end: number) {
    this.start = start;
    this.end = end;
  }
}

export class CitationText {
  // Text shown for a citation chip. Selection offsets reported by the Text
  // component count these characters, so copy mapping must use the same label.
  static chipLabel(citationIndex: number): string {
    return CHIP_PADDING + (citationIndex + 1).toString() + CHIP_PADDING;
  }

  // Clipboard text for a whole answer (end < 0) or for a selection measured in
  // rendered characters. Plain copies drop citation chips; copies with
  // citations turn chips into [依据n] and list only the citations used.
  static copyText(content: string, citations: LawCitation[], withCitations: boolean,
    start: number = 0, end: number = -1): string {
    const segments: AnswerSegment[] = CitationText.split(content, citations.length);
    const used: boolean[] = citations.map((): boolean => false);
    let output: string = '';
    let position: number = 0;
    segments.forEach((segment: AnswerSegment) => {
      const rendered: string = segment.citationIndex < 0 ? segment.text :
        CitationText.chipLabel(segment.citationIndex);
      const from: number = Math.max(start, position);
      const to: number = end < 0 ? position + rendered.length : Math.min(end, position + rendered.length);
      if (to > from) {
        if (segment.citationIndex < 0) {
          output += rendered.substring(from - position, to - position);
        } else if (withCitations) {
          output += '[依据' + (segment.citationIndex + 1).toString() + ']';
          used[segment.citationIndex] = true;
        }
      }
      position += rendered.length;
    });
    output = output.trim();
    if (!withCitations) {
      return output;
    }
    const references: string[] = [];
    used.forEach((isUsed: boolean, index: number) => {
      if (isUsed) {
        references.push('[依据' + (index + 1).toString() + ']' + CitationText.referenceLabel(citations[index]));
      }
    });
    if (references.length > 0) {
      output += '\n\n参考依据：\n' + references.join('\n');
    }
    return output + '\n\n' + COPY_FOOTER;
  }

  static usedCitationCount(content: string, citationCount: number): number {
    const used: Set<number> = new Set<number>();
    CitationText.split(content, citationCount).forEach((segment: AnswerSegment) => {
      if (segment.citationIndex >= 0) {
        used.add(segment.citationIndex);
      }
    });
    return used.size;
  }

  private static referenceLabel(citation: LawCitation): string {
    // Keep a title's own book-title marks, using the nested form inside 《》.
    const title: string = citation.title.trim().replace(/^《/, '').replace(/》$/, '')
      .replace(/《/g, '〈').replace(/》/g, '〉');
    const article: string = citation.article.includes('片段') ? '' : citation.article;
    return '《' + title + '》' + article;
  }

  static split(content: string, citationCount: number): AnswerSegment[] {
    const segments: AnswerSegment[] = [];
    let plainStart: number = 0;
    let cursor: number = 0;
    while (cursor < content.length) {
      const start: number = content.indexOf('[K', cursor);
      if (start < 0) {
        break;
      }
      const end: number = content.indexOf(']', start + 2);
      if (end < 0) {
        break;
      }
      const index: number = Number(content.substring(start + 2, end)) - 1;
      if (!Number.isInteger(index) || index < 0 || index >= citationCount) {
        cursor = start + 2;
        continue;
      }
      if (start > plainStart) {
        segments.push(new AnswerSegment(content.substring(plainStart, start), -1));
      }
      segments.push(new AnswerSegment('', index));
      plainStart = end + 1;
      cursor = end + 1;
    }
    if (plainStart < content.length) {
      segments.push(new AnswerSegment(content.substring(plainStart), -1));
    }
    return segments;
  }

  // For each citation, the clause right before its first marker. That is the
  // claim the citation is supposed to support.
  static leads(content: string, citationCount: number): string[] {
    const leads: string[] = [];
    for (let index: number = 0; index < citationCount; index++) {
      leads.push('');
    }
    let text: string = '';
    CitationText.split(content, citationCount).forEach((segment: AnswerSegment) => {
      if (segment.citationIndex < 0) {
        text += segment.text;
        return;
      }
      if (leads[segment.citationIndex].length === 0) {
        leads[segment.citationIndex] = CitationText.lastClause(text);
      }
    });
    return leads;
  }

  // Finds the longest stretch of the claim that appears verbatim in the
  // excerpt and widens it to the surrounding sentence. Models often paraphrase,
  // so no match is a normal outcome.
  static highlight(excerpt: string, lead: string): HighlightRange | undefined {
    const claim: string = lead.replace(/\s/g, '');
    if (claim.length < MIN_MATCH || excerpt.length === 0) {
      return undefined;
    }
    for (let size: number = Math.min(claim.length, MAX_MATCH); size >= MIN_MATCH; size--) {
      for (let offset: number = 0; offset + size <= claim.length; offset++) {
        const found: number = excerpt.indexOf(claim.substring(offset, offset + size));
        if (found >= 0) {
          return CitationText.sentenceAround(excerpt, found, found + size);
        }
      }
    }
    return undefined;
  }

  private static lastClause(text: string): string {
    let end: number = text.length;
    while (end > 0 && (CLAUSE_BREAKS.includes(text.charAt(end - 1)) || text.charAt(end - 1) === ' ')) {
      end--;
    }
    let start: number = end;
    while (start > 0 && !CLAUSE_BREAKS.includes(text.charAt(start - 1))) {
      start--;
    }
    return text.substring(start, end).trim();
  }

  private static sentenceAround(excerpt: string, from: number, to: number): HighlightRange {
    let start: number = from;
    while (start > 0 && !EXCERPT_BREAKS.includes(excerpt.charAt(start - 1))) {
      start--;
    }
    let end: number = to;
    while (end < excerpt.length && !EXCERPT_BREAKS.includes(excerpt.charAt(end))) {
      end++;
    }
    if (end < excerpt.length) {
      end++;
    }
    return new HighlightRange(start, end);
  }
}
