import { ApiConfig } from './AppModels';
import { LIGHT, ThemeColors } from '../theme/Theme';

// The widest the content gets on a tablet; wider windows center it.
export const CONTENT_MAX: number = 840;
// From this window width on, the layout is a tablet's.
const WIDE_WIDTH: number = 600;
// From this width on (a tablet held sideways), pages show two panes.
const SPLIT_WIDTH: number = 1000;

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
  // 光感强度, one of LIGHT_* in theme/Material.
  lightLevel: number = 0;
  showReasoning: boolean = true;
  // The window's width in vp.
  windowWidth: number = 0;
  autoExpandReasoning: boolean = true;

  // Room on each side of the content: 16 on a phone; on a tablet the content
  // keeps to a centered column of CONTENT_MAX.
  side(): number {
    return Math.max(16, (this.windowWidth - CONTENT_MAX) / 2);
  }

  wide(): boolean {
    return this.windowWidth >= WIDE_WIDTH;
  }

  split(): boolean {
    return this.windowWidth >= SPLIT_WIDTH;
  }

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
