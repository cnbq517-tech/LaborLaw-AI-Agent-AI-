import { Capacitor, registerPlugin, type PluginListenerHandle } from '@capacitor/core';
import { ApiConfig, ChatCompletionRequest, ChatMessage } from '@harmony/models/AppModels';
import { ModelTuning, TASK_ANSWER, TASK_STRUCTURED } from '@harmony/services/ModelTuning';
import { ThinkTagParser } from '@harmony/services/ThinkTagParser';

interface NativeStreamPlugin {
  startStream(options: {
    requestId: string;
    url: string;
    headers: Record<string, string>;
    body: string;
    timeoutMs?: number;
  }): Promise<void>;
  abortStream(options: { requestId: string }): Promise<void>;
  addListener(
    eventName: 'streamChunk',
    listenerFunc: (data: { requestId: string; chunk: string }) => void
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'streamEnd',
    listenerFunc: (data: { requestId: string; status: number }) => void
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'streamError',
    listenerFunc: (data: { requestId: string; status: number; message: string }) => void
  ): Promise<PluginListenerHandle>;
}

const NativeStream = registerPlugin<NativeStreamPlugin>('NativeStream');

export interface StreamCallbacks {
  onDelta: (answer: string, reasoning: string) => void;
}

export interface CompletionOutput {
  content: string;
  reasoning: string;
  thinkMs: number;
  aborted: boolean;
}

export interface StreamHandle {
  promise: Promise<CompletionOutput>;
  abort: () => void;
}

export function normalizeEndpoint(baseUrl: string): string {
  const trimmed = baseUrl.trim().replace(/\/+$/, '');
  if (trimmed.endsWith('/chat/completions')) {
    return trimmed;
  }
  return `${trimmed}/chat/completions`;
}

function extractSseLine(line: string): { content: string; reasoning: string; done: boolean } {
  const trimmed = line.trim();
  if (!trimmed.startsWith('data:')) {
    return { content: '', reasoning: '', done: false };
  }
  const data = trimmed.slice(5).trim();
  if (data === '[DONE]') {
    return { content: '', reasoning: '', done: true };
  }
  try {
    const parsed = JSON.parse(data) as {
      choices?: Array<{
        delta?: { content?: string; reasoning_content?: string; reasoning?: string };
        message?: { content?: string; reasoning_content?: string; reasoning?: string };
      }>;
      error?: { message?: string };
    };
    if (parsed.error?.message) {
      throw new Error(parsed.error.message);
    }
    const choice = parsed.choices?.[0];
    const delta = choice?.delta ?? choice?.message;
    return {
      content: typeof delta?.content === 'string' ? delta.content : '',
      reasoning:
        typeof delta?.reasoning_content === 'string'
          ? delta.reasoning_content
          : typeof delta?.reasoning === 'string'
            ? delta.reasoning
            : '',
      done: false,
    };
  } catch (e) {
    if (e instanceof Error && !e.message.includes('JSON')) {
      throw e;
    }
    return { content: '', reasoning: '', done: false };
  }
}

/**
 * Streams an OpenAI-compatible Chat Completion.
 * Uses the Android native HttpURLConnection bridge (`NativeStream`) on Android
 * devices so WebView CORS restrictions never block DeepSeek or custom endpoints.
 */
