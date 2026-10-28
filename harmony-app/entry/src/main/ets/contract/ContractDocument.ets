import { ClauseAnchor, Finding, LEVEL_ARTICLE, LEVEL_CHAPTER, SEVERITIES, WHOLE_CONTRACT } from './ContractTypes';

// Lays the contract text out for the annotated view: one entry per line, each
// cut into pieces that are plain or belong to a finding. Pure logic, tested in
// tools/harmony/contract-rules.

export class DocSegment {
  text: string;
  // Index into the report's findings, or -1 for plain text.
  finding: number;
  severity: string;

  constructor(text: string, finding: number, severity: string) {
    this.text = text;
    this.finding = finding;
    this.severity = severity;
  }
}

export class DocLine {
  index: number;
  start: number;
  heading: boolean;
  segments: DocSegment[];
  // Findings on the clause that starts on this line but have no exact place
  // (saved before highlighting existed, or a quote that was not found).
  clauseFindings: number[];

  constructor(index: number, start: number, heading: boolean, segments: DocSegment[], clauseFindings: number[]) {
    this.index = index;
    this.start = start;
    this.heading = heading;
    this.segments = segments;
    this.clauseFindings = clauseFindings;
  }
}

export class ContractDocument {
  static lines(text: string, anchors: ClauseAnchor[], findings: Finding[]): DocLine[] {
    const out: DocLine[] = [];
    let pos: number = 0;
    const raw: string[] = text.split('\n');
    for (let i: number = 0; i < raw.length; i++) {
      const lineText: string = raw[i];
      const start: number = pos;
      const end: number = pos + lineText.length;
      pos = end + 1;
      if (lineText.trim().length === 0) {
        continue;
      }
      const anchor: ClauseAnchor | undefined = anchors.find((a: ClauseAnchor) => a.start >= start && a.start < end &&
        text.substring(start, a.start).trim().length === 0);
      const heading: boolean = anchor !== undefined &&
        (anchor.level === LEVEL_ARTICLE || anchor.level === LEVEL_CHAPTER);
      const clauseFindings: number[] = [];
      if (anchor !== undefined) {
        findings.forEach((f: Finding, k: number) => {
          if (f.anchorId === anchor.anchorId && f.start < 0) {
            clauseFindings.push(k);
          }
        });
      }
      out.push(new DocLine(out.length, start, heading, ContractDocument.cut(lineText, start, end, findings),
        clauseFindings));
    }
    return out;
  }

  // Findings about the contract as a whole, shown above the text.
  static wholeContract(findings: Finding[]): number[] {
    const out: number[] = [];
    findings.forEach((f: Finding, k: number) => {
      if (f.anchorId === WHOLE_CONTRACT) {
        out.push(k);
      }
    });
    return out;
  }

  // Reading order for the 上一处 / 下一处 navigation: whole-contract findings
  // first, then by position in the text.
  static order(findings: Finding[], anchors: ClauseAnchor[]): number[] {
    const position: (f: Finding) => number = (f: Finding): number => {
      if (f.start >= 0) {
        return f.start;
      }
      const a: ClauseAnchor | undefined = anchors.find((x: ClauseAnchor) => x.anchorId === f.anchorId);
      return a !== undefined ? a.start : -1;
    };
    return findings.map((f: Finding, k: number) => k).sort((a: number, b: number) => {
      const d: number = position(findings[a]) - position(findings[b]);
      return d !== 0 ? d : SEVERITIES.indexOf(findings[a].severity) - SEVERITIES.indexOf(findings[b].severity);
    });
  }

  // Splits one line at every finding boundary; where findings overlap, the
  // more severe one owns the piece.
  private static cut(lineText: string, start: number, end: number, findings: Finding[]): DocSegment[] {
    const cuts: number[] = [start, end];
    findings.forEach((f: Finding) => {
      if (f.start >= 0 && f.end > start && f.start < end) {
        cuts.push(Math.max(start, f.start));
        cuts.push(Math.min(end, f.end));
      }
    });
    const points: number[] = cuts.filter((p: number, i: number) => cuts.indexOf(p) === i).sort((a: number, b: number) => a - b);
    const segments: DocSegment[] = [];
    for (let i: number = 0; i + 1 < points.length; i++) {
      const a: number = points[i];
      const b: number = points[i + 1];
      let best: number = -1;
      findings.forEach((f: Finding, k: number) => {
        if (f.start >= 0 && f.start <= a && f.end >= b &&
          (best < 0 || SEVERITIES.indexOf(f.severity) < SEVERITIES.indexOf(findings[best].severity))) {
          best = k;
        }
      });
      const piece: string = lineText.substring(a - start, b - start);
      const last: DocSegment | undefined = segments.length > 0 ? segments[segments.length - 1] : undefined;
      if (last !== undefined && last.finding === best) {
        last.text += piece;
      } else {
        segments.push(new DocSegment(piece, best, best >= 0 ? findings[best].severity : ''));
      }
    }
    return segments;
  }
}
