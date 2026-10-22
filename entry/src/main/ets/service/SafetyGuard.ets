/**
 * 输出安全护栏
 *
 * 定位：模型/规则产出任何一段要给老人看的文字，在展示和播报之前过一遍这里。
 *
 * 为什么单独做一层：
 * 当前分诊由确定性规则产出，不会说"您得了心脏病"。但只要接入大模型生成
 * 解释话术，模型极易滑向诊断性表述（"您这种情况很可能是冠心病"）。
 * 一旦输出疾病判断，产品就从"挂号导航"变成"医疗诊断软件"，
 * 进入医疗器械监管范围。这层护栏是最后一道闸。
 *
 * 参考做法来自开源项目 Health-Flow 的安全护栏设计思路：
 * 不是靠提示词约束模型，而是在模型输出之后用确定性规则拦截。
 */
export class SafetyGuard {
  /** 诊断性、绝对化表述，出现即拦截 */
  private static BANNED: string[] = [
    '确诊', '诊断为', '您患有', '您得了', '您这是', '一定是', '肯定是',
    '百分之百', '包治', '药到病除', '保证治好', '不用去医院'
  ];

  /** 通用保守话术：拦下之后替换成这句 */
  private static FALLBACK: string = '这个情况需要医生当面判断，我先帮您挂对应的科室。';

  /** 页面与播报必须常驻的免责声明 */
  static readonly DISCLAIMER: string = '本应用只提供科室推荐，不做诊断。紧急情况请拨 120。';

  /**
   * 过滤一段面向用户的文本。
   * 命中禁用词时整体替换，而不是做局部删改——局部删改容易留下半句话，
   * 反而产生新的歧义。
   */
  static sanitize(text: string): string {
    if (text.length === 0) {
      return text;
    }
    for (let i = 0; i < SafetyGuard.BANNED.length; i++) {
      if (text.indexOf(SafetyGuard.BANNED[i]) >= 0) {
        return SafetyGuard.FALLBACK;
      }
    }
    return text;
  }

  /**
   * 校验一段即将播报的话。返回可直接播报的文本。
   * 危急场景必须带"立即就医"语义，否则补上提示。
   */
  static sanitizeWithEmergency(text: string, emergency: boolean): string {
    const safe: string = SafetyGuard.sanitize(text);
    if (!emergency) {
      return safe;
    }
    if (safe.indexOf('120') >= 0 || safe.indexOf('急诊') >= 0 || safe.indexOf('就医') >= 0) {
      return safe;
    }
    return `${safe} 请尽快拨打 120 或前往急诊。`;
  }
}