export function streamChatCompletion(
  config: ApiConfig,
  messages: ChatMessage[],
  callbacks: StreamCallbacks,
  task: number = TASK_ANSWER
): StreamHandle {
  if (!config.baseUrl.trim() || !config.model.trim() || !config.apiKey.trim()) {
    return {
      promise: Promise.reject(new Error('请先在「我的」中配置 API 地址、模型名称和 API Key')),
      abort: () => {},
    };
  }

  const url = normalizeEndpoint(config.baseUrl);
  const temperature = ModelTuning.temperature(config.baseUrl, task);
  const reqBody = new ChatCompletionRequest(config.model.trim(), messages, true, temperature);
  const bodyJson = JSON.stringify(reqBody);
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    Accept: 'text/event-stream',
    Authorization: `Bearer ${config.apiKey.trim()}`,
  };

  let aborted = false;
  let cancelFn: () => void = () => {};

  const promise = new Promise<CompletionOutput>(async (resolve, reject) => {
    const parser = new ThinkTagParser();
    let directReasoning = '';
    let thinkStart = 0;
    let thinkEnd = 0;
    let lineBuffer = '';
    let rawFallback = '';

    const emitUpdate = () => {
      const combinedReasoning = (directReasoning + parser.reasoning).trim();
      if (combinedReasoning.length > 0 && thinkStart === 0) {
        thinkStart = Date.now();
      }
      if (parser.answer.length > 0 && thinkStart > 0 && thinkEnd === 0) {
        thinkEnd = Date.now();
      }
      callbacks.onDelta(parser.answer, combinedReasoning);
    };

    const feedChunk = (text: string) => {
      rawFallback += text;
      lineBuffer += text;
      const lines = lineBuffer.split(/\r?\n/);
      lineBuffer = lines.pop() ?? '';
      for (const line of lines) {
        const parsed = extractSseLine(line);
        if (parsed.reasoning) {
          directReasoning += parsed.reasoning;
        }
        if (parsed.content) {
          parser.push(parsed.content);
        }
        if (parsed.reasoning || parsed.content) {
          emitUpdate();
        }
      }
    };

    const finalize = (): CompletionOutput => {
      if (lineBuffer.trim().length > 0) {
        try {
          const parsed = extractSseLine(lineBuffer);
          if (parsed.reasoning) directReasoning += parsed.reasoning;
          if (parsed.content) parser.push(parsed.content);
        } catch {
          // ignore trailing partial line
        }
      }
      parser.finish();

      // Handle non-SSE JSON fallback if provider ignored stream:true
      if (parser.answer.length === 0 && rawFallback.trim().startsWith('{')) {
        try {
          const obj = JSON.parse(rawFallback) as {
            choices?: Array<{ message?: { content?: string; reasoning_content?: string } }>;
            error?: { message?: string };
          };
          if (obj.error?.message) {
            throw new Error(obj.error.message);
          }
          const msg = obj.choices?.[0]?.message;
          if (msg?.reasoning_content) directReasoning += msg.reasoning_content;
          if (msg?.content) parser.push(msg.content);
          parser.finish();
        } catch (e) {
          if (e instanceof Error && !e.message.includes('JSON')) throw e;
        }
      }

      const combinedReasoning = (directReasoning + parser.reasoning).trim();
      const thinkMs = thinkStart > 0 ? Math.max(0, (thinkEnd || Date.now()) - thinkStart) : 0;
      callbacks.onDelta(parser.answer, combinedReasoning);
      return {
        content: parser.answer,
        reasoning: combinedReasoning,
        thinkMs,
        aborted,
      };
    };

    if (Capacitor.isNativePlatform()) {
      const requestId = `req_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
      const handles: PluginListenerHandle[] = [];
      let settled = false;

      const cleanup = async () => {
        for (const h of handles) {
          try {
            await h.remove();
          } catch {
            // ignore
          }
        }
      };

      cancelFn = () => {
        aborted = true;
        NativeStream.abortStream({ requestId }).catch(() => {});
      };

      try {
        handles.push(
          await NativeStream.addListener('streamChunk', (ev) => {
            if (ev.requestId !== requestId || settled) return;
            try {
              feedChunk(ev.chunk);
            } catch (err) {
              settled = true;
              cleanup();
              reject(err instanceof Error ? err : new Error(String(err)));
            }
          })
        );
        handles.push(
          await NativeStream.addListener('streamEnd', (ev) => {
            if (ev.requestId !== requestId || settled) return;
            settled = true;
            cleanup();
            try {
              resolve(finalize());
            } catch (err) {
              reject(err instanceof Error ? err : new Error(String(err)));
            }
          })
        );
        handles.push(
          await NativeStream.addListener('streamError', (ev) => {
            if (ev.requestId !== requestId || settled) return;
            settled = true;
            cleanup();
            if (aborted) {
              resolve(finalize());
            } else {
              const prefix = ev.status > 0 ? `HTTP ${ev.status}：` : '';
              reject(new Error(`${prefix}${ev.message || '网络请求失败'}`));
            }
          })
        );

        await NativeStream.startStream({
          requestId,
          url,
          headers,
          body: bodyJson,
          timeoutMs: 90000,
        });
      } catch (err) {
        if (!settled) {
          settled = true;
          await cleanup();
          reject(err instanceof Error ? err : new Error(String(err)));
        }
      }
      return;
    }

    // Web browser fallback
    const controller = new AbortController();
    cancelFn = () => {
      aborted = true;
      controller.abort();
    };

    try {
      const resp = await fetch(url, {
        method: 'POST',
        headers,
        body: bodyJson,
        signal: controller.signal,
      });
      if (!resp.ok) {
        const errText = await resp.text().catch(() => '');
        throw new Error(`HTTP ${resp.status}：${errText.slice(0, 200) || resp.statusText}`);
      }
      if (!resp.body) {
        const text = await resp.text();
        feedChunk(text);
        resolve(finalize());
        return;
      }
      const reader = resp.body.getReader();
      const decoder = new TextDecoder('utf-8');
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        if (value) {
          feedChunk(decoder.decode(value, { stream: true }));
        }
      }
      feedChunk(decoder.decode());
      resolve(finalize());
    } catch (err) {
      if (aborted) {
        resolve(finalize());
      } else {
        const msg = err instanceof Error ? err.message : String(err);
        reject(new Error(msg.includes('Failed to fetch') ? '网络请求失败（请检查地址、网络或 CORS 配置）' : msg));
      }
    }
  });

  return {
    promise,
    abort: () => cancelFn(),
  };
}

export async function completeStructuredJson(
  config: ApiConfig,
  systemPrompt: string,
  userPrompt: string
): Promise<CompletionOutput> {
  const messages = [
    new ChatMessage('system', systemPrompt),
    new ChatMessage('user', userPrompt),
  ];
  const handle = streamChatCompletion(config, messages, { onDelta: () => {} }, TASK_STRUCTURED);
  return handle.promise;
}

export async function testApiConnection(config: ApiConfig): Promise<string> {
  const messages = [new ChatMessage('user', '请只回复“连接正常”四个字。')];
  const handle = streamChatCompletion(config, messages, { onDelta: () => {} }, TASK_ANSWER);
  const out = await handle.promise;
  return out.content.trim() || '连接成功（模型返回空文本）';
}
