import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileIo } from '@kit.CoreFileKit';

// Where the user's records live: the app's files directory, or in 演示模式 a
// separate one holding the sample case, contract and evidence. The two never
// mix; switching restarts the app so every page reloads from the other.

const PREFERENCES_NAME: string = 'model_config';
const DEMO_KEY: string = 'demo_mode';
const DEMO_DIR: string = 'demo';

export class DataSpace {
  // Read once at start-up, before any page loads its records.
  static demo: boolean = false;

  static init(context: common.Context): void {
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
      DataSpace.demo = store.getSync(DEMO_KEY, false) as boolean;
      if (DataSpace.demo && !fileIo.accessSync(context.filesDir + '/' + DEMO_DIR)) {
        fileIo.mkdirSync(context.filesDir + '/' + DEMO_DIR);
      }
    } catch (error) {
      DataSpace.demo = false;
    }
  }

  // The directory records are read from and written to.
  static root(context: common.Context): string {
    return DataSpace.demo ? context.filesDir + '/' + DEMO_DIR : context.filesDir;
  }

  // Takes effect at the next start.
  static async setDemo(context: common.Context, on: boolean): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(context, PREFERENCES_NAME);
    await store.put(DEMO_KEY, on);
    await store.flush();
  }

  // Leaving 演示模式 throws the sample records away, so the next time starts
  // fresh from the samples.
  static async clearDemo(context: common.Context): Promise<void> {
    const dir: string = context.filesDir + '/' + DEMO_DIR;
    if (await fileIo.access(dir)) {
      await fileIo.rmdir(dir);
    }
  }
}
