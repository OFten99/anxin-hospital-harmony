import { http } from '@kit.NetworkKit';
import { AppConfig } from './AppConfig';
import { SymptomProfile } from '../model/Types';

/**
 * 语义结构化服务
 *
 * 大模型只做一件事：把老人的口语转成结构化字段。
 * 不负责给科室结论——结论由确定性规则引擎产出，保证可解释、可审计。
 *
 * 未配置 LLM_ENDPOINT 时返回 null，调用方自动退回本地规则抽取。
 */
export class NluService {
  isAvailable(): boolean {
    return !AppConfig.FORCE_DEMO && AppConfig.LLM_ENDPOINT.length > 0;
  }

  /**
   * 调用大模型抽取症状结构。
   * 期望服务端返回 JSON：
   * { "bodyParts": [...], "symptoms": [...], "duration": "三天", "severity": "中" }
   */
  async extract(rawText: string): Promise<SymptomProfile | null> {
    if (!this.isAvailable()) {
      return null;
    }

    const prompt: string =
      '你是医院分诊助手。把下面老人说的话整理成 JSON，只输出 JSON，不要解释。\n' +
      '字段：bodyParts（身体部位词数组）、symptoms（不舒服的表现数组）、duration（时长，没说就空字符串）。\n' +
      '要求：用规范医学术语替换口语，但保留原意；不要推断没提到的症状。\n' +
      `原话：${rawText}`;

    const client: http.HttpRequest = http.createHttp();
    try {
      const resp: http.HttpResponse = await client.request(AppConfig.LLM_ENDPOINT, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${AppConfig.LLM_TOKEN}`
        },
        extraData: JSON.stringify({
          messages: [{ role: 'user', content: prompt }],
          temperature: 0
        }),
        connectTimeout: 15000,
        readTimeout: 30000
      });
      if (resp.responseCode !== 200) {
        return null;
      }
      const body: string = resp.result as string;
      const obj: Record<string, Object> = JSON.parse(body) as Record<string, Object>;
      const content: string = obj['content'] as string;
      if (!content) {
        return null;
      }
      const parsed: Record<string, Object> = JSON.parse(content) as Record<string, Object>;

      const bodyParts: string[] = NluService.toStringArray(parsed['bodyParts']);
      const symptoms: string[] = NluService.toStringArray(parsed['symptoms']);
      const duration: string = (parsed['duration'] as string) ?? '';

      return {
        rawText: rawText,
        bodyParts: bodyParts,
        symptoms: symptoms,
        contexts: [],
        duration: duration,
        redFlags: [],
        vague: bodyParts.length === 0 && symptoms.length === 0
      };
    } catch (e) {
      // 网络或解析失败一律降级，不阻塞挂号主流程
      return null;
    } finally {
      client.destroy();
    }
  }

  private static toStringArray(value: Object): string[] {
    const result: string[] = [];
    if (!value) {
      return result;
    }
    const arr: Object[] = value as Object[];
    if (!Array.isArray(arr)) {
      return result;
    }
    for (let i = 0; i < arr.length; i++) {
      result.push(String(arr[i]));
    }
    return result;
  }
}
