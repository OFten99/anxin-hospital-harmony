import { HOSPITALS } from '../model/HospitalData';
import { Hospital, HospitalMatch, DeptEntry } from '../model/Types';

/**
 * 医院匹配服务
 *
 * 多医院整合的价值不在于"把所有医院列出来"，而在于替老人做减法：
 * 只给出「有这个科室 + 现在能挂上号 + 距离可接受」的少数几家。
 *
 * 排序因子：可预约优先 > 距离近 > 医院等级。
 * 对老年人而言，"今天能看上"的权重要高于"医院名气大"，
 * 因此可预约与否放在第一优先级。
 */
export class HospitalService {
  /** 按科室匹配医院，返回已排序结果 */
  static match(deptId: string): HospitalMatch[] {
    const list: HospitalMatch[] = [];

    for (let i = 0; i < HOSPITALS.length; i++) {
      const hospital: Hospital = HOSPITALS[i];
      for (let j = 0; j < hospital.departments.length; j++) {
        const entry: DeptEntry = hospital.departments[j];
        if (entry.deptId === deptId) {
          list.push({
            hospital: hospital,
            deptEntry: entry,
            bookable: entry.bookable
          });
          break;
        }
      }
    }

    if (list.length === 0) {
      return HospitalService.matchFallback();
    }

    list.sort((a: HospitalMatch, b: HospitalMatch) => {
      return HospitalService.rank(b) - HospitalService.rank(a);
    });
    return list;
  }

  /** 没有对应专科时，退回全科/老年科，避免把老人卡在死胡同 */
  private static matchFallback(): HospitalMatch[] {
    const list: HospitalMatch[] = [];
    for (let i = 0; i < HOSPITALS.length; i++) {
      const hospital: Hospital = HOSPITALS[i];
      for (let j = 0; j < hospital.departments.length; j++) {
        const entry: DeptEntry = hospital.departments[j];
        if (entry.deptId === 'general_practice' || entry.deptId === 'geriatrics') {
          list.push({ hospital: hospital, deptEntry: entry, bookable: entry.bookable });
          break;
        }
      }
    }
    list.sort((a: HospitalMatch, b: HospitalMatch) => {
      return HospitalService.rank(b) - HospitalService.rank(a);
    });
    return list;
  }

  /** 综合排序分 */
  private static rank(m: HospitalMatch): number {
    let score: number = 0;
    if (m.bookable) {
      score += 45;
    }
    score += Math.max(0, 40 - m.hospital.distanceKm * 6);

    if (m.hospital.level.indexOf('三级甲等') >= 0) {
      score += 25;
    } else if (m.hospital.level.indexOf('二级甲等') >= 0) {
      score += 15;
    } else if (m.hospital.level.indexOf('三级') >= 0) {
      score += 18;
    }
    return score;
  }

  /** 判断是否已有真实挂号地址 */
  static hasRealUrl(m: HospitalMatch): boolean {
    return m.deptEntry.url.length > 0;
  }
}
