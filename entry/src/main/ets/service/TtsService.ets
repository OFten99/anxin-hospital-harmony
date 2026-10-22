import { textToSpeech } from '@kit.CoreSpeechKit';
import { AppConfig } from './AppConfig';

/**
 * 语音播报服务（适老化核心能力）
 *
 * 老年人看不清小字、也不习惯读屏，但听得清。
 * 每一步操作后都用语音复述一遍，能显著降低误操作。
 *
 * 端侧 TTS 并非所有设备都可用，因此全程 try/catch，
 * 初始化失败时静默降级，绝不因为播报失败阻塞挂号流程。
 */
export class TtsService {
  private engine: textToSpeech.TextToSpeechEngine | null = null;
  private initializing: boolean = false;
  private failed: boolean = false;

  /** 初始化引擎 */
  async init(): Promise<void> {
    if (this.engine !== null || this.initializing || this.failed) {
      return;
    }
    this.initializing = true;
    try {
      const params: textToSpeech.CreateEngineParams = {
        language: 'zh-CN',
        person: 0,
        online: 1,
        extraParams: {}
      };
      this.engine = await textToSpeech.createEngine(params);
    } catch (e) {
      this.failed = true;
      this.engine = null;
    } finally {
      this.initializing = false;
    }
  }

  /** 播报一句话 */
  async speak(text: string): Promise<void> {
    if (!AppConfig.TTS_ENABLED || text.length === 0) {
      return;
    }
    if (this.engine === null) {
      await this.init();
    }
    if (this.engine === null) {
      return;
    }
    try {
      const requestId: string = `tts_${Date.now()}`;
      const speakParams: textToSpeech.SpeakParams = {
        requestId: requestId,
        extraParams: {}
      };
      this.engine.speak(text, speakParams);
    } catch (e) {
      // 播报失败不影响主流程
    }
  }

  /** 打断当前播报 */
  stop(): void {
    if (this.engine !== null) {
      try {
        this.engine.stop();
      } catch (e) {
        // 忽略
      }
    }
  }

  /** 释放引擎 */
  async release(): Promise<void> {
    if (this.engine !== null) {
      try {
        this.engine.shutdown();
      } catch (e) {
        // 忽略
      }
      this.engine = null;
    }
  }
}
