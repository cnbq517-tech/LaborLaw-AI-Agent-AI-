import { common, Want } from '@kit.AbilityKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { harmonyShare, systemShare } from '@kit.ShareKit';

// 碰一碰: a phone tapped against a tablet sends evidence images straight into
// the tablet's evidence library (Share Kit's knock share and sandbox receive).
// The images go device to device, never through a cloud.

// The most images sent or received at once.
export const KNOCK_MAX: number = 9;

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'KnockShare';
// Received files land here before the library copies them in.
const INBOX_DIR: string = 'knock-inbox';

// What the sending side needs from the page on screen.
export class KnockSender {
  // The images to send now (sandbox paths); empty when nothing is chosen.
  files: () => string[] = () => [];
  // The phone was tapped with nothing chosen.
  onEmpty: () => void = () => {
  };
  onSent: (count: number) => void = (count: number) => {
  };
  onFailed: () => void = () => {
  };
}

// What the receiving side does with a tap and the files it brings.
export class KnockReceiver {
  // A phone tapped the screen here (px from the screen's top left).
  onKnock: (screenX: number, screenY: number) => void = (screenX: number, screenY: number) => {
  };
  // The images arrived, as file URIs in the inbox.
  onReceived: (uris: string[]) => void = (uris: string[]) => {
  };
  onFailed: () => void = () => {
  };
}

let sendWindow: number = -1;
let sendCallback: ((target: harmonyShare.SharableTarget) => void) | undefined = undefined;
let receiveWindow: number = -1;

function receiveRegistry(windowId: number): harmonyShare.RecvCapabilityRegistry {
  return {
    windowId: windowId,
    capabilities: [{ utd: utd.UniformDataType.IMAGE, maxSupportedCount: KNOCK_MAX }]
  };
}

function imageType(path: string): string {
  const dot: number = path.lastIndexOf('.');
  if (dot >= 0) {
    try {
      return utd.getUniformDataTypeByFilenameExtension(path.substring(dot).toLowerCase(), utd.UniformDataType.IMAGE);
    } catch (error) {
      return utd.UniformDataType.IMAGE;
    }
  }
  return utd.UniformDataType.IMAGE;
}

function record(path: string): systemShare.SharedRecord {
  const uri: string = fileUri.getUriFromPath(path);
  return { utd: imageType(path), uri: uri, thumbnailUri: uri };
}

function detail(error: Object): string {
  try {
    return JSON.stringify(error);
  } catch (e) {
    return String(error);
  }
}

// Images as one piece of shared data.
function sharedData(paths: string[]): systemShare.SharedData {
  const data: systemShare.SharedData = new systemShare.SharedData(record(paths[0]));
  paths.slice(1).forEach((path: string) => {
    data.addRecord(record(path));
  });
  return data;
}

export class KnockShare {
  // Where 碰一碰 is not available: the system share panel, whose 华为分享
  // sends to a nearby tablet (or any other app).
  static async showSharePanel(context: common.UIAbilityContext, paths: string[]): Promise<void> {
    const controller: systemShare.ShareController = new systemShare.ShareController(sharedData(paths));
    await controller.show(context, {
      selectionMode: systemShare.SelectionMode.BATCH,
      previewMode: systemShare.SharePreviewMode.DEFAULT
    });
  }

  // Images shared into the app (it is a share target for images): their URIs.
  static async sharedUris(want: Want): Promise<string[]> {
    const data: systemShare.SharedData = await systemShare.getSharedData(want);
    const uris: string[] = [];
    data.getRecords().forEach((r: systemShare.SharedRecord) => {
      if (r.uri !== undefined && r.uri.length > 0) {
        uris.push(r.uri);
      }
    });
    return uris.slice(0, KNOCK_MAX);
  }

