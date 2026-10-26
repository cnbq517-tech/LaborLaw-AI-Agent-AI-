const OPEN_TAG: string = '<think>';
const CLOSE_TAG: string = '</think>';

// Splits streamed content into answer text and reasoning wrapped in
// <think>...</think>, as some self-hosted reasoning models emit it. Tags may
// arrive split across chunks, so a possible partial tag at the end of a chunk
// is held back until the next one.
export class ThinkTagParser {
  answer: string = '';
  reasoning: string = '';
  private inThink: boolean = false;
  private carry: string = '';

  push(text: string): void {
    let rest: string = this.carry + text;
    this.carry = '';
    while (rest.length > 0) {
      const tag: string = this.inThink ? CLOSE_TAG : OPEN_TAG;
      const found: number = rest.indexOf(tag);
      if (found < 0) {
        const keep: number = ThinkTagParser.partialTagLength(rest, tag);
        this.append(rest.substring(0, rest.length - keep));
        this.carry = rest.substring(rest.length - keep);
        return;
      }
      this.append(rest.substring(0, found));
      rest = rest.substring(found + tag.length);
      this.inThink = !this.inThink;
    }
  }

  // Flushes text held back as a possible partial tag.
  finish(): void {
    this.append(this.carry);
    this.carry = '';
  }

  private append(text: string): void {
    if (this.inThink) {
      this.reasoning += text;
    } else {
      this.answer += text;
    }
  }

  // Length of the longest suffix of `text` that is a prefix of `tag`.
  private static partialTagLength(text: string, tag: string): number {
    for (let length: number = Math.min(tag.length - 1, text.length); length > 0; length--) {
      if (text.endsWith(tag.substring(0, length))) {
        return length;
      }
    }
    return 0;
  }
}
