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
  baseUrl: string = 'https://api.openai.com/v1';
  modelName: string = '';
  apiKey: string = '';
  showReasoning: boolean = true;
  autoExpandReasoning: boolean = true;

  config(): ApiConfig {
    return new ApiConfig(this.baseUrl, this.modelName, this.apiKey);
  }
}
