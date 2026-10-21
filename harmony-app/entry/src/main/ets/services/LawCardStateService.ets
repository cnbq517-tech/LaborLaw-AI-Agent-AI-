import { preferences } from '@kit.ArkData';
import { formBindingData, formProvider } from '@kit.FormKit';
import { LAW_CARD_TIPS, LawCardTip } from '../models/LawCardTip';

const PREFERENCES_NAME: string = 'law_card_state';
const FORM_ID_KEY: string = 'form_id';
const DOCUMENT_COUNT_KEY: string = 'document_count';
const SEARCHABLE_COUNT_KEY: string = 'searchable_count';
const RECENT_CONSULTATION_KEY: string = 'recent_consultation';
const TIP_INDEX_KEY: string = 'tip_index';
const TIP_VISIBLE_KEY: string = 'tip_visible';
const DEFAULT_DOCUMENT_COUNT: number = 2790;
const DEFAULT_SEARCHABLE_COUNT: number = 2761;

export class LawCardStateService {
  static bindingData(context: Context): formBindingData.FormBindingData {
    let documentCount: number = DEFAULT_DOCUMENT_COUNT;
    let searchableCount: number = DEFAULT_SEARCHABLE_COUNT;
    let recentConsultation: string = '尚无咨询';
    let tipIndex: number = 0;
    let tipVisible: boolean = false;
    try {
      const store: preferences.Preferences =
        preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
      documentCount = store.getSync(DOCUMENT_COUNT_KEY, DEFAULT_DOCUMENT_COUNT) as number;
      searchableCount = store.getSync(SEARCHABLE_COUNT_KEY, DEFAULT_SEARCHABLE_COUNT) as number;
      recentConsultation = store.getSync(RECENT_CONSULTATION_KEY, '尚无咨询') as string;
      tipIndex = store.getSync(TIP_INDEX_KEY, 0) as number;
      tipVisible = store.getSync(TIP_VISIBLE_KEY, false) as boolean;
    } catch (error) {
      // 首次创建或本地状态不可读时使用内置知识库的安全默认值。
    }
    const tip: LawCardTip = LAW_CARD_TIPS[LawCardStateService.safeTipIndex(tipIndex)];
    return formBindingData.createFormBindingData({
      documentCount: documentCount,
      searchableDocumentCount: searchableCount,
      statusText: '本地资料已就绪',
      recentConsultation: recentConsultation,
      tipVisible: tipVisible,
      tipTitle: tip.title,
      tipBody: tip.body,
      tipScenario: tip.scenario
    });
  }

  static currentTip(context: Context): LawCardTip {
    try {
      const store: preferences.Preferences =
        preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
      return LAW_CARD_TIPS[LawCardStateService.safeTipIndex(store.getSync(TIP_INDEX_KEY, 0) as number)];
    } catch (error) {
      return LAW_CARD_TIPS[0];
    }
  }

  static async nextTip(context: Context, formId: string): Promise<LawCardTip> {
    let tip: LawCardTip = LAW_CARD_TIPS[0];
    try {
      const store: preferences.Preferences =
        preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
      const previous: number = store.getSync(TIP_INDEX_KEY, -1) as number;
      const index: number = previous < 0 ? 0 :
        (LawCardStateService.safeTipIndex(previous) + 1) % LAW_CARD_TIPS.length;
      tip = LAW_CARD_TIPS[index];
      store.putSync(TIP_INDEX_KEY, index);
      store.putSync(TIP_VISIBLE_KEY, true);
      store.flushSync();
    } catch (error) {
      // The static card stays usable even if preferences are unavailable.
    }
    await LawCardStateService.updateForm(context, formId);
    return tip;
  }

  static async hideTip(context: Context, formId: string): Promise<void> {
    try {
      const store: preferences.Preferences =
        preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
      store.putSync(TIP_VISIBLE_KEY, false);
      store.flushSync();
    } catch (error) {
      return;
    }
    await LawCardStateService.updateForm(context, formId);
  }

  private static safeTipIndex(index: number): number {
    return Number.isInteger(index) && index >= 0 && index < LAW_CARD_TIPS.length ? index : 0;
  }

  static registerForm(context: Context, formId: string): void {
    if (formId.length === 0) {
      return;
    }
    try {
      const store: preferences.Preferences =
        preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
      store.putSync(FORM_ID_KEY, formId);
      store.flushSync();
    } catch (error) {
      // 注册失败只会影响主动刷新，卡片仍可使用创建时的数据。
    }
  }

  static removeForm(context: Context, formId: string): void {
    try {
      const store: preferences.Preferences =
        preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
      const savedFormId: string = store.getSync(FORM_ID_KEY, '') as string;
      if (savedFormId === formId) {
        store.deleteSync(FORM_ID_KEY);
        store.flushSync();
      }
    } catch (error) {
      // 删除卡片时清理失败不会影响应用主流程。
    }
  }

  static async updateKnowledge(
    context: Context,
    documentCount: number,
    searchableCount: number
  ): Promise<void> {
    try {
      const store: preferences.Preferences =
        preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
      store.putSync(DOCUMENT_COUNT_KEY, documentCount);
      store.putSync(SEARCHABLE_COUNT_KEY, searchableCount);
      store.flushSync();
    } catch (error) {
      return;
    }
    await LawCardStateService.updateRegisteredForm(context);
  }

  static async recordConsultation(context: Context, topic: string): Promise<void> {
    try {
      const store: preferences.Preferences =
        preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
      store.putSync(RECENT_CONSULTATION_KEY, topic);
      store.flushSync();
    } catch (error) {
      return;
    }
    await LawCardStateService.updateRegisteredForm(context);
  }

  static topicForPrompt(prompt: string): string {
    if (prompt.includes('拖欠') || prompt.includes('欠薪')) {
      return '欠薪';
    }
    if (prompt.includes('没签') || prompt.includes('没有签') || prompt.includes('未签')) {
      return '未签合同';
    }
    if (prompt.includes('辞退') || prompt.includes('解除')) {
      return '违法解除';
    }
    if (prompt.includes('加班')) {
      return '加班';
    }
    return '普法问答';
  }

  static async updateForm(context: Context, formId: string): Promise<void> {
    if (formId.length === 0) {
      return;
    }
    try {
      await formProvider.updateForm(formId, LawCardStateService.bindingData(context));
    } catch (error) {
      // 卡片可能已被移除或暂时不可刷新。
    }
  }

  private static async updateRegisteredForm(context: Context): Promise<void> {
    let formId: string = '';
    try {
      const store: preferences.Preferences =
        preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
      formId = store.getSync(FORM_ID_KEY, '') as string;
    } catch (error) {
      return;
    }
    if (formId.length === 0) {
      return;
    }
    await LawCardStateService.updateForm(context, formId);
  }
}
