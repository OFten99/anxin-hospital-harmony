# 拉起微信小程序挂号：接入方案

> 本文所有技术细节来自微信官方文档，链接附在文末。涉及规则的部分建议接入前再核对一次，微信的策略调整较频繁。

## 一、结论

**鸿蒙 App 拉起指定微信小程序，官方支持。** 微信 Open SDK for HarmonyOS 从 **1.0.3** 版本开始提供 `LaunchMiniProgramReq` 接口。

这条路径适用于"聚合导流"型产品：App 只负责判断挂什么科、去哪家医院，把用户送到医院自己的挂号小程序里，交易在医院侧完成。

## 二、三种拉起方式，只有一种适合第三方聚合

| 方式 | 能否只靠小程序 ID 拉起 | 有效期 | 是否适合本项目 |
| --- | --- | --- | --- |
| **Open SDK `launchMiniProgram`** | ✅ 只需 `userName` + `path` | 无（实时请求） | ✅ **推荐** |
| URL Scheme（`weixin://dl/business/?t=TICKET`） | ❌ 需小程序方生成 TICKET | 最长 30 天 | ❌ 不适用 |
| URL Link（`https://wxaurl.cn/xxx`） | ❌ 需小程序方生成 | 最长 30 天 | ❌ 不适用 |

**为什么不用 URL Scheme / URL Link：**

1. 生成接口 `generatescheme` / `generate_urllink` 必须用**该小程序自己的** `access_token` 调用。你是第三方，拿不到别人家小程序的凭证。
2. 自 2022 年 4 月 11 日起规则收紧：**每个链接被一个用户访问后，其他用户就不能再用同一条链接打开**。这直接排除了"配置一批链接给所有用户"的做法。
3. 都要 30 天续期。

而 SDK 的 `launchMiniProgram` 是实时请求，只传小程序原始 ID 和页面 path，没有上述限制。**这是唯一能规模化的路径。**

## 三、接入前置条件（缺一不可）

### 1. 微信开放平台移动应用账号（审核制）

- 去 `open.weixin.qq.com` 创建「移动应用」
- **平台必须选 HarmonyOS**，填写鸿蒙应用的 Bundle Name（本项目是 `com.anxin.hospital`）
- 提交审核，通过后拿到移动应用 AppID（`wx` 开头）
- ⚠️ 这个 AppID 是**你自己的移动应用 ID，不是医院小程序的 AppID**，两者别混

审核需要企业主体资质，周期通常几天。**这一步没过，代码写了也调不通。**

### 2. 目标小程序的原始 ID（`gh_` 开头）

每家医院一个。获取方式：
- 医院提供（最合规）
- 或从该小程序的介绍页 / 小程序码解析

注意是**原始 ID（gh_xxx）**，不是 AppID（wx 开头）。

### 3. 目标页面的 path

形如 `pages/registration/dept?deptId=0301`。

**这是最大的卡点**：path 是小程序内部路由，外部看不到，只有医院开发方知道。也就是说——

> **没有医院配合，你只能拉起小程序首页，无法直达科室。**

对老人来说，"进了小程序还要自己找到心血管内科"这一步，体验会明显打折。所以能直达科室的医院才是真正好用的合作方。

不要试图通过反编译小程序去扒 path，有法律风险。

## 四、集成步骤

> ✅ **步骤 1~5 已在工程中完成并编译通过**（`BUILD SUCCESSFUL`，产物 `entry-default-unsigned.hap`）。
> 现在只需在 `AppConfig.ets` 填两个 ID 即可启用。本节保留完整过程，供你核对与二次开发。

### 步骤 1：安装 SDK

已在 `entry/oh-package.json5` 写入 `"@tencent/wechat_open_sdk": "1.0.23"`，并通过 ohpm 装好（实测 ohpm 仓库在本机网络下可访问，1.5 秒完成）：

```bash
ohpm install @tencent/wechat_open_sdk@1.0.23
```

可用版本：`1.0.0 / 1.0.3 / 1.0.4 / 1.0.6 / 1.0.7 / 1.0.11 / 1.0.14 / 1.0.15 / 1.0.16 / 1.0.17 / 1.0.18 / 1.0.19 / 1.0.20 / 1.0.21 / 1.0.23`，latest 为 `1.0.23`。

### 步骤 2：配置 querySchemes

`entry/src/main/module.json5` 的 `module` 节点下加：

