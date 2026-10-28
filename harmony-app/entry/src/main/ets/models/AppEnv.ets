import { ApiConfig } from './AppModels';
import { LIGHT, ThemeColors } from '../theme/Theme';

// App-wide settings every section reads: theme, motion, keyboard, the model
// service and how reasoning is shown. Index provides it as 'env'.
@Observed
export class AppEnv {
  cx: ThemeColors = LIGHT;
  isDark: boolean = false;
  // 0 follow the system, 1 light, 2 dark.
  themeMode: number = 0;
  reduceMotion: boolean = false;
  keyboardVisible: boolean = false;
  // The user's own model service, edited in 我的.
  baseUrl: string = 'https://api.openai.com/v1';
  modelName: string = '';
  apiKey: string = '';
  // The service the app ships with (undefined in builds without one), whether
  // it is in use, and how many requests it served today.
  builtin: ApiConfig | undefined = undefined;
  useBuiltin: boolean = false;
  quotaUsed: number = 0;
  showReasoning: boolean = true;
  autoExpandReasoning: boolean = true;

  usingBuiltin(): boolean {
    return this.useBuiltin && this.builtin !== undefined;
  }

  // The service requests go to.
  config(): ApiConfig {
    return this.usingBuiltin() ? this.builtin! : this.customConfig();
  }

  customConfig(): ApiConfig {
    return new ApiConfig(this.baseUrl, this.modelName, this.apiKey);
  }
}
