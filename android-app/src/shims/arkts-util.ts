// Minimal Web shim for `@kit.ArkTS` used solely by HarmonyOS KnowledgeEngine.ets
// (`new util.TextDecoder().decodeToString(bytes)`). Keeps `harmony-app/` untouched.

class ArkTextDecoder {
  private readonly decoder = new globalThis.TextDecoder('utf-8');

  decodeToString(bytes: Uint8Array): string {
    return this.decoder.decode(bytes);
  }
}

export const util = {
  TextDecoder: ArkTextDecoder,
};
