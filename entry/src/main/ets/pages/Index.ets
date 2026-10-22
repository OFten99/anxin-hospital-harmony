import { common, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { AsrService } from '../service/AsrService';
import { TriageEngine } from '../service/TriageEngine';
import { HospitalService } from '../service/HospitalService';
import { TtsService } from '../service/TtsService';
import { AppConfig } from '../service/AppConfig';
import { SafetyGuard } from '../service/SafetyGuard';
import { MiniProgramLauncher, LaunchResult } from '../service/MiniProgramLauncher';
import { MiniProgramMap } from '../model/MiniProgramMap';
import { HospitalMatch, TriageResult, VoiceSample } from '../model/Types';
import { EMERGENCY_TIP } from '../model/HospitalData';

/**
 * 配色：与「医院门诊管理系统」Web 端同一套视觉规范
 *
 * 取自 web_app/static/style.css 的 :root 变量：
 *   背景 #f4f4f5 / 面板 #ffffff / 正文 #18181b / 次要 #71717a / 分割线 #e4e4e7
 * 强调色即黑色（原设计用蓝色，为与后台统一改为黑）。
 *
 * 唯一保留彩色的地方是急症页的红色：那里如果用灰黑，
 * 危急信号就失去了警示作用，这与统一视觉不冲突，是安全性优先。
 */
const C_BG: string = '#F4F4F5';
const C_PRIMARY: string = '#18181B';
const C_PRIMARY_DARK: string = '#000000';
const C_DANGER: string = '#B91C1C';
const C_TEXT: string = '#18181B';
const C_TEXT_SUB: string = '#71717A';
const C_WHITE: string = '#FFFFFF';
const C_WARN_BG: string = '#FAFAFA';
const C_WARN: string = '#3F3F46';
/** 浅灰底，对应后台 .secondary-btn / .badge 的 #e4e4e7 */
const C_SOFT: string = '#E4E4E7';
const C_MUTED: string = '#A1A1AA';

/**
 * 主页面
 *
 * 交互设计的三处关键取舍（都针对老年人）：
 *
 * 1. 用「点一下开始 / 再点一下结束」，不用长按。
 *    手抖、关节僵硬的老人长按容易脱手，录到一半断掉更让人挫败。
 *
 * 2. 每一步都语音复述 + 大字确认。
 *    老人常说「啊？你说啥？」，不给确认环节就会出现挂错科。
 *
 * 3. 全流程只有一个主要按钮。
 *    多选项、返回键、小字链接对老人都是陷阱。
 */
@Entry
@Component
struct Index {
  /** 0 首页 1 录音中 2 识别中 3 确认 4 分诊结果 5 医院列表 6 挂号页 7 急症警示 */
  @State stage: number = 0;
  @State isRecording: boolean = false;
  @State recordSeconds: number = 0;
  @State recognizedText: string = '';
  @State triage: TriageResult | null = null;
  @State hospitalList: HospitalMatch[] = [];
  @State selected: HospitalMatch | null = null;
  @State statusTip: string = '';
  @State samples: VoiceSample[] = [];
  /** 挂号页地址：真实医院 H5 / 真实 HIS 接口页 / 内置模拟页 */
  @State webSrc: string | Resource = $rawfile('his.html');
  /** 当前加载的是否为「真实 HIS 接口页」，决定 onPageEnd 注入什么参数 */
  @State usingHisPage: boolean = true;

  private asr: AsrService = new AsrService();
  private tts: TtsService = new TtsService();
  private timerId: number = -1;
  private webController: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    this.samples = this.asr.getDemoSamples();
    this.tts.init();
  }

  aboutToDisappear(): void {
    this.clearTimer();
    this.asr.release();
    this.tts.release();
  }

  private clearTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  /** 申请麦克风权限 */
  private async ensureMicPermission(): Promise<boolean> {
    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const perms: Permissions[] = ['ohos.permission.MICROPHONE'];
      const res = await atManager.requestPermissionsFromUser(ctx, perms);
      return res.authResults.length > 0 && res.authResults[0] === 0;
    } catch (e) {
      return false;
    }
  }

  /** 点击主按钮：开始 / 结束录音 */
  private async onTapMic(): Promise<void> {
    if (this.isRecording) {
      await this.finishRecord();
      return;
    }

    // 演示模式下不真的录音，避免评审时环境没有麦克风
    if (AppConfig.FORCE_DEMO) {
      this.showTip('演示模式：请点下面的一句话试试');
      return;
    }

    const granted: boolean = await this.ensureMicPermission();
    if (!granted) {
      this.showTip('没有麦克风权限，可以点下面的例子试试');
      return;
    }

    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      await this.asr.startRecord(ctx);
      this.isRecording = true;
      this.stage = 1;
      this.recordSeconds = 0;
      this.tts.speak('请说哪里不舒服，说完再点一下屏幕');
      this.timerId = setInterval(() => {
        this.recordSeconds = this.recordSeconds + 1;
        // 录音上限 30 秒，防止老人忘记点结束
        if (this.recordSeconds >= 30) {
          this.finishRecord();
        }
      }, 1000);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      this.showTip(`录音没启动起来（${err.code}），可以点下面的例子`);
    }
  }

  /** 结束录音并识别 */
  private async finishRecord(): Promise<void> {
    this.clearTimer();
    this.isRecording = false;
    this.stage = 2;
    this.statusTip = '正在听您说……';

    const path: string = await this.asr.stopRecord();
    let text: string = '';
    try {
      text = await this.asr.recognizeAudio(path);
    } catch (e) {
      this.stage = 0;
      this.statusTip = '';
      this.showTip('这次没听清，您再说一遍好吗');
      this.tts.speak('这次没听清，您再说一遍好吗');
      return;
    }
    this.handleRecognized(text);
  }

  /** 走演示样例 */
  private async onPickSample(sample: VoiceSample): Promise<void> {
    this.stage = 2;
    this.statusTip = '正在听您说……';
    this.tts.speak('好的，我听听');
    const text: string = await this.asr.recognizeDemo(sample.id);
    this.handleRecognized(text);
  }

  /** 识别完成 → 进入确认页 */
  private handleRecognized(text: string): void {
    if (text.length === 0) {
      this.stage = 0;
      this.showTip('没听到内容，您再说一遍');
      return;
    }
    this.recognizedText = text;
    this.stage = 3;
    this.tts.speak(`您说的是：${text}。是这个意思吗？`);
  }

  /** 确认无误 → 分诊 */
  private onConfirm(): void {
    const result: TriageResult = TriageEngine.triage(this.recognizedText);
    this.triage = result;

    if (result.emergency) {
      this.stage = 7;
      const em: string = `注意，${result.primary.evidences[0]}。${result.emergencyAdvice}`;
      this.tts.speak(SafetyGuard.sanitizeWithEmergency(em, true));
      return;
    }

    this.stage = 4;
    const alt: string = result.alternates.length > 0 ? `，也可以看${result.alternates[0].deptName}` : '';
    this.tts.speak(SafetyGuard.sanitize(`建议您挂${result.primary.deptName}${alt}`));
  }

  /** 进入医院列表 */
  private onGoRegister(): void {
    if (this.triage === null) {
      return;
    }
    this.hospitalList = HospitalService.match(this.triage.primary.deptId);
    this.stage = 5;
    const n: number = this.hospitalList.length;
    this.tts.speak(n > 0 ? `为您找到${n}家医院，第一家有号` : '暂时没有可挂号的医院');
  }

  /**
   * 选择医院 → 优先用微信打开医院自己的挂号小程序，拉不起来再退回挂号页
   *
   * 为什么先试小程序：老人手机里基本都装微信、也用过医院小程序登录过，
   * 而 H5 挂号页往往还要再登录一次、再选一遍医院。
   * 但小程序这条路依赖外部条件（微信在不在、ID 配没配、账号有没有权限），
   * 任何一环不满足都必须能退回来，不能让老人卡在“点了没反应”。
   */
  private async onSelectHospital(m: HospitalMatch): Promise<void> {
    this.selected = m;
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

    const r: LaunchResult = await MiniProgramLauncher.launch(ctx, m.deptEntry.deptId, m.deptEntry.name);

    if (r.ok) {
      this.tts.speak(`正在打开${m.hospital.name}的挂号小程序`);
      this.showTip('正在打开微信小程序');
      return;
    }

    // 未配置时静默降级；配置了却失败，要说一句，否则用户不知道发生了什么
    if (r.reason !== 'not_configured') {
      this.showTip(r.message);
    }

    this.tts.speak(`正在打开${m.hospital.name}的挂号页面`);

    // 三级降级：医院自有 H5 > 真实 HIS 接口页 > 内置模拟页
    if (HospitalService.hasRealUrl(m)) {
      this.webSrc = m.deptEntry.url;
      this.usingHisPage = false;
    } else if (AppConfig.HIS_BASE_URL.length > 0) {
      this.webSrc = $rawfile('his.html');
      this.usingHisPage = true;
    } else {
      this.webSrc = $rawfile('reg.html');
      this.usingHisPage = false;
    }
    this.stage = 6;
  }

  /** 急症：尝试拉起拨号盘 */
  private onCall120(): void {
    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      ctx.startAbility({
        action: 'ohos.want.action.dial',
        uri: 'tel:120'
      });
    } catch (e) {
      this.showTip('请直接用手机拨打 120');
    }
  }

  private showTip(msg: string): void {
    try {
      promptAction.showToast({ message: msg, duration: 2500 });
    } catch (e) {
      // 忽略
    }
  }

  /** 顶部标题栏 */
  @Builder
  TopBar(title: string, showBack: boolean) {
    Row() {
      if (showBack) {
        Text('返回')
          .fontSize(19)
          .fontColor(C_PRIMARY)
          .padding({ left: 20, right: 20, top: 12, bottom: 12 })
          .onClick(() => {
            this.stage = 0;
            this.recognizedText = '';
            this.triage = null;
            this.selected = null;
          })
      }
      Text(title)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(C_TEXT)
        .layoutWeight(1)
        .textAlign(showBack ? TextAlign.Center : TextAlign.Start)
        .padding({ left: showBack ? 0 : 24, right: showBack ? 56 : 24 })
    }
    .width('100%')
    .height(72)
    .alignItems(VerticalAlign.Center)
  }

  /** 首页：一个大按钮解决所有事 */
  @Builder
  HomePage() {
    Column() {
      Text('有事您说话')
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor(C_TEXT)
        .margin({ top: 40 })

      Text('哪里不舒服，说给我听')
        .fontSize(19)
        .fontColor(C_TEXT_SUB)
        .margin({ top: 12 })

      // 主按钮
      Stack() {
        Column()
          .width(240)
          .height(240)
          .borderRadius(120)
          .backgroundColor(C_PRIMARY)
          .shadow({ radius: 24, color: '#1A18181B', offsetY: 8 })

        Column() {
          Text('🎤')
            .fontSize(48)
          Text(this.isRecording ? '说完了，点这里' : '点这里说话')
            .fontSize(22)
            .fontWeight(FontWeight.Medium)
            .fontColor(C_WHITE)
            .margin({ top: 8 })
        }
      }
      .width(240)
      .height(240)
      .margin({ top: 48 })
      .onClick(() => {
        this.onTapMic();
      })

      Text(this.statusTip.length > 0 ? this.statusTip : '说完再点一下，我就带您去挂号')
        .fontSize(18)
        .fontColor(C_TEXT_SUB)
        .margin({ top: 28 })
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })

      Blank()

      // 演示样例：让评审者不用真的说话也能看完整链路
      if (AppConfig.FORCE_DEMO) {
        Column() {
          Text('不方便说话？点下面的例子')
            .fontSize(16)
            .fontColor(C_TEXT_SUB)
            .margin({ bottom: 12 })

          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
            ForEach(this.samples, (item: VoiceSample) => {
              Text(item.tag)
                .fontSize(17)
                .fontColor(C_PRIMARY_DARK)
                .padding({ left: 18, right: 18, top: 12, bottom: 12 })
                .backgroundColor('#E4E4E7')
                .borderRadius(24)
                .margin(6)
                .onClick(() => {
                  this.onPickSample(item);
                })
            }, (item: VoiceSample) => item.id)
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 28 })
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
  }

  /** 录音中 */
  @Builder
  RecordingPage() {
    Column() {
      Text('我在听……')
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor(C_DANGER)
        .margin({ top: 90 })

      Text(`${this.recordSeconds} 秒`)
        .fontSize(48)
        .fontWeight(FontWeight.Bold)
        .fontColor(C_TEXT)
        .margin({ top: 32 })

      Text('说慢一点，说清楚哪里不舒服')
        .fontSize(19)
        .fontColor(C_TEXT_SUB)
        .margin({ top: 16 })

      Blank()

      Stack() {
        Column()
          .width(200)
          .height(200)
          .borderRadius(100)
          .backgroundColor(C_DANGER)
        Text('说完了\n点这里')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(C_WHITE)
          .textAlign(TextAlign.Center)
      }
      .margin({ bottom: 100 })
      .onClick(() => {
        this.finishRecord();
      })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
  }

  /** 识别中 */
  @Builder
  RecognizingPage() {
    Column() {
      LoadingProgress()
        .width(120)
        .height(120)
        .color(C_PRIMARY)
        .margin({ top: 160 })

      Text('正在听您说……')
        .fontSize(24)
        .fontColor(C_TEXT)
        .margin({ top: 40 })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
  }

  /** 确认页：把机器听到的内容原样给老人看一遍 */
  @Builder
  ConfirmPage() {
    Column() {
      Text('您说的是这个意思吗？')
        .fontSize(22)
        .fontColor(C_TEXT_SUB)
        .margin({ top: 40 })

      Column() {
        Text(this.recognizedText)
          .fontSize(24)
          .lineHeight(44)
          .fontColor(C_TEXT)
          .padding(24)
      }
      .width('92%')
      .backgroundColor(C_WHITE)
      .borderRadius(20)
      .margin({ top: 24 })

      Text('如果不对，请点下面重说一遍')
        .fontSize(17)
        .fontColor(C_TEXT_SUB)
        .margin({ top: 20 })

      Blank()

      Button('对，就是这么回事')
        .width('92%')
        .height(88)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .backgroundColor(C_PRIMARY)
        .borderRadius(44)
        .margin({ bottom: 16 })
        .onClick(() => {
          this.onConfirm();
        })

      Button('说得不对，我重说')
        .width('92%')
        .height(80)
        .fontSize(21)
        .fontColor(C_PRIMARY)
        .backgroundColor('#E4E4E7')
        .borderRadius(40)
        .margin({ bottom: 40 })
        .onClick(() => {
          this.stage = 0;
          this.recognizedText = '';
          this.triage = null;
        })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
  }

  /** 分诊结果 */
  @Builder
  ResultPage() {
    Column() {
      Text(this.triage !== null && this.triage.needMoreInfo ? '我还想再问问您' : '建议您挂这个科')
        .fontSize(21)
        .fontColor(C_TEXT_SUB)
        .margin({ top: 32 })

      if (this.triage !== null) {
        Column() {
          Text(this.triage.primary.deptName)
            .fontSize(36)
            .fontWeight(FontWeight.Bold)
            .fontColor(C_PRIMARY_DARK)

          // 用对话式语言解释依据，避免冷冰冰的分数
          Text(this.triage.primary.evidences.length > 0
            ? `您说到「${this.triage.primary.evidences.slice(0, 3).join('、')}」`
            : '')
            .fontSize(18)
            .fontColor(C_TEXT_SUB)
            .margin({ top: 12 })
            .textAlign(TextAlign.Center)

          if (this.triage.needMoreInfo) {
            Text(this.triage.askBackText)
              .fontSize(19)
              .lineHeight(36)
              .fontColor(C_WARN)
              .padding(20)
              .backgroundColor(C_WARN_BG)
              .borderRadius(16)
              .margin({ top: 24 })
          }

          if (this.triage.alternates.length > 0) {
            Text(`也可以看：${this.triage.alternates.map((d) => d.deptName).join('、')}`)
              .fontSize(18)
              .fontColor(C_TEXT_SUB)
              .margin({ top: 20 })
          }

          Text(SafetyGuard.sanitize(this.triage.primary.hint))
            .fontSize(17)
            .fontColor('#A1A1AA')
            .margin({ top: 16 })
            .padding({ left: 24, right: 24 })
            .textAlign(TextAlign.Center)
        }
        .width('92%')
        .padding({ top: 36, bottom: 36 })
        .backgroundColor(C_WHITE)
        .borderRadius(24)
        .margin({ top: 24 })
        .alignItems(HorizontalAlign.Center)
      }

      Text(SafetyGuard.DISCLAIMER)
        .fontSize(13)
        .fontColor('#A1A1AA')
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32, top: 14 })
        .lineHeight(22)

      Blank()

      // 低置信度时不直接放行挂号，先让用户补充信息
      if (this.triage !== null && this.triage.needMoreInfo) {
        Button('我再补充几句')
          .width('92%')
          .height(88)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .backgroundColor(C_PRIMARY)
          .borderRadius(44)
          .margin({ bottom: 16 })
          .onClick(() => {
            this.stage = 0;
            this.recognizedText = '';
            this.triage = null;
          })

        Button('就先看老年医学科')
          .width('92%')
          .height(80)
          .fontSize(21)
          .fontColor(C_PRIMARY)
          .backgroundColor('#E4E4E7')
          .borderRadius(40)
          .margin({ bottom: 40 })
          .onClick(() => {
            this.onGoRegister();
          })
      } else {
        Button('帮我挂号')
          .width('92%')
          .height(96)
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .backgroundColor(C_PRIMARY)
          .borderRadius(48)
          .margin({ bottom: 44 })
          .onClick(() => {
            this.onGoRegister();
          })
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
  }

  /** 医院列表 */
  @Builder
  HospitalPage() {
    Column() {
      Text('离您近、还能挂上号的医院')
        .fontSize(18)
        .fontColor(C_TEXT_SUB)
        .width('100%')
        .padding({ left: 24, top: 16, bottom: 12 })

      // 配好小程序 ID 后，把跳转方式提前说清楚，别让老人以为点了会在这里挂号
      if (MiniProgramLauncher.isConfigured()) {
        Text('点医院会用微信打开它的挂号小程序')
          .fontSize(16)
          .fontColor(C_TEXT_SUB)
          .width('100%')
          .padding({ left: 24, bottom: 10 })
      }

      List({ space: 14 }) {
        ForEach(this.hospitalList, (item: HospitalMatch) => {
          ListItem() {
            Column() {
              Row() {
                Text(item.hospital.name)
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(C_TEXT)
                  .layoutWeight(1)
                Text(item.bookable ? '有号' : '约满')
                  .fontSize(16)
                  .fontColor(item.bookable ? C_WHITE : C_TEXT_SUB)
                  .backgroundColor(item.bookable ? '#18181B' : '#E4E4E7')
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .borderRadius(12)
              }
              .width('100%')

              Row() {
                Text(item.hospital.level)
                  .fontSize(17)
                  .fontColor(C_TEXT_SUB)
                Text('·').fontSize(17).fontColor('#D4D4D8').margin({ left: 8, right: 8 })
                Text(`${item.hospital.distanceKm} 公里`)
                  .fontSize(17)
                  .fontColor(C_TEXT_SUB)
                Text('·').fontSize(17).fontColor('#D4D4D8').margin({ left: 8, right: 8 })
                Text(item.deptEntry.name)
                  .fontSize(17)
                  .fontColor(C_PRIMARY_DARK)
              }
              .width('100%')
              .margin({ top: 10 })

              if (item.bookable && item.deptEntry.nextSlot.length > 0) {
                Text(`最近可约：${item.deptEntry.nextSlot}`)
                  .fontSize(17)
                  .fontColor('#3F3F46')
                  .width('100%')
                  .margin({ top: 8 })
              }
            }
            .width('100%')
            .padding(22)
            .backgroundColor(C_WHITE)
            .borderRadius(20)
            .alignItems(HorizontalAlign.Start)
          }
          .onClick(() => {
            this.onSelectHospital(item);
          })
        }, (item: HospitalMatch) => item.hospital.id)
      }
      .width('92%')
      .layoutWeight(1)

      if (this.hospitalList.length === 0) {
        Text('暂时没有可挂号的医院，建议直接到院或拨打 120')
          .fontSize(18)
          .fontColor(C_DANGER)
          .textAlign(TextAlign.Center)
          .padding({ left: 32, right: 32, bottom: 60 })
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
  }

  /** 挂号页：真实场景加载医院 H5，演示场景加载内置模拟页 */
  @Builder
  RegisterPage() {
    Column() {
      Row() {
        Text('返回')
          .fontSize(19)
          .fontColor(C_PRIMARY)
          .padding({ left: 20, right: 16, top: 12, bottom: 12 })
          .onClick(() => {
            this.stage = 5;
          })
        Text(this.selected !== null ? `${this.selected.hospital.name} · ${this.selected.deptEntry.name}` : '挂号')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(C_TEXT)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ right: 20 })
      }
      .width('100%')
      .height(64)

      Web({ src: this.webSrc, controller: this.webController })
        .width('100%')
        .layoutWeight(1)
        .domStorageAccess(true)
        .onPageEnd(() => {
          if (this.selected === null) {
            return;
          }
          if (this.usingHisPage) {
            // 真实 HIS 接口页：把后端地址和分诊科室的 department_id 传进去，
            // 页面会直接落在该科室的医生列表，省掉老人自己找科室这一步
            const base: string = AppConfig.HIS_BASE_URL;
            const hisId: string = MiniProgramMap.hisDeptId(this.selected.deptEntry.deptId);
            const dn: string = this.selected.deptEntry.name;
            this.webController.runJavaScript(
              `initPage('${base}', '${hisId}', '${dn}')`
            ).catch((err: BusinessError) => {
              console.error(`注入 HIS 参数失败 ${err.code}`);
            });
            return;
          }
          // 只有内置模拟页才注入；真实医院页面不能注入，否则可能干扰其业务逻辑
          if (!HospitalService.hasRealUrl(this.selected)) {
            const h: string = this.selected.hospital.name;
            const d: string = this.selected.deptEntry.name;
            const s: string = this.selected.deptEntry.nextSlot;
            this.webController.runJavaScript(
              `initPage('${h}', '${d}', '${s}')`
            ).catch((err: BusinessError) => {
              console.error(`注入失败 ${err.code}`);
            });
          }
        })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 急症警示 */
  @Builder
  EmergencyPage() {
    Column() {
      Text('⚠️')
        .fontSize(80)
        .margin({ top: 70 })

      Text(this.triage !== null ? this.triage.primary.evidences[0] : '情况可能比较紧急')
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor(C_WHITE)
        .textAlign(TextAlign.Center)
        .padding({ left: 28, right: 28 })
        .margin({ top: 20 })

      Text(this.triage !== null ? this.triage.primary.hint : '')
        .fontSize(21)
        .lineHeight(38)
        .fontColor(C_WHITE)
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })
        .margin({ top: 24 })

      Text(EMERGENCY_TIP)
        .fontSize(18)
        .fontColor('#FECACA')
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })
        .margin({ top: 20 })

      Blank()

      Button('拨打 120')
        .width('88%')
        .height(100)
        .fontSize(32)
        .fontWeight(FontWeight.Bold)
        .backgroundColor(C_WHITE)
        .fontColor(C_DANGER)
        .borderRadius(50)
        .margin({ bottom: 16 })
        .onClick(() => {
          this.onCall120();
        })

      Button('我了解风险，仍要挂号')
        .width('88%')
        .height(76)
        .fontSize(19)
        .fontColor('#FECACA')
        .backgroundColor('#26FFFFFF')
        .borderRadius(38)
        .margin({ bottom: 44 })
        .onClick(() => {
          this.onGoRegister();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(C_DANGER)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      if (this.stage !== 7) {
        this.TopBar(this.stage === 0 ? '' : '安心挂号', this.stage > 0)
      }

      if (this.stage === 0) {
        this.HomePage()
      } else if (this.stage === 1) {
        this.RecordingPage()
      } else if (this.stage === 2) {
        this.RecognizingPage()
      } else if (this.stage === 3) {
        this.ConfirmPage()
      } else if (this.stage === 4) {
        this.ResultPage()
      } else if (this.stage === 5) {
        this.HospitalPage()
      } else if (this.stage === 6) {
        this.RegisterPage()
      } else {
        this.EmergencyPage()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.stage === 7 ? C_DANGER : C_BG)
    .alignItems(HorizontalAlign.Center)
  }
}