  // Phone: while the evidence library is on screen, a tap on a tablet sends
  // what is chosen there. Send only, so two phones do not swap content.
  static startSending(windowId: number, sender: KnockSender): void {
    KnockShare.stopSending();
    const callback = (target: harmonyShare.SharableTarget): void => {
      const paths: string[] = sender.files().slice(0, KNOCK_MAX);
      if (paths.length === 0) {
        target.reject(harmonyShare.SharableErrorCode.NO_CONTENT_ERROR).catch(() => {
        });
        sender.onEmpty();
        return;
      }
      target.share(sharedData(paths)).then(() => {
        sender.onSent(paths.length);
      }).catch((error: Object) => {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Share failed: %{public}s', detail(error));
        sender.onFailed();
      });
    };
    try {
      harmonyShare.on('knockShare', { windowId: windowId, sendOnly: true }, callback);
      sendWindow = windowId;
      sendCallback = callback;
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Knock share unavailable: %{public}s', detail(error));
    }
  }

  static stopSending(): void {
    if (sendWindow < 0) {
      return;
    }
    try {
      harmonyShare.off('knockShare', { windowId: sendWindow, sendOnly: true }, sendCallback);
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Stop sending failed: %{public}s', detail(error));
    }
    sendWindow = -1;
    sendCallback = undefined;
  }

  // Tablet: images a phone taps over are received into the app's own inbox.
  static startReceiving(context: common.UIAbilityContext, windowId: number, receiver: KnockReceiver): void {
    KnockShare.stopReceiving();
    try {
      harmonyShare.on('dataReceive', receiveRegistry(windowId), (target: harmonyShare.ReceivableTarget) => {
        KnockShare.receive(context, target, receiver);
      });
      receiveWindow = windowId;
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Sandbox receive unavailable: %{public}s', detail(error));
    }
  }

  static stopReceiving(): void {
    if (receiveWindow < 0) {
      return;
    }
    try {
      harmonyShare.off('dataReceive', receiveRegistry(receiveWindow));
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Stop receiving failed: %{public}s', detail(error));
    }
    receiveWindow = -1;
  }

  static inbox(context: common.Context): string {
    return context.filesDir + '/' + INBOX_DIR;
  }

  // The library has copied the files in; the inbox copies can go.
  static async clearInbox(context: common.Context): Promise<void> {
    try {
      if (await fileIo.access(KnockShare.inbox(context))) {
        await fileIo.rmdir(KnockShare.inbox(context));
      }
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Clearing the inbox failed: %{public}s', detail(error));
    }
  }

  private static async receive(context: common.UIAbilityContext, target: harmonyShare.ReceivableTarget,
    receiver: KnockReceiver): Promise<void> {
    try {
      const point: harmonyShare.CoordinateInfo | undefined = target.getInfo().coordinate;
      if (point !== undefined) {
        receiver.onKnock(point.screenX, point.screenY);
      }
    } catch (error) {
      // No position before 26.0.0: the files still come.
    }
    try {
      const dir: string = KnockShare.inbox(context);
      if (!(await fileIo.access(dir))) {
        await fileIo.mkdir(dir);
      }
      let delivered: boolean = false;
      await target.receive(fileUri.getUriFromPath(dir), {
        onDataReceived: (data: systemShare.SharedData) => {
          const uris: string[] = [];
          data.getRecords().forEach((r: systemShare.SharedRecord) => {
            if (r.uri !== undefined && r.uri.length > 0) {
              uris.push(r.uri);
            }
          });
          hilog.info(LOG_DOMAIN, LOG_TAG, 'Received %{public}d file(s)', uris.length);
          delivered = true;
          receiver.onReceived(uris);
        },
        onResult: (code: harmonyShare.ShareResultCode) => {
          hilog.info(LOG_DOMAIN, LOG_TAG, 'Receive result %{public}d', code);
          if (code !== harmonyShare.ShareResultCode.SHARE_SUCCESS && !delivered) {
            receiver.onFailed();
          }
        }
      });
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Receive failed: %{public}s', detail(error));
      receiver.onFailed();
    }
  }
}
