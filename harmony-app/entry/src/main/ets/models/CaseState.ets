import { ChatMessage, LawCitation } from './AppModels';
import { CaseRecord, DossierState } from './ChatState';
import { CaseArchive } from '../services/CaseArchive';

// The 维权 case being worked on: its dossier fields and report, with the
// archived cases. Its conversation is a ChatSession of its own.
@Observed
export class CaseState {
  id: string = '';
  location: string = '';
  company: string = '';
  salary: string = '';
  timeline: string = '';
  request: string = '';
  details: string = '';
  report: string = '';
  reportCitations: LawCitation[] = [];
  // Percentage of the six dossier fields filled.
  progress: number = 0;
  history: CaseRecord[] = [];

  dossier(): DossierState {
    const dossier: DossierState = new DossierState();
    dossier.location = this.location;
    dossier.company = this.company;
    dossier.salary = this.salary;
    dossier.timeline = this.timeline;
    dossier.request = this.request;
    dossier.details = this.details;
    dossier.report = this.report;
    dossier.reportCitations = this.reportCitations;
    return dossier;
  }

  // Replaces the fields with a saved dossier (or an empty one).
  setDossier(dossier: DossierState): void {
    this.location = dossier.location;
    this.company = dossier.company;
    this.salary = dossier.salary;
    this.timeline = dossier.timeline;
    this.request = dossier.request;
    this.details = dossier.details;
    this.report = dossier.report;
    this.reportCitations = dossier.reportCitations;
  }

  fieldFilled(index: number): boolean {
    return CaseArchive.fieldFilled(this.dossier(), index);
  }

  hasContent(messages: ChatMessage[]): boolean {
    return CaseArchive.hasContent(messages, this.dossier());
  }

  title(messages: ChatMessage[]): string {
    return this.hasContent(messages) ? CaseArchive.title(messages, this.dossier()) : '新案件';
  }
}
