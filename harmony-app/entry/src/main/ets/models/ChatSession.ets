import { ChatMessage, FileAttachment, LawCitation } from './AppModels';

// One conversation with the model: what was said, what is being typed and
// sent, the answer streaming in, and the layout the pinned composer needs.
// 普法, 维权 and the dossier report each have one.
@Observed
export class ChatSession {
  messages: ChatMessage[] = [];
  input: string = '';
  attachment: FileAttachment = new FileAttachment();
  attachmentError: string = '';
  sending: boolean = false;
  error: string = '';
  // The answer and reasoning so far while a reply streams in.
  streaming: string = '';
  reasoning: string = '';
  thinkSeconds: number = 0;
  streamCitations: LawCitation[] = [];
  // After sending, the latest turn fills the viewport so its question can
  // sit at the top while the answer streams below.
  anchorTurn: boolean = false;
  viewportHeight: number = 0;
  contentHeight: number = 0;
  pinnedHeight: number = 0;
  showJump: boolean = false;
  // Scrolled down to read: the composer is folded into a button and the tab
  // bar steps aside. Ends at the top, or from that button.
  reading: boolean = false;

  canSend(): boolean {
    return (this.input.trim().length > 0 || this.attachment.name.length > 0) && !this.sending;
  }
}
