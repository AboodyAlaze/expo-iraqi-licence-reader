import type { CategoryCode } from './ExpoIraqiLicenceReader.types';

/** رموز الفئات بترتيب صفوف الجدول بظهر البطاقة */
export const CATEGORY_ORDER: readonly CategoryCode[] = [
  'A1',
  'A',
  'B',
  'C1',
  'C',
  'D1',
  'D',
  'BE',
  'C1E',
  'CE',
  'D1E',
  'DE',
  'T',
];

/** وصف عربي لكل فئة */
export const CATEGORY_LABELS: Readonly<Record<CategoryCode, string>> = {
  A1: 'دراجة صغيرة',
  A: 'دراجة نارية',
  B: 'سيارة خصوصي',
  C1: 'شاحنة خفيفة',
  C: 'شاحنة',
  D1: 'باص صغير',
  D: 'باص',
  BE: 'خصوصي مع مقطورة',
  C1E: 'شاحنة خفيفة مع مقطورة',
  CE: 'شاحنة مع مقطورة',
  D1E: 'باص صغير مع مقطورة',
  DE: 'باص مع مقطورة',
  T: 'ساحبة',
};

/**
 * هل التاريخ (DD/MM/YYYY) ما زال ساري؟
 *
 * التاريخ المفقود أو غير المفهوم يرجع true — ما نحكم بالانتهاء
 * بدون دليل. يوم الانتهاء نفسه يُعدّ ساري.
 */
export function isDateValid(expiry: string, now: Date = new Date()): boolean {
  const m = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(expiry);
  if (!m) return true;

  const day = Number(m[1]);
  const month = Number(m[2]);
  const year = Number(m[3]);

  const ty = now.getFullYear();
  const tm = now.getMonth() + 1;
  const td = now.getDate();

  if (year !== ty) return year > ty;
  if (month !== tm) return month > tm;
  return day >= td;
}
