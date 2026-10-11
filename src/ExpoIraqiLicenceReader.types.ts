/** إصدار الإجازة */
export type LicenceVariant = 'FEDERAL' | 'KURDISTAN';

/** رموز الفئات بترتيب ظهورها بجدول ظهر البطاقة */
export type CategoryCode =
  | 'A1'
  | 'A'
  | 'B'
  | 'C1'
  | 'C'
  | 'D1'
  | 'D'
  | 'BE'
  | 'C1E'
  | 'CE'
  | 'D1E'
  | 'DE'
  | 'T';

/**
 * السطر السفلي من وجه البطاقة (MRZ).
 *
 * موثوق: رقم التحقق + اتفاق 3 إطارات على نفس القراءة.
 */
export type LicenceMrz = {
  /** مثل D12345678 */
  licenceNumber: string;
  /** فاضي بالإصدار الاتحادي — موجود بإصدار الإقليم فقط */
  nationalNumber: string;
  /** السطر الكامل (30 خانة) بعد إعادة بنائه بالصيغة القياسية */
  raw: string;
  variant: LicenceVariant;
};

/**
 * الحقول المطبوعة على وجه البطاقة.
 *
 * ⚠️ تقريبية: ما عندها رقم تحقق، وأي غلطة بالـ OCR تمر بصمت.
 * راجعها قبل الاعتماد عليها. التواريخ بصيغة DD/MM/YYYY.
 */
export type LicenceViz = {
  /** الاسم بالحروف اللاتينية — الحقل الأكثر موثوقية بين حقول الاسم */
  nameLatin: string;
  /** ⚠️ غالباً فاضي: محرّكا الـ OCR لا يقرآن الخط العربي */
  nameArabic: string;
  dateOfBirth: string;
  dateOfIssue: string;
  dateOfExpiry: string;
  issuingOffice: string;
  nationalNumber: string;
  nationality: string;
  bloodType: string;
  licenceNumber: string;
  categories: string;
  /** ⚠️ غالباً فاضي — عربي */
  address: string;
  /** كل سطر قرأه الـ OCR — للتشخيص */
  allLines: string[];
};

/** نتيجة مسح وجه البطاقة */
export type LicenceFront = {
  /** هل انقرأ الـ MRZ وانتأكد؟ false يعني البيانات من الوجه فقط */
  verified: boolean;
  mrz: LicenceMrz | null;
  /** هل رقم الإجازة المطبوع يطابق رقم الـ MRZ؟ إشارة ثقة قوية لباقي حقول الوجه */
  mrzMatchesViz: boolean;
  /** رقم الإجازة — من الـ MRZ إن وُجد، وإلا من الوجه */
  licenceNumber: string;
  /** الرقم الوطني — من الـ MRZ إن وُجد، وإلا من الوجه */
  nationalNumber: string;
  viz: LicenceViz;
};

/**
 * فئة واحدة من جدول ظهر البطاقة.
 * كل فئة لها تواريخ مستقلة — ممكن تكون الدراجة منتهية والسيارة سارية.
 */
export type LicenceCategory = {
  code: CategoryCode;
  /** وصف عربي مختصر مثل "سيارة خصوصي" */
  label: string;
  /** DD/MM/YYYY */
  issueDate: string;
  /** DD/MM/YYYY */
  expiryDate: string;
  /** سارية حسب تاريخ الجهاز وقت المسح */
  isValid: boolean;
};

/** نتيجة المسح الكامل: وجه + ظهر */
export type LicenceData = LicenceFront & {
  categories: LicenceCategory[];
};

export type ScanFullOptions = {
  /**
   * يُستدعى بعد انتهاء مسح الوجه وقبل فتح كاميرا الظهر.
   * استعمله لتعرض للمستخدم رسالة "اقلب البطاقة" — ارجع Promise
   * يخلص لما يكون جاهز.
   */
  beforeBack?: () => void | Promise<void>;
};
