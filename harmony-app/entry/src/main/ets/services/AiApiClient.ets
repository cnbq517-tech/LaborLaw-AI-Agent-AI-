import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import {
  ApiConfig,
  ApiErrorResponse,
  ChatCompletionChunk,
  ChatCompletionDelta,
  ChatCompletionRequest,
  ChatCompletionResponse,
  ChatMessage
} from '../models/AppModels';

const MAX_RAW_BODY: number = 65536;

// Lets the UI stop an in-flight streaming answer. Whatever text has already
// arrived is kept and returned by AiApiClient.stream().
export class StreamHandle {
  private request: http.HttpRequest | undefined = undefined;
  private stopped: boolean = false;

  get cancelled(): boolean {
    return this.stopped;
  }

  attach(request: http.HttpRequest): void {
    this.request = request;
  }

  cancel(): void {
    if (this.stopped) {
      return;
    }
    this.stopped = true;
    if (this.request !== undefined) {
      try {
        this.request.destroy();
      } catch (error) {
        // Already destroyed by the normal completion path.
      }
      this.request = undefined;
    }
  }

  detach(): void {
    this.request = undefined;
  }
}

class StreamState {
  pending: string = '';
  answer: string = '';
  refusal: string = '';
  streamError: string = '';
  rawBody: string = '';
  sawSse: boolean = false;
}

class RequestHeaders {
  Authorization: string;
  'Content-Type': string = 'application/json';

  constructor(apiKey: string) {
    this.Authorization = 'Bearer ' + apiKey;
  }
}

export class AiApiClient {
  static validateConfig(config: ApiConfig): string {
    if (config.baseUrl.trim().length === 0) {
      return '请填写 Base URL';
    }
    if (!config.baseUrl.trim().startsWith('https://')) {
      return 'Base URL 必须使用 HTTPS';
    }
    if (config.model.trim().length === 0) {
      return '请填写模型名称';
    }
    if (config.apiKey.trim().length === 0) {
      return '请填写 API Key';
    }
    return '';
  }

