// Splits model answers into plain text and [Kn] citation markers so the UI can
// render markers as tappable chips, and finds the quoted sentence in a cited
// excerpt so the detail sheet can highlight it.

const CLAUSE_BREAKS: string = '。！？；\n';
// Source documents wrap lines mid-sentence, so newlines are not sentence breaks here.
const EXCERPT_BREAKS: string = '。！？；';
const MIN_MATCH: number = 6;
const MAX_MATCH: number = 32;

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
