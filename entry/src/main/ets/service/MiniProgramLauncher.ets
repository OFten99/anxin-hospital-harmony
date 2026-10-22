import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { WXAPIFactory, WXApi, LaunchMiniProgramReq, SendReqResultWrap } from '@tencent/wechat_open_sdk';
import { AppConfig } from './AppConfig';
import { MiniProgramMap } from '../model/MiniProgramMap';

/**
 * 拉起医院微信小程序
 *
 * 产品定位（重要）：本应用是「识货」式的跳转器 ——
 * 只负责把人送到医院自己的挂号小程序，不代填、不代挂、不经手任何交易。
 * 挂号这件事始终发生在医院的小程序里，责任边界清晰。
 *
 * 设计原则：**任何原因导致拉不起来，都必须静默退回内置 H5 挂号页**。
 * 老人已经走到「选医院」这一步了，这时候弹一个技术错误让他自己去理解，
 * 是最糟的处理方式。
 */
export interface LaunchResult {
  /** 是否成功唤起微信 */
  ok: boolean;
  /** 给用户看的一句话，失败时才有内容 */
  message: string;
  /** 内部原因，仅用于日志与分支判断 */
  reason: string;
}

export class MiniProgramLauncher {
  /** 两个 ID 是否都填了。缺任一个都不可能拉起成功 */
  static isConfigured(): boolean {
    return AppConfig.WX_MOBILE_APP_ID.length > 0 && AppConfig.WX_MINI_PROGRAM_ORIGIN_ID.length > 0;
  }

  /** 缺哪个 ID，返回一句人话；都不缺返回空串 */
  static describeMissing(): string {
    if (AppConfig.WX_MOBILE_APP_ID.length === 0) {
      return '还没配置微信开放平台的移动应用 AppID';
    }
    if (AppConfig.WX_MINI_PROGRAM_ORIGIN_ID.length === 0) {
      return '还没配置小程序的原始 ID（gh_ 开头那个）';
    }
    return '';
  }

  /**
   * 拼小程序启动路径。
   *
   * 科室映射不到 department_id 时退到首页：
   * 硬拼一个「只有科室名、没有 department_id」的路径，对方页面查不到医生，
   * 用户看到空白列表，比停在首页更让人困惑。
   */
  static buildPath(deptId: string, deptName: string): string {
    const hisDeptId: string = MiniProgramMap.hisDeptId(deptId);
    if (hisDeptId.length === 0) {
      return MiniProgramMap.HOME_PAGE;
    }
    return `${MiniProgramMap.DEPT_PAGE}?department_id=${hisDeptId}` +
      `&department_name=${encodeURIComponent(deptName)}`;
  }

  /**
   * 唤起微信并打开指定科室。
   *
   * 注意：sendReq 返回 true 只代表「请求已交给微信」，
   * 不代表小程序一定打开成功——微信侧的失败（比如当前微信号不是体验成员）
   * 不会回传给调用方，需要在演示前自己确认账号权限。
   */
  static async launch(ctx: common.UIAbilityContext, deptId: string, deptName: string): Promise<LaunchResult> {
    const missing: string = MiniProgramLauncher.describeMissing();
    if (missing.length > 0) {
      return { ok: false, message: missing, reason: 'not_configured' };
    }

    try {
      const api: WXApi = WXAPIFactory.createWXAPI(AppConfig.WX_MOBILE_APP_ID, ctx);

      if (!api.isWXAppInstalled()) {
        return { ok: false, message: '您手机上没有装微信', reason: 'wechat_not_installed' };
      }

      const req: LaunchMiniProgramReq = new LaunchMiniProgramReq();
      // userName 要的是原始 ID（gh_ 开头），不是 AppID（wx 开头）
      req.userName = AppConfig.WX_MINI_PROGRAM_ORIGIN_ID;
      req.path = MiniProgramLauncher.buildPath(deptId, deptName);
      req.miniprogramType = AppConfig.WX_MINI_PROGRAM_TYPE;
      // 微信处理完返回本应用时，默认回到 EntryAbility，与本工程能力名一致，无需额外指定

      const raw: SendReqResultWrap = api.sendReq(ctx, req);
      const ok: boolean = await Promise.resolve(raw);

      if (!ok) {
        return { ok: false, message: '微信没有打开，先用网页挂号', reason: 'send_req_failed' };
      }
      return { ok: true, message: '', reason: 'ok' };
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      console.error(`拉起小程序异常 code=${err.code} msg=${err.message}`);
      return { ok: false, message: '微信没能打开，先用网页挂号', reason: 'exception' };
    }
  }
}
