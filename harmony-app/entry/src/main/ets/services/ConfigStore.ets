import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { asset } from '@kit.AssetStoreKit';
import { ApiConfig } from '../models/AppModels';
import { ModelQuota } from './ModelQuota';

const PREFERENCES_NAME: string = 'model_config';
const BASE_URL_KEY: string = 'base_url';
const MODEL_KEY: string = 'model';
const DEFAULT_BASE_URL: string = 'https://api.openai.com/v1';
const API_KEY_ALIAS: string = 'laborlaw_ai_api_key';
const QUOTA_DAY_KEY: string = 'builtin_quota_day';
const QUOTA_USED_KEY: string = 'builtin_quota_used';
// Written by tools/harmony/builtin-service/set.sh; absent in builds without a
// built-in service.
const BUILTIN_FILE: string = 'builtin_service.json';

interface BuiltinFile {
  baseUrl: string;
  model: string;
  key: string;
}

// Today's use of the built-in service.
export class QuotaRecord {
  day: string;
  used: number;

  constructor(day: string, used: number) {
    this.day = day;
    this.used = used;
  }
}

export class ConfigStore {
  static async load(context: common.UIAbilityContext): Promise<ApiConfig> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, PREFERENCES_NAME);
      const baseUrl: string = await store.get(BASE_URL_KEY, DEFAULT_BASE_URL) as string;
      const model: string = await store.get(MODEL_KEY, '') as string;
      const apiKey: string = await ConfigStore.loadApiKey();
      return new ApiConfig(baseUrl, model, apiKey);
    } catch (error) {
      throw new Error('读取模型配置失败');
    }
  }

  static async save(context: common.UIAbilityContext, config: ApiConfig): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, PREFERENCES_NAME);
      await store.put(BASE_URL_KEY, config.baseUrl.trim());
      await store.put(MODEL_KEY, config.model.trim());
      await store.flush();
      await ConfigStore.saveApiKey(config.apiKey.trim());
    } catch (error) {
      throw new Error('保存模型配置失败');
    }
  }

  private static bytes(value: string): Uint8Array {
    return new util.TextEncoder().encodeInto(value);
  }

  private static text(value: Uint8Array): string {
    return new util.TextDecoder().decodeToString(value);
  }

  private static async saveApiKey(apiKey: string): Promise<void> {
    const attributes: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    attributes.set(asset.Tag.ALIAS, ConfigStore.bytes(API_KEY_ALIAS));
    attributes.set(asset.Tag.SECRET, ConfigStore.bytes(apiKey));
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    attributes.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
    attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    try {
      await asset.add(attributes);
    } catch (error) {
      throw new Error('安全保存 API Key 失败');
    }
  }

  // The model service the app ships with, or undefined when it has none.
  static async loadBuiltin(context: common.UIAbilityContext): Promise<ApiConfig | undefined> {
    try {
      const bytes: Uint8Array = await context.resourceManager.getRawFileContent(BUILTIN_FILE);
      const file: BuiltinFile = JSON.parse(ConfigStore.text(bytes)) as BuiltinFile;
      const config: ApiConfig = new ApiConfig(file.baseUrl ?? '', file.model ?? '', ModelQuota.decodeKey(file.key ?? ''));
      return config.baseUrl.length > 0 && config.model.length > 0 && config.apiKey.length > 0 ? config : undefined;
    } catch (error) {
      return undefined;
    }
  }

  static async loadQuota(context: common.UIAbilityContext): Promise<QuotaRecord> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, PREFERENCES_NAME);
      return new QuotaRecord(await store.get(QUOTA_DAY_KEY, '') as string, await store.get(QUOTA_USED_KEY, 0) as number);
    } catch (error) {
      return new QuotaRecord('', 0);
    }
  }

  static async saveQuota(context: common.UIAbilityContext, record: QuotaRecord): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(context, PREFERENCES_NAME);
    await store.put(QUOTA_DAY_KEY, record.day);
    await store.put(QUOTA_USED_KEY, record.used);
    await store.flush();
  }

  // Whether a flag was ever saved, to tell a first run from a choice.
  static async hasFlag(context: common.UIAbilityContext, key: string): Promise<boolean> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, PREFERENCES_NAME);
      return await store.has(key);
    } catch (error) {
      return false;
    }
  }

  // Display preferences that are not part of the model connection.
  static async loadFlag(context: common.UIAbilityContext, key: string, fallback: boolean): Promise<boolean> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, PREFERENCES_NAME);
      return await store.get(key, fallback) as boolean;
    } catch (error) {
      return fallback;
    }
  }

  static async saveFlag(context: common.UIAbilityContext, key: string, value: boolean): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(context, PREFERENCES_NAME);
    await store.put(key, value);
    await store.flush();
  }

  private static async loadApiKey(): Promise<string> {
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, ConfigStore.bytes(API_KEY_ALIAS));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const results: asset.AssetMap[] = await asset.query(query);
      if (results.length === 0) {
        return '';
      }
      const secret: asset.Value | undefined = results[0].get(asset.Tag.SECRET);
      if (secret instanceof Uint8Array) {
        return ConfigStore.text(secret);
      }
      return '';
    } catch (error) {
      return '';
    }
  }
}
