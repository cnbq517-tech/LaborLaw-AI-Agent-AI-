import { ChatMessage, ChatRole } from '../models/AppModels';
import { CaseRecord, DossierState, MAX_ARCHIVED_CASES } from '../models/ChatState';

// Naming and archiving 维权 cases. Pure logic, tested in
// tools/harmony/logic-tests.

export class CaseArchive {
  // Whether dossier field 0–5 (发生地, 单位, 月薪, 时间, 诉求, 经过) is filled.
  static fieldFilled(dossier: DossierState, index: number): boolean {
    const values: string[] = [dossier.location, dossier.company, dossier.salary, dossier.timeline, dossier.request,
      dossier.details];
    return index >= 0 && index < values.length && values[index].trim().length > 0;
  }

  static hasDossierInput(dossier: DossierState): boolean {
    for (let index: number = 0; index < 6; index++) {
      if (CaseArchive.fieldFilled(dossier, index)) {
        return true;
      }
    }
    return false;
  }

  static hasContent(messages: ChatMessage[], dossier: DossierState): boolean {
    return messages.length > 0 || CaseArchive.hasDossierInput(dossier) || dossier.report.length > 0;
  }

  // A short name for a case: unit and claim when the dossier has them,
  // otherwise the employer named in the first message, else its first sentence.
  static title(messages: ChatMessage[], dossier: DossierState): string {
    if (dossier.company.trim().length > 0 && dossier.request.trim().length > 0) {
      return dossier.company.trim() + ' · ' + dossier.request.trim().substring(0, 12);
    }
    if (dossier.company.trim().length > 0) {
      return dossier.company.trim();
    }
    const first: ChatMessage | undefined = messages.find((m: ChatMessage) => m.role === ChatRole.USER);
    if (first === undefined) {
      return '新案件';
    }
    const unit: RegExpExecArray | null =
      /([一-龥A-Za-z]{2,16}?(?:有限责任公司|股份有限公司|有限公司|集团|公司|工厂))/.exec(first.content);
    if (unit !== null) {
      // "林某入职广州某某公司" → "广州某某公司".
      return unit[1].replace(/^.*?(入职|就职|任职|受雇于|在|于|被|与|到)/, '');
    }
    const sentence: string = first.content
      .replace(/^[\s\d一二三四五六七八九十]+[.、．)）]\s*/gm, '')
      .split(/[。！？\n]/).map((part: string) => part.trim()).find((part: string) => part.length >= 4) ?? '';
    return sentence.length > 18 ? sentence.substring(0, 18) + '…' : (sentence.length > 0 ? sentence : '新案件');
  }

  // The archive with this case at the top (replacing an older copy of it),
  // capped at MAX_ARCHIVED_CASES. An empty case is not archived.
  static archive(history: CaseRecord[], id: string, messages: ChatMessage[], dossier: DossierState,
    now: number = Date.now()): CaseRecord[] {
    if (!CaseArchive.hasContent(messages, dossier)) {
      return history;
    }
    const record: CaseRecord = new CaseRecord();
    record.id = id.length > 0 ? id : now.toString(36) + Math.floor(Math.random() * 1679616).toString(36);
    record.messages = messages;
    record.dossier = dossier;
    record.title = CaseArchive.title(messages, dossier);
    record.updatedAt = now;
    return [record].concat(history.filter((c: CaseRecord) => c.id !== record.id)).slice(0, MAX_ARCHIVED_CASES);
  }
}
