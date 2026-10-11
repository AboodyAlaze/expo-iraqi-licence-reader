import NativeModule from './ExpoIraqiLicenceReaderModule';
import { CATEGORY_LABELS, CATEGORY_ORDER, isDateValid } from './categories';
import type {
  CategoryCode,
  LicenceCategory,
  LicenceData,
  LicenceFront,
  LicenceMrz,
  LicenceVariant,
  LicenceViz,
  ScanFullOptions,
} from './ExpoIraqiLicenceReader.types';

export type {
  CategoryCode,
  LicenceCategory,
  LicenceData,
  LicenceFront,
  LicenceMrz,
  LicenceVariant,
  LicenceViz,
  ScanFullOptions,
};

export { CATEGORY_LABELS, CATEGORY_ORDER, isDateValid };

type RawCategory = { code: string; issueDate: string; expiryDate: string };

/** هل صلاحية الكاميرا ممنوحة؟ لا يطلبها — المسح يطلبها تلقائياً أول مرة */
export function hasCameraPermission(): boolean {
  return NativeModule.hasCameraPermission();
}

/**
 * يفتح الكاميرا على **وجه** الإجازة.
 *
 * يرجع لما ينتأكد الـ MRZ بثلاثة إطارات متطابقة. إذا ما انقرأ بعد
 * محاولات كثيرة، يظهر للمستخدم زر "اكتفِ بقراءة الوجه" وترجع النتيجة
 * بـ `verified: false`.
 *
 * يرفض بأحد الأكواد: `CAMERA_DENIED` · `SCAN_CANCELLED` · `NO_ACTIVITY` · `BUSY`
 */
export async function scanFront(): Promise<LicenceFront> {
  const json = await NativeModule.scanFront();
  return JSON.parse(json) as LicenceFront;
}

/**
 * يفتح الكاميرا على **ظهر** الإجازة ويقرأ جدول الفئات.
 *
 * لازم الجدول كامل داخل الإطار. يرجع لما إطاران يتفقان على نفس النتيجة.
 */
export async function scanBack(): Promise<LicenceCategory[]> {
  const json = await NativeModule.scanBack();
  const raw = JSON.parse(json) as RawCategory[];

  return raw.map((c) => {
    const code = c.code as CategoryCode;
    return {
      code,
      label: CATEGORY_LABELS[code] ?? '',
      issueDate: c.issueDate,
      expiryDate: c.expiryDate,
      isValid: isDateValid(c.expiryDate),
    };
  });
}

/**
 * مسح كامل: الوجه ثم الظهر.
 *
 * بين الخطوتين يستدعي `options.beforeBack` حتى تعرض للمستخدم
 * رسالة "اقلب البطاقة".
 */
export async function scanFull(options: ScanFullOptions = {}): Promise<LicenceData> {
  const front = await scanFront();
  if (options.beforeBack) await options.beforeBack();
  const categories = await scanBack();
  return { ...front, categories };
}

export default {
  hasCameraPermission,
  scanFront,
  scanBack,
  scanFull,
  isDateValid,
};
