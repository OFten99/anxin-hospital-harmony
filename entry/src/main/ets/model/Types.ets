/**
 * 全局数据模型定义
 *
 * 设计说明：
 * 1. 所有类型集中定义，服务层与 UI 层共用，避免结构漂移。
 * 2. 生产环境下 TriegeKnowledge / HospitalConfig 应由服务端下发，
 *    本地这份仅作为离线兜底与首启默认值。
 */

/** 症状 → 科室 映射规则 */
export interface SymptomRule {
  /** 科室唯一标识，与医院配置中的科室 key 对应 */
  deptId: string;
  /** 科室显示名称 */
  deptName: string;
  /** 症状所在身体部位词（权重最高） */
  bodyParts: string[];
  /** 症状描述词 */
  symptoms: string[];
  /** 上下文线索：人群、病史、诱因 */
  contextWords: string[];
  /** 基础权重，用于区分强关联与弱关联科室 */
  weight: number;
  /** 面向老人的一句推荐话术 */
  hint: string;
}

/** 危急信号（红旗症状）。命中即提示立即就医，不做普通挂号 */
export interface RedFlag {
  id: string;
  /** 一句话风险标题，用于大字提示 */
  title: string;
  /** 处置建议 */
  advice: string;
  /**
   * 必要条件：二维数组，外层每组内「任一命中」即可，
   * 所有组都命中才算触发。
   * 例：[["胸痛","胸口疼"],["大汗","冒冷汗"]] 表示
   * 既提到胸痛类词、又提到出汗类词才触发。
   */
  requireGroups: string[][];
  /** 目标科室 */
  targetDeptId: string;
}

/** 从语音文本中抽取出的结构化症状信息 */
export interface SymptomProfile {
  /** 原始语音转写文本 */
  rawText: string;
  /** 命中的身体部位词 */
  bodyParts: string[];
  /** 命中的症状词 */
  symptoms: string[];
  /** 命中的上下文线索词 */
  contexts: string[];
  /** 抽取出的持续时长描述，未提及则为空串 */
  duration: string;
  /** 命中的红旗症状，无则为空数组 */
  redFlags: RedFlag[];
  /** 是否有「说不清具体位置」的情况，需要追问 */
  vague: boolean;
}

/** 单个科室的分诊结果 */
export interface DeptCandidate {
  deptId: string;
  deptName: string;
  /** 0~100 的匹配分 */
  score: number;
  /** 命中的依据词，用于向老人解释「为什么推荐这个科」 */
  evidences: string[];
  hint: string;
}

/** 完整分诊结论 */
export interface TriageResult {
  /** 首选科室 */
  primary: DeptCandidate;
  /** 备选科室，最多 2 个 */
  alternates: DeptCandidate[];
  /** 是否触发危急信号 */
  emergency: boolean;
  /** 危急时给出的处置建议 */
  emergencyAdvice: string;
  /** 0~100 置信度，低于 55 时 UI 应引导用户补充描述 */
  confidence: number;
  /** 是否信息不足需要追问 */
  needMoreInfo: boolean;
  /** 追问话术 */
  askBackText: string;
}

/** 医院某个科室的挂号入口 */
export interface DeptEntry {
  /** 标准化科室标识，与分诊结果对齐 */
  deptId: string;
  /** 科室在挂号系统里的名称，可能与本地命名不同 */
  name: string;
  /** 挂号页地址（H5） */
  url: string;
  /** 是否可预约 */
  bookable: boolean;
  /** 最近可约号源，空串表示暂无 */
  nextSlot: string;
}

/** 合作医院配置 */
export interface Hospital {
  id: string;
  name: string;
  level: string;
  /** 距离，单位公里 */
  distanceKm: number;
  /** 科室入口表：key 为标准化 deptId */
  departments: DeptEntry[];
  /** 医院总挂号入口，科室未匹配时兜底 */
  fallbackUrl: string;
  address: string;
}

/** 匹配到科室后的医院候选 */
export interface HospitalMatch {
  hospital: Hospital;
  deptEntry: DeptEntry;
  bookable: boolean;
}

/** 语音识别状态 */
export enum AsrState {
  IDLE = 0,
  RECORDING = 1,
  RECOGNIZING = 2,
  DONE = 3,
  FAILED = 4
}

/** 演示用语音样例 */
export interface VoiceSample {
  id: string;
  /** 老人口吻的原话 */
  text: string;
  /** 一句话标签，帮助演示者选择 */
  tag: string;
}
