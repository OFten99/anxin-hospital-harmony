import { DeptCandidate, RedFlag, SymptomProfile, TriageResult, SymptomRule } from '../model/Types';
import { SYMPTOM_RULES, RED_FLAGS, VAGUE_WORDS, DURATION_WORDS } from '../model/TriageData';

/**
 * 分诊引擎
 *
 * 职责：把一段口语化文本，变成「结构化症状 + 科室建议 + 风险等级」。
 *
 * 为什么不让大模型直接输出科室：
 * 1. 大模型对科室命名不稳定（可能说「心内科」「心血管科」「循环内科」）；
 * 2. 危急症状必须确定性拦截，不能靠概率；
 * 3. 需要向老人解释「为什么推荐这个科」，规则命中词可直接作为依据展示。
 *
 * 因此分工是：大模型负责把话说清楚（抽取结构化症状），
 * 规则引擎负责把症状映射成科室（确定性、可解释、可审计）。
 */
export class TriageEngine {
  /** 将文本归一化：去掉标点与空白，便于词表匹配 */
  private static normalize(text: string): string {
    return text.replace(/[，。！？、,.!?\s"'（）()【】]/g, '');
  }

  /** 判断词是否出现在归一化文本中 */
  private static hit(hay: string, word: string): boolean {
    return word.length > 0 && hay.indexOf(word) >= 0;
  }

  /**
   * 抽取结构化症状。
   * 若外部已通过大模型得到结构化结果，可直接构造 SymptomProfile，
   * 本方法仅作为离线兜底。
   */
  static extract(rawText: string): SymptomProfile {
    const hay: string = TriageEngine.normalize(rawText);
    const bodyParts: string[] = [];
    const symptoms: string[] = [];
    const contexts: string[] = [];
    const flags: RedFlag[] = [];

    for (let i = 0; i < SYMPTOM_RULES.length; i++) {
      const rule: SymptomRule = SYMPTOM_RULES[i];
      TriageEngine.collect(hay, rule.bodyParts, bodyParts);
      TriageEngine.collect(hay, rule.symptoms, symptoms);
      TriageEngine.collect(hay, rule.contextWords, contexts);
    }

    // 派生信号：老人常说「腿还有点肿」「脚肿了」，部位词与「肿」被别的字隔开，
    // 规则表里的「腿肿」命中不了。这里把两者都出现的情况补成规范词，
    // 否则下肢水肿会被误判成骨科的「肿」。
    const hasSwelling: boolean = hay.indexOf('肿') >= 0;
    const hasLimb: boolean = hay.indexOf('腿') >= 0 || hay.indexOf('脚') >= 0 ||
      hay.indexOf('下肢') >= 0;
    // 外伤引起的肿归骨科，不能推到心内科/肾内科
    let hasTrauma: boolean = false;
    const traumaWords: string[] = ['崴', '摔', '扭', '撞', '外伤', '磕', '砸'];
    for (let i = 0; i < traumaWords.length; i++) {
      if (hay.indexOf(traumaWords[i]) >= 0) {
        hasTrauma = true;
        break;
      }
    }
    if (hasSwelling && hasLimb && !hasTrauma && symptoms.indexOf('腿肿') < 0) {
      symptoms.push('腿肿');
    }

    for (let i = 0; i < RED_FLAGS.length; i++) {
      const flag: RedFlag = RED_FLAGS[i];
      let allGroupsHit: boolean = true;
      for (let g = 0; g < flag.requireGroups.length; g++) {
        const group: string[] = flag.requireGroups[g];
        let groupHit: boolean = false;
        for (let w = 0; w < group.length; w++) {
          if (TriageEngine.hit(hay, group[w])) {
            groupHit = true;
            break;
          }
        }
        if (!groupHit) {
          allGroupsHit = false;
          break;
        }
      }
      if (allGroupsHit) {
        flags.push(flag);
      }
    }

    let duration: string = '';
    for (let i = 0; i < DURATION_WORDS.length; i++) {
      if (TriageEngine.hit(hay, DURATION_WORDS[i])) {
        duration = DURATION_WORDS[i];
        break;
      }
    }

    let vagueHit: boolean = false;
    const vagueWords: string[] = [];
    for (let i = 0; i < VAGUE_WORDS.length; i++) {
      if (TriageEngine.hit(hay, VAGUE_WORDS[i])) {
        vagueHit = true;
        vagueWords.push(VAGUE_WORDS[i]);
      }
    }

    // 只有模糊词、没有任何具体部位和症状 → 判为「说不清」
    const vague: boolean = vagueHit && bodyParts.length === 0 && symptoms.length === 0;

    return {
      rawText: rawText,
      bodyParts: bodyParts,
      symptoms: symptoms,
      contexts: contexts,
      duration: duration,
      redFlags: flags,
      vague: vague
    };
  }

  /** 去重收集命中的词 */
  private static collect(hay: string, words: string[], bucket: string[]): void {
    for (let i = 0; i < words.length; i++) {
      const w: string = words[i];
      if (TriageEngine.hit(hay, w) && bucket.indexOf(w) < 0) {
        bucket.push(w);
      }
    }
  }

  /**
   * 主入口：文本 → 分诊结论
   */
  static triage(rawText: string): TriageResult {
    const profile: SymptomProfile = TriageEngine.extract(rawText);

    // 第一优先：危急信号拦截，不做普通分诊
    if (profile.redFlags.length > 0) {
      const flag: RedFlag = profile.redFlags[0];
      const emergency: DeptCandidate = {
        deptId: flag.targetDeptId,
        deptName: '急诊科',
        score: 100,
        evidences: [flag.title],
        hint: flag.advice
      };
      return {
        primary: emergency,
        alternates: [],
        emergency: true,
        emergencyAdvice: flag.advice,
        confidence: 100,
        needMoreInfo: false,
        askBackText: ''
      };
    }

    // 第二步：按规则表打分
    const scores: Map<string, number> = new Map<string, number>();
    const evidences: Map<string, string[]> = new Map<string, string[]>();
    const deptNames: Map<string, string> = new Map<string, string>();
    const deptHints: Map<string, string> = new Map<string, string>();

    for (let i = 0; i < SYMPTOM_RULES.length; i++) {
      const rule: SymptomRule = SYMPTOM_RULES[i];
      let raw: number = 0;
      const ev: string[] = [];

      for (let p = 0; p < profile.bodyParts.length; p++) {
        const word: string = profile.bodyParts[p];
        if (rule.bodyParts.indexOf(word) >= 0) {
          // 部位命中权重最高，长词更精确额外加成
          raw += 3 * rule.weight + (word.length >= 3 ? 0.5 : 0);
          ev.push(word);
        }
      }
      for (let s = 0; s < profile.symptoms.length; s++) {
        const word: string = profile.symptoms[s];
        if (rule.symptoms.indexOf(word) >= 0) {
          raw += 2 * rule.weight + (word.length >= 3 ? 0.5 : 0);
          ev.push(word);
        }
      }
      for (let c = 0; c < profile.contexts.length; c++) {
        const word: string = profile.contexts[c];
        if (rule.contextWords.indexOf(word) >= 0) {
          // 病史线索权重略高于普通症状词：有高血压的老人说心慌，
          // 心血管内科的优先级应当明显高于其他科。
          raw += 1.5 * rule.weight;
          ev.push(word);
        }
      }

      if (raw > 0) {
        scores.set(rule.deptId, raw);
        evidences.set(rule.deptId, ev);
        deptNames.set(rule.deptId, rule.deptName);
        deptHints.set(rule.deptId, rule.hint);
      }
    }

    // 第三步：排序取候选
    const candidates: DeptCandidate[] = [];
    scores.forEach((value: number, key: string) => {
      const ev: string[] = evidences.get(key) ?? [];
      candidates.push({
        deptId: key,
        deptName: deptNames.get(key) ?? key,
        score: 0,
        evidences: ev,
        hint: deptHints.get(key) ?? ''
      });
      // 暂存原始分在 score 字段，稍后统一归一化
      const last: DeptCandidate = candidates[candidates.length - 1];
      last.score = value * 10;
    });

    candidates.sort((a: DeptCandidate, b: DeptCandidate) => b.score - a.score);

    // 没有任何命中 → 引导补充描述
    if (candidates.length === 0) {
      return TriageEngine.buildAskBack(profile, '没能听清具体是哪里不舒服');
    }

    // 第四步：置信度。原始分越高越可信；与次优科室越接近，越可疑
    const topRaw: number = candidates[0].score / 10;
    let confidence: number = Math.round(100 * (1 - Math.exp(-topRaw / 4)));
    if (candidates.length > 1) {
      const secondRaw: number = candidates[1].score / 10;
      if (secondRaw / topRaw > 0.75) {
        confidence = Math.round(confidence * 0.82);
      }
    }
    // 只有模糊表述时压低置信度
    if (profile.vague) {
      confidence = Math.min(confidence, 40);
    }

    const primary: DeptCandidate = candidates[0];
    primary.score = confidence;

    const alternates: DeptCandidate[] = [];
    for (let i = 1; i < candidates.length && alternates.length < 2; i++) {
      const item: DeptCandidate = candidates[i];
      if (item.score >= topRaw * 4) {
        item.score = Math.round(confidence * 0.7);
        alternates.push(item);
      }
    }

    const needMoreInfo: boolean = confidence < 55 ||
      (profile.symptoms.length === 0 && profile.bodyParts.length === 0);

    return {
      primary: primary,
      alternates: alternates,
      emergency: false,
      emergencyAdvice: '',
      confidence: confidence,
      needMoreInfo: needMoreInfo,
      askBackText: needMoreInfo ? TriageEngine.buildAskBack(profile, '还不太确定').askBackText : ''
    };
  }

  /** 构造追问话术 */
  private static buildAskBack(profile: SymptomProfile, reason: string): TriageResult {
    let question: string = '';
    if (profile.vague) {
      question = '您说的是全身不舒服，能再说说主要是哪个地方难受吗？比如头、胸口、肚子、腰腿。';
    } else if (profile.bodyParts.length === 0) {
      question = '您能说说具体是身体哪个部位不舒服吗？比如头、胸口、肚子、腰、腿。';
    } else if (profile.symptoms.length === 0) {
      question = '您这个部位是怎么个难受法？是疼、是胀、是麻，还是没劲？';
    } else {
      question = '我还没太听明白，您能再描述一下是哪里、怎么个难受法吗？';
    }

    const fallback: DeptCandidate = {
      deptId: 'geriatrics',
      deptName: '老年医学科',
      score: 30,
      evidences: [reason],
      hint: '说不清具体科室时，老年医学科可以帮您综合判断'
    };

    return {
      primary: fallback,
      alternates: [],
      emergency: false,
      emergencyAdvice: '',
      confidence: 30,
      needMoreInfo: true,
      askBackText: question
    };
  }
}
