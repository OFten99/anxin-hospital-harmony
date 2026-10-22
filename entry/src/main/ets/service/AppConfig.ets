/**
 * 运行时配置
 *
 * 【接入真实服务只需要改这里】
 * 把 asrEndpoint / llmEndpoint 填成你自己的服务地址即可，无需改业务代码。
 *
 * 安全提醒：把 API Key 硬编码在客户端是高风险做法，任何人都能从 hap 包里
 * 提取出来。正式产品必须由自有服务端代理转发，客户端只持有短期票据。
 * 这里的字段仅用于本地联调。
 */
export class AppConfig {
  /** 云端语音识别接口，留空则使用演示模式 */
  static readonly ASR_ENDPOINT: string = '';
  /** 语音识别接口鉴权令牌（联调用，上线须改为服务端代理） */
  static readonly ASR_TOKEN: string = '';

  /** 大模型语义结构化接口，留空则使用本地规则抽取 */
  static readonly LLM_ENDPOINT: string = '';
  static readonly LLM_TOKEN: string = '';

  /** 是否开启语音播报（适老化关键能力，不建议关闭） */
  static readonly TTS_ENABLED: boolean = true;

  /** 是否强制演示模式：true 时不走任何网络请求，便于无网演示 */
  static readonly FORCE_DEMO: boolean = true;

  /** 分诊置信度低于该值时，不做直接挂号，改为引导补充描述 */
  static readonly CONFIDENCE_THRESHOLD: number = 55;

  /** 是否把「说不清」的用户引导到老年医学科兜底 */
  static readonly ENABLE_GERIATRICS_FALLBACK: boolean = true;

  // ───────────────────────── 医院 HIS 后端 ─────────────────────────

  /**
   * 医院门诊管理系统的服务地址。
   *
   * 填了它 → 挂号页加载真实接口（rawfile/his.html），看到的是 HIS 里的真实
   *          科室、医生、号源，挂的号会写进医院数据库。
   * 留空   → 退回内置模拟页（rawfile/reg.html），数据是假的。
   *
   * 注意三点：
   * 1. **鸿蒙模拟器**用 `10.0.2.2`：QEMU 用户态网络里，10.0.2.2 就是宿主机的别名
   *    （实测宿主 10.0.2.15 是模拟器自己，DHCP 段 10.0.2.x，MAC 52:54:00:12:34:56）。
   *    此时写 127.0.0.1 是错的——那是模拟器自己，不是你的电脑。
   * 2. **真机**要换成电脑的局域网 IP（如当前 `10.150.5.254`），且手机与电脑必须
   *    同一网段。校园网常开 AP 隔离，建议手机开热点、电脑连热点再取 IP。
   * 3. 换成局域网 IP 后若访问不到，先查 Windows 防火墙是否放行 5000 端口。
   */
  static readonly HIS_BASE_URL: string = 'http://10.0.2.2:5000';

  // ───────────────────────── 微信小程序拉起配置 ─────────────────────────
  //
  // 这里最容易错的地方：小程序有两个完全不同的 ID，用途不通用。
  //
  //   AppID（wx 开头）  →  只用于「上传代码到微信服务器」，
  //                        填在 miniapp 仓库的 project.config.json 里
  //  原始ID（gh_ 开头） →  只用于「从别的 App 拉起这个小程序」，
  //                        填在下面的 WX_MINI_PROGRAM_ORIGIN_ID
  //
  // 把 wx 的 AppID 填到 ORIGIN_ID 里，拉起会失败。

  /**
   * 微信开放平台「移动应用（HarmonyOS）」的 AppID，wx 开头。
   * 注意：这是「本应用自己」在微信开放平台注册得到的 ID，
   * 不是被拉起小程序的 AppID。
   * 留空 = 关闭小程序拉起，全部走内置 H5 挂号页（当前默认状态）。
   */
  static readonly WX_MOBILE_APP_ID: string = '';

  /**
   * 被拉起小程序的**原始 ID**，gh_ 开头。
   * 获取位置：小程序后台 → 设置 → 基本设置 → 账号信息 → 原始ID
   *
   * 当前值来自「经常有的小窝」（个人主体，类目 工具>预约/报名）。
   * 对应 AppID 为 wxxxxxxxxxxxxxxxxx —— 那个只用于上传代码，不要填到这里。
   */
  static readonly WX_MINI_PROGRAM_ORIGIN_ID: string = 'gh_xxxxxxxxxxxxxxxx';

  /**
   * 拉起哪个版本：0 正式版 / 1 开发版 / 2 体验版
   *
   * 演示阶段用 2（体验版），因为体验版不经审核即可存在；
   * 但体验版的打开者必须已在小程序后台被加为「体验成员」，否则微信会拒绝。
   */
  static readonly WX_MINI_PROGRAM_TYPE: number = 2;
}