```json5
"querySchemes": ["weixin", "wxopensdk"]
```

不加这行，`isWXAppInstalled` 之类的检测会失败。

### 步骤 3：封装拉起服务

新建 `entry/src/main/ets/service/MiniProgramLauncher.ets`：

```ts
import * as wxopensdk from '@tencent/wechat_open_sdk';
import { common } from '@kit.AbilityKit';

/** 目标小程序信息 */
export interface MiniProgramTarget {
  /** 小程序原始 ID，gh_ 开头 */
  userName: string;
  /** 目标页面路径，可带 query；为空则拉起首页 */
  path: string;
}

export class MiniProgramLauncher {
  /**
   * 拉起微信小程序。
   * 返回 false 时调用方应降级到 H5 或其他方式。
   */
  static async launch(context: common.UIAbilityContext,
    target: MiniProgramTarget): Promise<boolean> {
    if (target.userName.length === 0) {
      return false;
    }
    try {
      const req = new wxopensdk.LaunchMiniProgramReq();
      req.userName = target.userName;
      req.path = target.path;
      // 0 正式版 / 1 开发版 / 2 体验版
      req.miniprogramType = 0;
      return await wxopensdk.WXApi.sendReq(context, req);
    } catch (e) {
      return false;
    }
  }

  /** 检测设备是否装了微信 */
  static isWeChatInstalled(): boolean {
    try {
      return wxopensdk.WXApi.isWXAppInstalled();
    } catch (e) {
      return false;
    }
  }
}
```

### 步骤 4：医院配置加小程序字段

`model/Types.ets` 的 `Hospital` 接口增加：

```ts
/** 该院的微信挂号小程序；未接入时为空 */
miniProgramId: string;
/** 该院小程序里挂号页的路径 */
miniProgramPath: string;
```

`HospitalData.ets` 里每家医院填上。没有合作的就留空串，App 自动回退到 H5。

### 步骤 5：跳转处按优先级分发

在 `Index.ets` 的 `onSelectHospital()` 里改成三段式：

```ts
// 1 优先拉起医院小程序
if (m.hospital.miniProgramId.length > 0 && MiniProgramLauncher.isWeChatInstalled()) {
  const ok = await MiniProgramLauncher.launch(ctx, {
    userName: m.hospital.miniProgramId,
    path: m.hospital.miniProgramPath
  });
  if (ok) {
    return;
  }
}
// 2 降级到 H5
if (HospitalService.hasRealUrl(m)) {
  this.webSrc = m.deptEntry.url;
  this.stage = 6;
  return;
}
// 3 再降级到内置模拟页 / 提示
```

## 五、必须处理的失败场景

| 场景 | 处理 |
| --- | --- |
| 用户没装微信 | 提示"需要先安装微信"，并给出 H5 兜底 |
| 用户点了系统弹窗的"取消" | 微信会弹确认框，用户选不跳转就拉不起来，要给二次提示 |
| 医院换了 path | 小程序改版会导致 path 失效，需要能做远程配置下发，别硬编码在客户端 |
| 该院没接合作 | 回退 H5，或直接提示"该院暂不支持在线挂号" |

## 六、合规与商业边界（这条比技术重要）

1. **"识货"能跳淘宝，是因为有淘宝客的正式合作**。同理，聚合医院挂号如果想长期做，需要与医院或其互联网医院运营方签协议。否则一旦规模做大，容易被认定为未授权导流。
2. **不要代挂号、不要碰交易与支付。** 你的定位是"导诊 + 导流"，一旦介入挂号成功与否、退号、支付，责任和资质要求完全不同。
3. **跳转前明确告知**："即将打开 XX 医院的微信小程序"，让用户知道离开了你的服务。
4. 医院名称、科室、号源信息展示，要有数据来源授权，不能自己编。

## 七、参考文档

- 鸿蒙应用拉起小程序开发示例：`https://developers.weixin.qq.com/doc/oplatform/Mobile_App/Launching_a_Mini_Program/OHOS_Development_example.html`
- 获取加密 scheme 码：`https://developers.weixin.qq.com/minigame/dev/api-backend/url-scheme/api_generatescheme.html`
- 小程序链接规则调整公告：`http://fuwu.weixin.qq.com/community/develop/doc/000aeab88a4ea0c5c89d81fde5b801`
- 外部网页跳转小程序 FAQ：`https://developers.weixin.qq.com/community/develop/doc/00086c74744b80deb27bf757f5bc00`
