import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { SAMPLE_CONTRACT_CITY, SAMPLE_CONTRACT_NAME, SAMPLE_CONTRACT_TEXT } from '../contract/SampleContract';
import { FACT_YES, FactSheet } from '../contract/ContractTypes';
import { ChatMessage, ChatRole } from '../models/AppModels';
import { ChatState, DossierState, QuickSession } from '../models/ChatState';
import { EVIDENCE_SOURCE_PHOTO, EvidenceItem } from '../models/Evidence';
import { ChatStateStore } from './ChatStateStore';
import { ContractReport, ContractReviewService, ContractSource } from './ContractReviewService';
import { DataSpace } from './DataSpace';
import {
  DEMO_BACKUP_MARK,
  DEMO_COMPANY,
  DEMO_DETAILS,
  DEMO_LOCATION,
  DEMO_QUESTION,
  DEMO_REQUEST,
  DEMO_SALARY,
  DEMO_STORY,
  DEMO_TIMELINE,
  DemoBackups
} from './DemoScript';
import { EvidencePipeline } from './EvidencePipeline';
import { EvidenceStore } from './EvidenceStore';

// The finished story of 引导式演示 for 直接查看示例结果: the 普法 question, the
// 维权 case with its dossier and report, the sample contract's rule review,
// and three evidence images recognized on the device like any others. No
// model is called; the answers were recorded from real calls.

const SEEDED_FILE: string = '.seeded';
const DEMO_IMAGES: string[] = ['demo/payslip.jpg', 'demo/attendance.jpg', 'demo/chat.jpg'];

export class DemoData {
  // 直接查看示例结果 has filled the demo space (引导式演示 starts it empty).
  static async isSeeded(context: common.Context): Promise<boolean> {
    return DataSpace.demo && await fileIo.access(DataSpace.root(context) + '/' + SEEDED_FILE);
  }

  // Fills the demo space with the finished story; the answers are the
  // backups recorded from real calls.
  static async seed(context: common.UIAbilityContext): Promise<void> {
    if (!DataSpace.demo) {
      return;
    }
    const backups: DemoBackups = await DemoBackups.load(context);
    await DemoData.seedChat(context, backups);
    await DemoData.seedContract(context);
    await DemoData.seedEvidence(context);
    const file: fileIo.File = await fileIo.open(DataSpace.root(context) + '/' + SEEDED_FILE,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
    await fileIo.close(file);
  }

  private static async seedChat(context: common.UIAbilityContext, backups: DemoBackups): Promise<void> {
    const now: number = Date.now();
    const quick: ChatMessage[] = [new ChatMessage(ChatRole.USER, DEMO_QUESTION)];
    if (backups.quick !== undefined) {
      quick.push(backups.quick);
    }
    const history: QuickSession[] = [new QuickSession('demo-quick', DEMO_QUESTION, now - 3600000, quick)];
    await ChatStateStore.saveHistory(context, history);
    const state: ChatState = new ChatState();
    state.caseId = 'demo-case';
    state.caseMessages = [new ChatMessage(ChatRole.USER, DEMO_STORY)];
    if (backups.caseReply !== undefined) {
      state.caseMessages.push(backups.caseReply);
    }
    const dossier: DossierState = new DossierState();
    dossier.location = DEMO_LOCATION;
    dossier.company = DEMO_COMPANY;
    dossier.salary = DEMO_SALARY;
    dossier.timeline = DEMO_TIMELINE;
    dossier.request = DEMO_REQUEST;
    dossier.details = DEMO_DETAILS;
    dossier.report = backups.report.length > 0 ? DEMO_BACKUP_MARK + backups.report : '';
    dossier.reportCitations = backups.reportCitations;
    state.dossier = dossier;
    await ChatStateStore.save(context, state);
  }

  private static async seedContract(context: common.UIAbilityContext): Promise<void> {
    const facts: FactSheet = new FactSheet();
    facts.city = SAMPLE_CONTRACT_CITY;
    facts.position = '销售专员';
    facts.signed = FACT_YES;
    const report: ContractReport = ContractReviewService.local(
      new ContractSource(SAMPLE_CONTRACT_NAME, SAMPLE_CONTRACT_TEXT, false), facts);
    await ContractReviewService.save(context, [report]);
  }

  // The three sample images copied out of the package into dir, as URIs to
  // import.
  static async sampleImages(context: common.Context, dir: string): Promise<string[]> {
    if (!(await fileIo.access(dir))) {
      await fileIo.mkdir(dir);
    }
    const uris: string[] = [];
    for (let i: number = 0; i < DEMO_IMAGES.length; i++) {
      const bytes: Uint8Array = await context.resourceManager.getRawFileContent(DEMO_IMAGES[i]);
      const path: string = dir + '/sample-' + i.toString() + '.jpg';
      const file: fileIo.File = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY |
        fileIo.OpenMode.TRUNC);
      try {
        await fileIo.write(file.fd, bytes.buffer);
      } finally {
        await fileIo.close(file);
      }
      uris.push(fileUri.getUriFromPath(path));
    }
    return uris;
  }

  // Imported as photos; recognition runs when the evidence library opens.
  private static async seedEvidence(context: common.UIAbilityContext): Promise<void> {
    const dir: string = DataSpace.root(context) + '/samples';
    const uris: string[] = await DemoData.sampleImages(context, dir);
    const items: EvidenceItem[] = await EvidencePipeline.importUris(context, uris, EVIDENCE_SOURCE_PHOTO);
    await EvidenceStore.save(context, items);
    await fileIo.rmdir(dir);
  }
}
