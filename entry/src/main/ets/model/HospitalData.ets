import { Hospital, DeptEntry } from './Types';

/**
 * 多医院挂号入口配置
 *
 * 【数据说明】以下医院名称、距离、地址、号源均为演示用虚构数据，
 * 不代表任何真实医疗机构。正式接入时按以下步骤替换：
 *
 *   1. 与医院信息科确认其 H5 挂号页的「科室直达」地址格式；
 *   2. 若支持 URL 带参直达，把真实地址填进 DeptEntry.url，
 *      例如 https://reg.example.com/book?deptId=0301；
 *   3. 若不支持带参，DeptEntry.url 留空字符串，
 *      App 会打开内置模拟挂号页（便于演示，不具备真实挂号能力）；
 *   4. deptId 必须与 TriageData.ets 中的科室标识保持一致。
 */

/**
 * 构造科室入口：标识、院内名称、是否可约、最近号源、真实挂号地址。
 * url 传空字符串时，App 会打开内置模拟挂号页（仅演示用）。
 * 填了真实地址，就直接加载医院自己的挂号页。
 */
function dept(deptId: string, name: string, bookable: boolean, nextSlot: string,
  url: string = ''): DeptEntry {
  return { deptId: deptId, name: name, url: url, bookable: bookable, nextSlot: nextSlot };
}

export const HOSPITALS: Hospital[] = [
  {
    id: 'h1',
    name: '市第一人民医院',
    level: '三级甲等',
    distanceKm: 2.3,
    address: '示例路 1 号（演示数据）',
    fallbackUrl: '',
    departments: [
      dept('cardiology', '心血管内科', true, '今天 15:30'),
      dept('neurology', '神经内科', true, '明天 09:00'),
      dept('respiratory', '呼吸内科', true, '今天 16:00'),
      dept('gastroenterology', '消化内科', true, '明天 10:30'),
      dept('endocrinology', '内分泌科', true, '明天 14:00'),
      dept('nephrology', '肾内科', false, ''),
      dept('orthopedics', '骨科', true, '今天 14:00'),
      dept('urology', '泌尿外科', true, '明天 08:30'),
      dept('ophthalmology', '眼科', true, '今天 17:00'),
      dept('ent', '耳鼻咽喉科', true, '明天 11:00'),
      dept('dermatology', '皮肤科', true, '明天 15:00'),
      dept('psychiatry', '精神心理科', false, ''),
      dept('geriatrics', '老年医学科', true, '明天 09:30'),
      dept('general_surgery', '普通外科', true, '明天 13:30'),
      dept('emergency', '急诊科', true, '24 小时开放')
    ]
  },
  {
    id: 'h2',
    name: '市中心医院',
    level: '三级甲等',
    distanceKm: 4.1,
    address: '示例大道 88 号（演示数据）',
    fallbackUrl: '',
    departments: [
      dept('cardiology', '心血管内科', true, '明天 08:30'),
      dept('neurology', '神经内科', true, '今天 15:00'),
      dept('respiratory', '呼吸内科', true, '明天 10:00'),
      dept('gastroenterology', '消化内科', true, '今天 16:30'),
      dept('endocrinology', '内分泌科', true, '明天 09:00'),
      dept('nephrology', '肾内科', true, '明天 14:30'),
      dept('orthopedics', '骨科', true, '明天 11:00'),
      dept('urology', '泌尿外科', true, '今天 17:30'),
      dept('ophthalmology', '眼科', false, ''),
      dept('ent', '耳鼻咽喉科', true, '明天 09:30'),
      dept('dermatology', '皮肤科', true, '今天 14:30'),
      dept('geriatrics', '老年医学科', true, '今天 15:30'),
      dept('emergency', '急诊科', true, '24 小时开放')
    ]
  },
  {
    id: 'h3',
    name: '区人民医院',
    level: '二级甲等',
    distanceKm: 1.2,
    address: '示例街 23 号（演示数据）',
    fallbackUrl: '',
    departments: [
      dept('cardiology', '心血管内科', true, '今天 14:00'),
      dept('gastroenterology', '消化内科', true, '今天 15:00'),
      dept('respiratory', '呼吸内科', true, '明天 09:30'),
      dept('orthopedics', '骨科', true, '今天 16:00'),
      dept('ophthalmology', '眼科', true, '明天 10:00'),
      dept('dermatology', '皮肤科', true, '今天 14:30'),
      dept('geriatrics', '老年医学科', false, ''),
      dept('emergency', '急诊科', true, '24 小时开放')
    ]
  },
  {
    id: 'h4',
    name: '市中医院',
    level: '三级甲等',
    distanceKm: 3.5,
    address: '示例巷 6 号（演示数据）',
    fallbackUrl: '',
    departments: [
      dept('cardiology', '心血管内科', true, '明天 09:00'),
      dept('gastroenterology', '消化内科', true, '明天 14:00'),
      dept('neurology', '脑病科', false, ''),
      dept('orthopedics', '骨伤科', true, '今天 15:30'),
      dept('geriatrics', '老年病科', true, '今天 16:30'),
      dept('rehabilitation', '康复医学科', true, '明天 10:30'),
      dept('dermatology', '皮肤科', true, '明天 15:30')
    ]
  },
  {
    id: 'h5',
    name: '社区卫生服务中心',
    level: '一级',
    distanceKm: 0.8,
    address: '示例小区东门（演示数据）',
    fallbackUrl: '',
    departments: [
      dept('general_practice', '全科门诊', true, '今天 14:00'),
      dept('geriatrics', '老年医学科', true, '今天 15:00'),
      dept('cardiology', '心血管内科', true, '明天 09:00')
    ]
  }
];

/** 急诊提示语 */
export const EMERGENCY_TIP: string = '如情况紧急，请直接拨打 120，比在 App 里挂号更快。';
