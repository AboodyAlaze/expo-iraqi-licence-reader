import { useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';

import {
  scanBack,
  scanFront,
  scanFull,
  type LicenceCategory,
  type LicenceFront,
} from 'expo-iraqi-licence-reader';

/** أيقونة لكل فئة — إيموجي، بدون أي مكتبة */
const CATEGORY_ICON: Record<string, string> = {
  A1: '🛵',
  A: '🏍️',
  B: '🚗',
  BE: '🚙',
  C1: '🚚',
  C: '🚛',
  C1E: '🚚',
  CE: '🚛',
  D1: '🚐',
  D: '🚌',
  D1E: '🚐',
  DE: '🚍',
  T: '🚜',
};

/** رسالة عربية لكل كود خطأ */
function errorMessage(e: any): string {
  switch (e?.code) {
    case 'CAMERA_DENIED':
      return 'صلاحية الكاميرا مرفوضة — فعّلها من إعدادات الجهاز';
    case 'SCAN_CANCELLED':
      return '';
    case 'BUSY':
      return 'ماسح ثاني شغّال';
    default:
      return `${e?.code ?? ''} ${e?.message ?? 'صار خطأ'}`.trim();
  }
}

export default function App() {
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const [front, setFront] = useState<LicenceFront | null>(null);
  const [categories, setCategories] = useState<LicenceCategory[]>([]);
  const [showLines, setShowLines] = useState(false);

  /** يشغّل أي عملية مسح ويدير الحالة والأخطاء */
  const run = async (job: () => Promise<void>) => {
    setBusy(true);
    setMessage('');
    try {
      await job();
    } catch (e: any) {
      setMessage(errorMessage(e));
    } finally {
      setBusy(false);
    }
  };

  const handleFull = () =>
    run(async () => {
      setFront(null);
      setCategories([]);
      const result = await scanFull({
        // يظهر بين الوجه والظهر
        beforeBack: () =>
          new Promise<void>((resolve) => {
            Alert.alert('تم مسح الوجه ✔', 'هسه اقلب البطاقة للظهر', [
              { text: 'جاهز', onPress: () => resolve() },
            ]);
          }),
      });
      const { categories: cats, ...rest } = result;
      setFront(rest);
      setCategories(cats);
    });

  const handleFront = () =>
    run(async () => {
      setFront(await scanFront());
    });

  const handleBack = () =>
    run(async () => {
      setCategories(await scanBack());
    });

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <Text style={styles.title}>قارئ إجازة السياقة</Text>
      <Text style={styles.subtitle}>يدعم الإصدار الاتحادي وإصدار إقليم كردستان</Text>

      <Button label="📷  مسح كامل (وجه ثم ظهر)" onPress={handleFull} disabled={busy} primary />
      <View style={styles.row2}>
        <Button label="الوجه فقط" onPress={handleFront} disabled={busy} flex />
        <Button label="الظهر فقط" onPress={handleBack} disabled={busy} flex />
      </View>

      {busy && <ActivityIndicator style={{ marginTop: 16 }} />}
      {message ? <Text style={styles.error}>{message}</Text> : null}

      {front && <FrontView data={front} showLines={showLines} onToggleLines={() => setShowLines((v) => !v)} />}

      {categories.length > 0 && (
        <View>
          <Text style={styles.section}>فئات الإجازة</Text>
          <Text style={styles.hint}>
            كل فئة لها تواريخ مستقلة — ممكن تكون وحدة سارية وأخرى منتهية
          </Text>
          {categories.map((c) => (
            <CategoryCard key={c.code} c={c} />
          ))}
        </View>
      )}
    </ScrollView>
  );
}

// ---------- الوجه ----------

