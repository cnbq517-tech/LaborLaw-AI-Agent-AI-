// The built-in model service: its daily allowance and how its key is kept in
// the package. Pure logic, tested in tools/harmony/logic-tests.

export const DAILY_LIMIT: number = 100;
// The shortest gap between two requests on the built-in service.
export const MIN_INTERVAL_MS: number = 2000;

// The key is stored XOR-ed with this mask and hex-encoded, so it is not a
// readable string in the package. This only stops casual extraction; anyone
// who unpacks the app can still recover it. tools/harmony/builtin-service
// writes the file with the same mask.
export const KEY_MASK: string = 'laborlaw-harmony-builtin';

export class ModelQuota {
  // The local calendar day, as the allowance resets at midnight.
  static day(now: Date): string {
    const month: string = (now.getMonth() + 1).toString().padStart(2, '0');
    const date: string = now.getDate().toString().padStart(2, '0');
    return now.getFullYear().toString() + '-' + month + '-' + date;
  }

  // Requests used today, given what was saved for savedDay.
  static usedToday(savedDay: string, savedUsed: number, today: string): number {
    return savedDay === today ? Math.max(0, savedUsed) : 0;
  }

  static remaining(used: number): number {
    return Math.max(0, DAILY_LIMIT - used);
  }

  static decodeKey(hex: string): string {
    if (hex.length % 2 !== 0 || !/^[0-9a-f]*$/.test(hex)) {
      return '';
    }
    let key: string = '';
    for (let i: number = 0; i < hex.length / 2; i++) {
      const code: number = parseInt(hex.substring(i * 2, i * 2 + 2), 16) ^
        KEY_MASK.charCodeAt(i % KEY_MASK.length);
      key += String.fromCharCode(code);
    }
    return key;
  }

  static encodeKey(key: string): string {
    let hex: string = '';
    for (let i: number = 0; i < key.length; i++) {
      const code: number = key.charCodeAt(i) ^ KEY_MASK.charCodeAt(i % KEY_MASK.length);
      hex += code.toString(16).padStart(2, '0');
    }
    return hex;
  }
}
