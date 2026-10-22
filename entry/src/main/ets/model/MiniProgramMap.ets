/**
 * 本项目科室标识 → 医院 HIS 系统 department_id 的映射
 *
 * 数据来源：2026-10-23 对本地后端实测
 *   GET http://127.0.0.1:5000/api/mini/departments
 *
 * 实测结果：该 HIS 只有 6 个科室，本项目分诊有 17 个科室，必须做收敛映射。
 *
 * 为什么必须单独建表：
 * 本项目用可读字符串（cardiology / orthopedics）做科室标识，
 * 医院 HIS 里是数据库自增整数。两者不能互推，只能显式映射。
 *
 * 留空会怎样：
 * 该科室被留空时，拉起小程序会退到首页（pages/index/index），
 * 而不是拼一个「有科室名、没 department_id」的页面——
 * 那种页面在对方系统里查不到医生，用户看到的是空列表，比退回首页更差。
 *
 * 映射原则：
 * 只做临床上说得通的收敛。小医院的「内科」实际承接心血管、呼吸、消化、
 * 内分泌、肾内等亚专业（实测该院内科医生张建国的专长就是"心血管内科"，
 * 李慧是"呼吸系统疾病"），所以这些亚专业映射到内科是有依据的。
 * 说不过去的（如耳鼻咽喉科）宁可留空退首页，也不硬塞进外科——
 * 把病人送到错误科室，比让他自己再选一次伤害更大。
 */
export interface HisDeptRef {
  /** 本项目使用的科室标识 */
  deptId: string;
  /** 医院 HIS 数据库中的 department_id，实测得到；留空表示该院无对应科室 */
  departmentId: string;
  /** 映射依据，写给自己和评审看的一句话 */
  note: string;
}

const HIS_DEPT_TABLE: HisDeptRef[] = [
  // ── 收敛到 内科（department_id = 1）── 该院内科承担全部内科亚专业
  { deptId: 'cardiology', departmentId: '1', note: '该院内科医生专长含"心血管内科"' },
  { deptId: 'respiratory', departmentId: '1', note: '该院内科医生专长含"呼吸系统疾病"' },
  { deptId: 'neurology', departmentId: '1', note: '小医院神经内科并入内科' },
  { deptId: 'gastroenterology', departmentId: '1', note: '消化内科并入内科' },
  { deptId: 'endocrinology', departmentId: '1', note: '内分泌科并入内科' },
  { deptId: 'nephrology', departmentId: '1', note: '肾内科并入内科' },
  { deptId: 'geriatrics', departmentId: '1', note: '该院无独立老年科，走内科' },
  { deptId: 'general_practice', departmentId: '1', note: '全科兜底走内科' },

  // ── 收敛到 外科（department_id = 2）──
  { deptId: 'general_surgery', departmentId: '2', note: '普通外科即外科' },
  { deptId: 'urology', departmentId: '2', note: '泌尿外科属外科专业' },

  // ── 一一对应 ──
  { deptId: 'orthopedics', departmentId: '5', note: '骨科，实测有医生孙强' },
  { deptId: 'ophthalmology', departmentId: '6', note: '眼科' },

  // ── 该院无对应科室：故意留空，拉起时退小程序首页 ──
  { deptId: 'ent', departmentId: '', note: '该院无耳鼻咽喉科，不硬塞外科' },
  { deptId: 'dermatology', departmentId: '', note: '该院无皮肤科' },
  { deptId: 'psychiatry', departmentId: '', note: '该院无精神心理科' },
  { deptId: 'rehabilitation', departmentId: '', note: '该院无康复医学科' },
  { deptId: 'emergency', departmentId: '', note: '急诊不走预约挂号' }
];

export class MiniProgramMap {
  /** 小程序首页，作为科室无法映射时的兜底落点 */
  static readonly HOME_PAGE: string = 'pages/index/index';
  /** 科室医生列表页，本项目推荐的跳转目标 */
  static readonly DEPT_PAGE: string = 'pages/doctors/doctors';

  /** 取 HIS department_id，查不到返回空串 */
  static hisDeptId(deptId: string): string {
    for (let i = 0; i < HIS_DEPT_TABLE.length; i++) {
      if (HIS_DEPT_TABLE[i].deptId === deptId) {
        return HIS_DEPT_TABLE[i].departmentId;
      }
    }
    return '';
  }

  /** 取映射依据，用于自检与文档生成 */
  static note(deptId: string): string {
    for (let i = 0; i < HIS_DEPT_TABLE.length; i++) {
      if (HIS_DEPT_TABLE[i].deptId === deptId) {
        return HIS_DEPT_TABLE[i].note;
      }
    }
    return '';
  }

  /** 统计可直接直达科室的数量，用于界面提示与文档 */
  static mappedCount(): number {
    let n: number = 0;
    for (let i = 0; i < HIS_DEPT_TABLE.length; i++) {
      if (HIS_DEPT_TABLE[i].departmentId.length > 0) {
        n = n + 1;
      }
    }
    return n;
  }
}