function FrontView({
  data,
  showLines,
  onToggleLines,
}: {
  data: LicenceFront;
  showLines: boolean;
  onToggleLines: () => void;
}) {
  const v = data.viz;
  const variant =
    data.mrz?.variant === 'FEDERAL'
      ? 'اتحادي'
      : data.mrz?.variant === 'KURDISTAN'
        ? 'إقليم كردستان'
        : '';

  return (
    <View>
      {/* حالة التحقق */}
      <View style={[styles.banner, data.verified ? styles.bannerOk : styles.bannerWarn]}>
        <Text style={[styles.bannerText, { color: data.verified ? '#1b5e20' : '#e65100' }]}>
          {data.verified
            ? '✔ الـ MRZ مقروء ومؤكَّد من عدة إطارات'
            : '⚠ ما انقرأ الـ MRZ — البيانات من وجه البطاقة فقط'}
        </Text>
        {variant ? <Text style={styles.bannerSub}>نوع الإصدار: {variant}</Text> : null}
      </View>

      {/* تعارض بين الـ MRZ والمطبوع */}
      {data.mrz && v.licenceNumber && !data.mrzMatchesViz && (
        <View style={[styles.banner, styles.bannerBad]}>
          <Text style={[styles.bannerText, { color: '#c62828' }]}>
            ⚠ رقم الوجه ما يطابق الـ MRZ — أعد المسح
          </Text>
          <Text style={styles.mono}>
            MRZ: {data.mrz.licenceNumber}  |  الوجه: {v.licenceNumber}
          </Text>
        </View>
      )}

      <Text style={styles.section}>بيانات مضمونة (من الـ MRZ)</Text>
      <Row label="رقم الإجازة" value={data.mrz?.licenceNumber ?? ''} />
      {data.mrz && data.mrz.nationalNumber === '' && (
        <Text style={styles.hint}>الرقم الوطني مو مخزون بالـ MRZ بهذا الإصدار — شوفه تحت</Text>
      )}
      <Row label="الرقم الوطني" value={data.mrz?.nationalNumber ?? ''} />
      {data.mrz && <Text style={styles.mono}>{data.mrz.raw}</Text>}

      <Text style={styles.section}>بيانات تقريبية (من وجه البطاقة)</Text>
      <View style={styles.approx}>
        <Text style={styles.approxText}>هذي الحقول ما عندها رقم تحقق — راجعها قبل الاعتماد عليها</Text>
      </View>
      <Row label="الاسم (لاتيني)" value={v.nameLatin} />
      <Row label="الاسم (عربي)" value={v.nameArabic} />
      <Row label="تاريخ الميلاد" value={v.dateOfBirth} />
      <Row label="تاريخ الإصدار" value={v.dateOfIssue} />
      <Row label="تاريخ الانتهاء" value={v.dateOfExpiry} />
      <Row label="مكتب الإصدار" value={v.issuingOffice} />
      <Row label="الرقم الوطني" value={v.nationalNumber} />
      <Row label="الجنسية" value={v.nationality} />
      <Row label="فصيلة الدم" value={v.bloodType} />
      <Row label="الفئة (من الوجه)" value={v.categories} />
      <Row label="العنوان" value={v.address} />

      {/* تشخيص */}
      <TouchableOpacity onPress={onToggleLines}>
        <Text style={styles.link}>{showLines ? '▾ إخفاء كل النص المقروء' : '▸ كل النص المقروء (للتشخيص)'}</Text>
      </TouchableOpacity>
      {showLines && v.allLines.map((l, i) => (
        <Text key={i} style={styles.line}>• {l}</Text>
      ))}
    </View>
  );
}

// ---------- الفئات ----------

function CategoryCard({ c }: { c: LicenceCategory }) {
  const accent = c.isValid ? '#1b5e20' : '#c62828';
  return (
    <View style={[styles.card, { backgroundColor: c.isValid ? '#f1f8e9' : '#ffebee' }]}>
      <Text style={styles.icon}>{CATEGORY_ICON[c.code] ?? '🚗'}</Text>
      <View style={{ flex: 1 }}>
        <Text style={[styles.code, { color: accent }]}>
          {c.code}  <Text style={styles.label}>{c.label}</Text>
        </Text>
        <Text style={styles.dates}>من {c.issueDate}</Text>
        <Text style={styles.dates}>إلى {c.expiryDate}</Text>
      </View>
      <View style={[styles.badge, { backgroundColor: accent }]}>
        <Text style={styles.badgeText}>{c.isValid ? 'سارية' : 'منتهية'}</Text>
      </View>
    </View>
  );
}

