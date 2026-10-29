// Sampling settings per kind of request. Pure logic, tested in
// tools/harmony/logic-tests.
//
// DeepSeek runs in thinking mode by default, where temperature has no effect
// (its API accepts the field and ignores it), and the app keeps thinking on so
// it can show the model's reasoning, contract review included. So DeepSeek
// requests carry no temperature. Other OpenAI-compatible services get the
// values the Python prototype used.

// Answers and reports read as prose.
export const TASK_ANSWER: number = 0;
// Replies parsed as JSON (contract review), where steadiness matters most.
export const TASK_STRUCTURED: number = 1;

export class ModelTuning {
  static isDeepSeek(baseUrl: string): boolean {
    return baseUrl.toLowerCase().includes('deepseek.com');
  }

  // The temperature to send, or undefined to leave the service's default.
  static temperature(baseUrl: string, task: number): number | undefined {
    if (ModelTuning.isDeepSeek(baseUrl)) {
      return undefined;
    }
    return task === TASK_STRUCTURED ? 0.1 : 0.3;
  }
}
