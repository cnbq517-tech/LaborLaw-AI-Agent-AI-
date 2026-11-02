import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;
// On a tablet everything is drawn this much larger than the system's display
// size, so text and controls read at arm's length on the big screen.
const TABLET_SCALE: number = 1.12;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.applyCardLaunch(want);
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.applyCardLaunch(want);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    this.configureImmersiveWindow(windowStage);
    this.scaleForTablet(windowStage);

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }

  // Follows the user's display size setting, one step larger.
  private scaleForTablet(windowStage: window.WindowStage): void {
    if (deviceInfo.deviceType !== 'tablet') {
      return;
    }
    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      windowStage.setCustomDensity(mainWindow.getWindowDensityInfo().systemDensity * TABLET_SCALE);
      mainWindow.on('systemDensityChange', (density: number) => {
        windowStage.setCustomDensity(density * TABLET_SCALE);
      });
    } catch (error) {
      hilog.error(DOMAIN, 'window', 'Failed to scale for the tablet. Cause: %{public}s', JSON.stringify(error));
    }
  }

  private configureImmersiveWindow(windowStage: window.WindowStage): void {
    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      mainWindow.setWindowLayoutFullScreen(true)
        .then(() => {
          return mainWindow.setWindowSystemBarProperties({
            statusBarColor: '#00000000',
            statusBarContentColor: '#20333A',
            isStatusBarLightIcon: false,
            navigationBarColor: '#00000000',
            navigationBarContentColor: '#20333A',
            isNavigationBarLightIcon: false
          });
        })
        .catch((error: Error) => {
          hilog.error(DOMAIN, 'window', 'Failed to configure immersive window. Cause: %{public}s',
            JSON.stringify(error));
        });
    } catch (error) {
      hilog.error(DOMAIN, 'window', 'Failed to obtain main window. Cause: %{public}s', JSON.stringify(error));
    }
  }

  private applyCardLaunch(want: Want): void {
    if (want.parameters === undefined) {
      return;
    }
    const scenarioValue: Object | undefined = want.parameters['scenario'];
    if (typeof scenarioValue !== 'string' || !this.isSupportedScenario(scenarioValue)) {
      return;
    }
    AppStorage.setOrCreate('cardScenario', scenarioValue);
    const sequence: number = AppStorage.get<number>('cardScenarioSequence') ?? 0;
    AppStorage.setOrCreate('cardScenarioSequence', sequence + 1);
  }

  private isSupportedScenario(scenario: string): boolean {
    return scenario === 'wage_arrears'
      || scenario === 'unsigned_contract'
      || scenario === 'illegal_termination'
      || scenario === 'overtime';
  }
}