// ---------- مكوّنات صغيرة ----------

function Row({ label, value }: { label: string; value: string }) {
  if (!value) return null;
  return (
    <View style={styles.row}>
      <Text style={styles.rowLabel}>{label}: </Text>
      <Text style={styles.rowValue}>{value}</Text>
    </View>
  );
}

function Button({
  label,
  onPress,
  disabled,
  primary,
  flex,
}: {
  label: string;
  onPress: () => void;
  disabled?: boolean;
  primary?: boolean;
  flex?: boolean;
}) {
  return (
    <TouchableOpacity
      onPress={onPress}
      disabled={disabled}
      style={[
        styles.button,
        primary ? styles.buttonPrimary : styles.buttonSecondary,
        flex && { flex: 1 },
        disabled && { opacity: 0.5 },
      ]}>
      <Text style={[styles.buttonText, { color: primary ? '#fff' : '#3f51b5' }]}>{label}</Text>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#fff' },
  content: { padding: 20, paddingTop: 70, paddingBottom: 60 },
  title: { fontSize: 24, fontWeight: '700', textAlign: 'right' },
  subtitle: { fontSize: 13, color: '#888', textAlign: 'right', marginBottom: 16 },

  button: { paddingVertical: 14, borderRadius: 12, alignItems: 'center', marginTop: 10 },
  buttonPrimary: { backgroundColor: '#3f51b5' },
  buttonSecondary: { borderWidth: 1.5, borderColor: '#3f51b5' },
  buttonText: { fontSize: 16, fontWeight: '600' },
  row2: { flexDirection: 'row', gap: 10 },

  error: { marginTop: 14, color: '#c62828', textAlign: 'right' },

  banner: { padding: 12, borderRadius: 8, marginTop: 20 },
  bannerOk: { backgroundColor: '#e8f5e9' },
  bannerWarn: { backgroundColor: '#fff3e0' },
  bannerBad: { backgroundColor: '#ffebee', marginTop: 10 },
  bannerText: { fontSize: 13, fontWeight: '600', textAlign: 'right' },
  bannerSub: { fontSize: 12, color: '#1b5e20', textAlign: 'right', marginTop: 2 },

  section: { fontSize: 16, fontWeight: '700', marginTop: 22, marginBottom: 6, textAlign: 'right' },
  hint: { fontSize: 12, color: '#888', textAlign: 'right', marginBottom: 6 },

  approx: { backgroundColor: '#fff8e1', padding: 10, borderRadius: 8, marginBottom: 6 },
  approxText: { fontSize: 12, color: '#795548', textAlign: 'right' },

  row: { flexDirection: 'row-reverse', marginVertical: 3 },
  rowLabel: { fontWeight: '600', fontSize: 14 },
  rowValue: { fontSize: 14, flexShrink: 1 },

  mono: { fontFamily: 'monospace', fontSize: 11, color: '#555', textAlign: 'left', marginTop: 4 },
  link: { color: '#3f51b5', marginTop: 20, textAlign: 'right' },
  line: { fontSize: 11, color: '#666', textAlign: 'right', marginTop: 2 },

  card: {
    flexDirection: 'row-reverse',
    alignItems: 'center',
    padding: 12,
    borderRadius: 12,
    marginBottom: 8,
    gap: 12,
  },
  icon: { fontSize: 34 },
  code: { fontSize: 18, fontWeight: '700', textAlign: 'right' },
  label: { fontSize: 13, fontWeight: '400', color: '#555' },
  dates: { fontSize: 12, color: '#555', textAlign: 'right', fontVariant: ['tabular-nums'] },
  badge: { paddingHorizontal: 10, paddingVertical: 4, borderRadius: 12 },
  badgeText: { color: '#fff', fontSize: 11, fontWeight: '600' },
});