  static completionUrl(baseUrl: string): string {
    let normalized: string = baseUrl.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.endsWith('/chat/completions')) {
      return normalized;
    }
    return normalized + '/chat/completions';
  }

  static async send(config: ApiConfig, messages: ChatMessage[]): Promise<string> {
    const validationError: string = AiApiClient.validateConfig(config);
    if (validationError.length > 0) {
      throw new Error(validationError);
    }

    const request: http.HttpRequest = http.createHttp();
    const body: ChatCompletionRequest = new ChatCompletionRequest(config.model.trim(), messages);
    const headers: RequestHeaders = new RequestHeaders(config.apiKey.trim());

    try {
      const response: http.HttpResponse = await request.request(AiApiClient.completionUrl(config.baseUrl), {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        connectTimeout: 15000,
        readTimeout: 60000
      });
      const raw: string = response.result as string;
      const statusCode: number = response.responseCode as number;

      if (statusCode < 200 || statusCode >= 300) {
        throw new Error(AiApiClient.httpErrorMessage(statusCode, raw));
      }

      let parsed: ChatCompletionResponse;
      try {
        parsed = JSON.parse(raw) as ChatCompletionResponse;
      } catch (error) {
        throw new Error('模型返回了无法解析的数据');
      }

      if (parsed.choices.length === 0 || parsed.choices[0].message === undefined) {
        throw new Error('模型响应中没有可显示的回答');
      }
      const answer: string = parsed.choices[0].message.content;
      if (answer !== undefined && answer.trim().length > 0) {
        return answer.trim();
      }
      const refusal: string = parsed.choices[0].message.refusal;
      if (refusal !== undefined && refusal.trim().length > 0) {
        return refusal.trim();
      }
      throw new Error('模型返回了空回答');
    } catch (error) {
      if (error instanceof Error) {
        throw error;
      }
      throw new Error('网络请求失败，请检查网络和接口配置');
    } finally {
      request.destroy();
    }
  }

  // Streams a Chat Completions answer over SSE. `onText` receives the full
  // text accumulated so far each time new tokens arrive. If the service
  // ignores `stream: true` and returns a normal JSON body, that is handled too.
  static async stream(
    config: ApiConfig,
    messages: ChatMessage[],
    onText: (text: string) => void,
    handle: StreamHandle
  ): Promise<string> {
    const validationError: string = AiApiClient.validateConfig(config);
    if (validationError.length > 0) {
      throw new Error(validationError);
    }

    if (handle.cancelled) {
      return '';
    }
    const request: http.HttpRequest = http.createHttp();
    handle.attach(request);
    const body: ChatCompletionRequest = new ChatCompletionRequest(config.model.trim(), messages, true);
    const headers: RequestHeaders = new RequestHeaders(config.apiKey.trim());
    const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
    const state: StreamState = new StreamState();

    request.on('dataReceive', (data: ArrayBuffer) => {
      const text: string = decoder.decodeToString(new Uint8Array(data), { stream: true });
      const before: number = state.answer.length;
      AiApiClient.consume(state, text, false);
      if (state.answer.length > before) {
        onText(state.answer);
      }
    });

    try {
      const statusCode: number = await request.requestInStream(AiApiClient.completionUrl(config.baseUrl), {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify(body),
        usingCache: false,
        connectTimeout: 15000,
        // Long answers keep the connection open while tokens arrive.
        readTimeout: 180000
      });
      AiApiClient.consume(state, decoder.decodeToString(new Uint8Array(0)), true);

      if (statusCode < 200 || statusCode >= 300) {
        throw new Error(AiApiClient.httpErrorMessage(statusCode, state.rawBody));
      }
      if (!state.sawSse && state.answer.length === 0) {
        return AiApiClient.parseCompletion(state.rawBody);
      }
      if (state.streamError.length > 0 && state.answer.trim().length === 0) {
        throw new Error('接口错误：' + state.streamError);
      }
      const answer: string = state.answer.trim();
      if (answer.length > 0) {
        return answer;
      }
      if (state.refusal.trim().length > 0) {
        return state.refusal.trim();
      }
      throw new Error('模型返回了空回答');
    } catch (error) {
      if (handle.cancelled) {
        return state.answer.trim();
      }
      if (error instanceof Error) {
        throw error;
      }
      throw new Error('网络请求失败，请检查网络和接口配置');
    } finally {
      handle.detach();
      try {
        request.off('dataReceive');
        request.destroy();
      } catch (error) {
        // Already destroyed by StreamHandle.cancel().
      }
    }
  }

  private static consume(state: StreamState, text: string, final: boolean): void {
    if (state.rawBody.length < MAX_RAW_BODY) {
      state.rawBody += text;
    }
    state.pending += text;
    let newline: number = state.pending.indexOf('\n');
    while (newline >= 0) {
      AiApiClient.consumeLine(state, state.pending.substring(0, newline));
      state.pending = state.pending.substring(newline + 1);
      newline = state.pending.indexOf('\n');
    }
    if (final && state.pending.length > 0) {
      AiApiClient.consumeLine(state, state.pending);
      state.pending = '';
    }
  }

  private static consumeLine(state: StreamState, rawLine: string): void {
    const line: string = rawLine.trim();
    if (!line.startsWith('data:')) {
      return;
    }
    state.sawSse = true;
    const payload: string = line.substring(5).trim();
    if (payload.length === 0 || payload === '[DONE]') {
      return;
    }
    let chunk: ChatCompletionChunk;
    try {
      chunk = JSON.parse(payload) as ChatCompletionChunk;
    } catch (error) {
      return;
    }
    if (chunk.error !== undefined && chunk.error !== null && chunk.error.message !== undefined) {
      state.streamError = chunk.error.message;
    }
    if (chunk.choices === undefined || chunk.choices === null || chunk.choices.length === 0) {
      return;
    }
    const delta: ChatCompletionDelta = chunk.choices[0].delta;
    if (delta === undefined || delta === null) {
      return;
    }
    if (typeof delta.content === 'string') {
      state.answer += delta.content;
    }
    if (typeof delta.refusal === 'string') {
      state.refusal += delta.refusal;
    }
  }

  private static parseCompletion(raw: string): string {
    let parsed: ChatCompletionResponse;
    try {
      parsed = JSON.parse(raw) as ChatCompletionResponse;
    } catch (error) {
      throw new Error('模型返回了无法解析的数据');
    }
    if (parsed.choices === undefined || parsed.choices.length === 0 ||
      parsed.choices[0].message === undefined) {
      throw new Error('模型响应中没有可显示的回答');
    }
    const answer: string = parsed.choices[0].message.content;
    if (answer !== undefined && answer !== null && answer.trim().length > 0) {
      return answer.trim();
    }
    const refusal: string = parsed.choices[0].message.refusal;
    if (refusal !== undefined && refusal !== null && refusal.trim().length > 0) {
      return refusal.trim();
    }
    throw new Error('模型返回了空回答');
  }

  private static httpErrorMessage(statusCode: number, raw: string): string {
    let serverMessage: string = '';
    try {
      const parsed: ApiErrorResponse = JSON.parse(raw) as ApiErrorResponse;
      if (parsed.error !== undefined && parsed.error.message !== undefined) {
        serverMessage = parsed.error.message.trim();
      }
    } catch (error) {
      serverMessage = '';
    }

    if (statusCode === 401 || statusCode === 403) {
      return '认证失败，请检查 API Key';
    }
    if (statusCode === 404) {
      return '接口或模型不存在，请检查 Base URL 和模型名称';
    }
    if (statusCode === 408) {
      return '请求超时，请稍后重试';
    }
    if (statusCode === 429) {
      return '请求过于频繁或额度不足';
    }
    if (statusCode >= 500) {
      return '模型服务暂时不可用（' + statusCode.toString() + '）';
    }
    if (serverMessage.length > 0) {
      return '接口错误：' + serverMessage;
    }
    return '接口请求失败（HTTP ' + statusCode.toString() + '）';
  }
}
