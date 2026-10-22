import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { AppConfig } from './AppConfig';
import { DEMO_SAMPLES } from '../model/TriageData';
import { VoiceSample } from '../model/Types';

/**
 * 语音识别服务
 *
 * 三条路径，按可用性自动降级：
 *   1. 真实路径：录音 → 上传云端 ASR → 返回转写文本
 *   2. 演示路径：直接返回内置样例文本，用于无网络、无 Key 演示
 *   3. 文本路径：用户直接输入（兜底，也便于调试分诊逻辑）
 *
 * 关于方言：老年人普通话识别率显著低于年轻人，方言差距更大。
 * 选型时应优先评估支持「方言识别」或「带口音普通话」的 ASR，
 * 并保留「没听清就追问」的交互，而不是强行猜。
 */
export class AsrService {
  private recorder: media.AVRecorder | null = null;
  private file: fileIo.File | null = null;
  private filePath: string = '';
  private recording: boolean = false;

  /** 是否具备真实识别能力 */
  isRealMode(): boolean {
    return !AppConfig.FORCE_DEMO && AppConfig.ASR_ENDPOINT.length > 0;
  }

  isRecording(): boolean {
    return this.recording;
  }

  /** 开始录音，需要麦克风权限（调用方负责申请） */
  async startRecord(context: common.UIAbilityContext): Promise<void> {
    if (this.recording) {
      return;
    }
    const dir: string = context.cacheDir;
    this.filePath = `${dir}/voice_${Date.now()}.m4a`;

    this.file = fileIo.openSync(this.filePath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
    this.recorder = await media.createAVRecorder();

    const profile: media.AVRecorderProfile = {
      audioBitrate: 48000,
      audioChannels: 1,
      audioCodec: media.CodecMimeType.AUDIO_AAC,
      audioSampleRate: 16000,
      fileFormat: media.ContainerFormatType.CFT_MPEG_4A
    };
    const config: media.AVRecorderConfig = {
      audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
      profile: profile,
      url: `fd://${this.file.fd}`
    };

    await this.recorder.prepare(config);
    await this.recorder.start();
    this.recording = true;
  }

  /** 停止录音，返回音频文件路径 */
  async stopRecord(): Promise<string> {
    if (!this.recording) {
      return '';
    }
    this.recording = false;
    try {
      if (this.recorder !== null) {
        await this.recorder.stop();
        await this.recorder.release();
        this.recorder = null;
      }
    } catch (e) {
      // 录音过短或设备异常，忽略并继续
    }
    if (this.file !== null) {
      fileIo.closeSync(this.file);
      this.file = null;
    }
    return this.filePath;
  }

  /** 上传音频到云端 ASR，返回转写文本 */
  async recognizeAudio(filePath: string): Promise<string> {
    if (!this.isRealMode()) {
      throw new Error('未配置云端识别服务');
    }
    const stat: fileIo.Stat = fileIo.statSync(filePath);
    if (stat.size < 1024) {
      throw new Error('录音太短，没听清');
    }

    // 读取音频并转 base64。不同供应商要求的编码方式不同，
    // 若对方要求 multipart/form-data，需按供应商文档改写本段。
    const buf: ArrayBuffer = new ArrayBuffer(stat.size);
    const reader: fileIo.File = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
    fileIo.readSync(reader.fd, buf);
    fileIo.closeSync(reader);

    const helper: util.Base64Helper = new util.Base64Helper();
    const base64: string = helper.encodeToStringSync(new Uint8Array(buf));

    const client: http.HttpRequest = http.createHttp();
    try {
      const resp: http.HttpResponse = await client.request(AppConfig.ASR_ENDPOINT, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${AppConfig.ASR_TOKEN}`
        },
        extraData: JSON.stringify({
          format: 'm4a',
          sample_rate: 16000,
          audio: base64
        }),
        connectTimeout: 15000,
        readTimeout: 30000
      });
      if (resp.responseCode !== 200) {
        throw new Error(`识别服务返回 ${resp.responseCode}`);
      }
      const body: string = resp.result as string;
      const obj: Record<string, string> = JSON.parse(body) as Record<string, string>;
      const text: string = obj['text'] ?? '';
      if (text.length === 0) {
        throw new Error('没听清，请再说一遍');
      }
      return text;
    } finally {
      client.destroy();
    }
  }

  /** 演示模式：返回内置样例文本，模拟识别耗时 */
  async recognizeDemo(sampleId: string): Promise<string> {
    let text: string = '';
    for (let i = 0; i < DEMO_SAMPLES.length; i++) {
      if (DEMO_SAMPLES[i].id === sampleId) {
        text = DEMO_SAMPLES[i].text;
        break;
      }
    }
    if (text.length === 0) {
      text = DEMO_SAMPLES[0].text;
    }
    // 模拟云端往返延迟，让"识别中"状态可见
    await new Promise<void>((resolve: () => void) => {
      setTimeout(() => resolve(), 900);
    });
    return text;
  }

  getDemoSamples(): VoiceSample[] {
    return DEMO_SAMPLES;
  }

  /** 释放资源 */
  async release(): Promise<void> {
    if (this.recording) {
      await this.stopRecord();
    }
    if (this.recorder !== null) {
      await this.recorder.release();
      this.recorder = null;
    }
  }
}
