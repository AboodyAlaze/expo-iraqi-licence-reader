# expo-iraqi-licence-reader

Scan **Iraqi driving licences** with the camera in Expo / React Native apps —
both the **federal** card and the **Kurdistan Region** card.

Point the camera at the front, then the back. You get the licence number, the
printed fields, and **every licence class with its own issue/expiry dates and a
valid/expired flag**.

Everything runs **on the device**. No image is ever uploaded.

| | Android | iOS |
|---|---|---|
| OCR engine | ML Kit Text Recognition | Vision (built into iOS) |
| Added app size | a few MB (ML Kit + CameraX) | none |
| Minimum OS | follows your Expo SDK | iOS 15.1 |

---

## ⚠️ Read this first

**This is OCR, not a chip read.** Iraqi driving licences have no NFC chip, so
there is no cryptographic way to prove a card is genuine. The library reads what
is printed on the card — a forged card that *looks* right will be read as if it
were real.

**Do not use it as proof of identity or for KYC.**

What you *can* rely on, and how much:

| Data | Source | Trust |
|---|---|---|
| Licence number, national number (Kurdistan cards) | MRZ line | **High** — check digit **and** three matching frames |
| Licence classes and their dates | Back of card | **Medium** — two matching frames, no check digit |
| Latin name, dates of birth/issue/expiry, blood type, … | Front of card | **Approximate** — no check digit; a misread passes silently |

The result tells you how far to trust it: `verified`, and `mrzMatchesViz`
(whether the printed licence number agrees with the MRZ — a strong signal that
the rest of the front was read correctly too).

Always show front-of-card fields to the user for confirmation before storing
them.

---

## Install

```bash
npx expo install expo-iraqi-licence-reader
```

`app.json`:

```json
{
  "expo": {
    "plugins": ["expo-iraqi-licence-reader"]
  }
}
```

```bash
npx expo prebuild --clean
```

The plugin adds the camera permission on Android and `NSCameraUsageDescription`
on iOS. You do not edit any native file.

**Expo Go will not work** — this is native code, so you need a development build
(`npx expo run:android` / `npx expo run:ios`). The camera does not work in
simulators; use a real device.

### Plugin options

```json
{
  "plugins": [
    ["expo-iraqi-licence-reader", {
      "cameraPermission": "We scan your licence to fill in your details. Images never leave your phone."
    }]
  ]
}
```

---

## Quick start

```tsx
import { useState } from 'react';
import { Button, Text, View } from 'react-native';
import { scanFull, type LicenceData } from 'expo-iraqi-licence-reader';

export default function App() {
  const [data, setData] = useState<LicenceData | null>(null);
  const [error, setError] = useState('');

  const handleScan = async () => {
    try {
      const result = await scanFull();
      console.log(JSON.stringify(result, null, 2));
      setData(result);
    } catch (e: any) {
      setError(e.code ?? e.message);
    }
  };

  return (
    <View style={{ padding: 24, paddingTop: 80 }}>
      <Button title="Scan licence" onPress={handleScan} />
      {error ? <Text>{error}</Text> : null}
      {data && <Text>{data.licenceNumber}</Text>}
    </View>
  );
}
```

`scanFull()` opens the camera on the front, then on the back. Camera permission
is requested automatically the first time.

---

## Full example

A complete screen: asks the user to flip the card between the two scans, handles
every error, and lists each class with its dates and status.

```tsx
import { useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Button,
  FlatList,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import {
  scanFull,
  type LicenceCategory,
  type LicenceData,
} from 'expo-iraqi-licence-reader';

export default function LicenceScreen() {
  const [busy, setBusy] = useState(false);
  const [data, setData] = useState<LicenceData | null>(null);
  const [message, setMessage] = useState('');

  const handleScan = async () => {
    setBusy(true);
    setData(null);
    setMessage('');

    try {
      const result = await scanFull({
        // Shown between the two scans — resolve when the user is ready
        beforeBack: () =>
          new Promise<void>((resolve) => {
            Alert.alert('Front done', 'Now flip the card to the back.', [
              { text: 'Ready', onPress: () => resolve() },
            ]);
          }),
      });
      setData(result);
    } catch (e: any) {
      switch (e.code) {
        case 'CAMERA_DENIED':
          setMessage('Camera access is needed to scan the licence.');
          break;
        case 'SCAN_CANCELLED':
          break; // user closed the scanner — nothing to report
        default:
          setMessage(e.message ?? 'Something went wrong. Please try again.');
      }
    } finally {
      setBusy(false);
    }
  };

  return (
    <FlatList
      contentContainerStyle={styles.content}
      data={data?.categories ?? []}
      keyExtractor={(c) => c.code}
      ListHeaderComponent={
        <View>
          <Button title="Scan licence" onPress={handleScan} disabled={busy} />
          {busy && <ActivityIndicator style={{ marginTop: 16 }} />}
          {message ? <Text style={styles.error}>{message}</Text> : null}

          {data && (
            <View style={{ marginTop: 20 }}>
              <Text style={data.verified ? styles.ok : styles.warn}>
                {data.verified
                  ? 'MRZ read and confirmed'
                  : 'MRZ not read — front fields only'}
              </Text>
              {data.mrz && !data.mrzMatchesViz && (
                <Text style={styles.warn}>
                  The printed licence number differs from the MRZ — rescan.
                </Text>
              )}

              <Text style={styles.row}>Licence no.: {data.licenceNumber}</Text>
              {data.nationalNumber ? (
                <Text style={styles.row}>National no.: {data.nationalNumber}</Text>
              ) : null}
              <Text style={styles.row}>Name: {data.viz.nameLatin}</Text>
              <Text style={styles.row}>Arabic name: {data.viz.nameArabic}</Text>
              <Text style={styles.row}>Born: {data.viz.dateOfBirth}</Text>
              <Text style={styles.row}>Blood type: {data.viz.bloodType}</Text>

              <Text style={styles.section}>Classes</Text>
            </View>
          )}
        </View>
      }
      renderItem={({ item }) => <ClassRow c={item} />}
    />
  );
}

function ClassRow({ c }: { c: LicenceCategory }) {
  return (
    <View style={[styles.card, { backgroundColor: c.isValid ? '#f1f8e9' : '#ffebee' }]}>
      <View style={{ flex: 1 }}>
        <Text style={styles.code}>
          {c.code}  <Text style={styles.label}>{c.label}</Text>
        </Text>
        <Text style={styles.dates}>
          {c.issueDate} → {c.expiryDate}
        </Text>
      </View>
      <Text style={{ color: c.isValid ? '#1b5e20' : '#c62828', fontWeight: '700' }}>
        {c.isValid ? 'Valid' : 'Expired'}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  content: { padding: 20, paddingTop: 80 },
  error: { marginTop: 12, color: '#c62828' },
  ok: { color: '#1b5e20', fontWeight: '600' },
  warn: { color: '#e65100', fontWeight: '600', marginTop: 4 },
  row: { marginTop: 4 },
  section: { marginTop: 20, marginBottom: 8, fontWeight: '700', fontSize: 16 },
  card: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 12,
    borderRadius: 10,
    marginBottom: 8,
  },
  code: { fontSize: 18, fontWeight: '700' },
  label: { fontSize: 13, fontWeight: '400', color: '#555' },
  dates: { marginTop: 2, color: '#555', fontVariant: ['tabular-nums'] },
});
```

---

## One side at a time

Use `scanFront()` / `scanBack()` when you only need one side, or want your own
flow between them:

```tsx
import { scanBack, scanFront } from 'expo-iraqi-licence-reader';

const front = await scanFront();
console.log(front.licenceNumber, front.viz.nameLatin);

// …show your own "flip the card" screen…

const categories = await scanBack();
categories.forEach((c) =>
  console.log(c.code, c.label, c.issueDate, c.expiryDate, c.isValid)
);
```

---

## API

| Function | Returns | Notes |
|---|---|---|
| `scanFront()` | `Promise<LicenceFront>` | Opens the camera on the front |
| `scanBack()` | `Promise<LicenceCategory[]>` | Opens the camera on the back |
| `scanFull(options?)` | `Promise<LicenceData>` | Front, then back |
| `hasCameraPermission()` | `boolean` | Does not prompt |
| `isDateValid(expiry, now?)` | `boolean` | Helper used for `isValid` |
| `CATEGORY_ORDER` / `CATEGORY_LABELS` | constants | Class codes and Arabic labels |

`scanFull({ beforeBack })` calls `beforeBack` between the two scans; await a
promise there to show a "flip the card" prompt.

### `LicenceFront`

| Field | Type | Meaning |
|---|---|---|
| `verified` | `boolean` | MRZ was read and confirmed. `false` = front fields only |
| `mrz` | `LicenceMrz \| null` | `{ licenceNumber, nationalNumber, raw, variant }` |
| `mrzMatchesViz` | `boolean` | Printed licence number agrees with the MRZ |
| `licenceNumber` | `string` | From the MRZ if present, otherwise the front |
| `nationalNumber` | `string` | From the MRZ if present, otherwise the front |
| `viz` | `LicenceViz` | Printed fields — **approximate**, see above |

`mrz.variant` is `'FEDERAL'` or `'KURDISTAN'`. The federal card does **not** store
the national number in the MRZ — `mrz.nationalNumber` is empty and the value
comes from the front (`viz.nationalNumber`, field 4d).

### `LicenceViz`

`nameLatin` · `nameArabic` · `dateOfBirth` · `dateOfIssue` · `dateOfExpiry` ·
`issuingOffice` · `nationalNumber` · `nationality` · `bloodType` ·
`licenceNumber` · `categories` · `address` · `allLines`

Dates are `DD/MM/YYYY`. Any field can be an empty string. `allLines` is every
line the OCR saw — handy for debugging a card that reads badly.

### `LicenceCategory`

| Field | Example |
|---|---|
| `code` | `'B'` |
| `label` | `'سيارة خصوصي'` |
| `issueDate` | `'21/06/2021'` |
| `expiryDate` | `'11/07/2029'` |
| `isValid` | `true` |

Each class has its **own** dates — a motorcycle class can be expired while the
car class is still valid on the same card. `isValid` is computed from the
device's date at scan time; an unreadable date counts as valid (no verdict
without evidence).

### Errors

Every rejection carries a `code`:

| Code | Cause |
|---|---|
| `CAMERA_DENIED` | The user refused camera access |
| `SCAN_CANCELLED` | The user closed the scanner |
| `NO_ACTIVITY` | No foreground activity / view controller |
| `BUSY` | Another scan is already running |
| `SCAN_FAILED` | Native side returned no result |

---

## Getting a good read

Accuracy depends on the photo far more than on the code:

- Put the card on a **light, plain surface** — not a dark one
- **Side lighting**, so the plastic doesn't glare
- Hold it **straight**, not tilted
- **Front:** let the bottom line (the MRZ) fill the width of the screen, and hold
  still until the `3 / 3` counter completes
- **Back:** keep the **whole table** in frame, from the first row to the last,
  with the code column on the right

If the front's MRZ can't be read after a while, a **"read front only"** button
appears and the result comes back with `verified: false`.

---

## How it works

**The bottom line (MRZ)** is 30 characters. The federal and Kurdistan cards share
a layout but differ in one field:

```
Kurdistan:  D< D12345678 1234567890123 <<<<< 9
Federal:    D< D12345678 <<<<<<<<<<<<< <<<<< 2
                         └ national number is empty
```

The last digit is an ICAO 9303 check digit (weights 7-3-1). A check digit is only
one in ten, so a *wrong* read still passes about 10% of the time — which is why
the scanner requires **three frames to agree** before accepting.

The federal card has 18 identical `<` characters in a row, and OCR engines
routinely drop or add one. So the parser does not rely on a fixed length: it
finds `D<` + letter + 8 digits, strips every `<`, and counts what is left
(one digit → federal, fourteen → Kurdistan), then rebuilds the canonical line and
verifies it.

**The class table on the back** is the hard part. It has 13 rows, mostly empty,
and the OCR reads the one-letter codes (`A`, `B`, `C`) unreliably — it often
finds `A1` and `D1` but skips the rest. Matching dates to "the nearest code that
was read" therefore puts them on the wrong class.

Instead, the codes that *were* read are used as reference points, a straight line
is fitted through them (row index → vertical position) to get the row height, and
each date pair is assigned to a row by its position. A class is identified even
if its own code was never read. The same expiry date repeats down several rows,
so rows are separated by position, never de-duplicated by value.

---

## Notes

- Verified on a small number of real cards, both federal and Kurdistan Region,
  on both platforms. Cards from other issuing offices or older editions may
  differ — if one reads badly, open an issue with the `allLines` output
  (redact personal details first).
- **Arabic and Kurdish text is not recognised.** Both OCR engines run in Latin
  mode (ML Kit's Latin recognizer; Vision with `en-US`), so `viz.nameArabic` and
  `viz.address` will usually be **empty**. Use `viz.nameLatin` for the name. The
  parser does handle Arabic if an engine returns it; adding an Arabic-capable
  recogniser is the main gap.
- Android adds ML Kit and CameraX; iOS adds nothing.

---

## Run the example

The repo ships a ready-to-run example app in `example/`. From the repo root:

```bash
npm install          # builds the package + plugin and links everything
npm run android      # or: npm run ios
```

Needs a **real device** (the camera does not work in simulators). `npm run ios`
needs a paid Apple Developer team — set yours in `example/app.json`
(`ios.appleTeamId`) and change `ios.bundleIdentifier` to one that is free in your
account.

Handy scripts:

| Script | What it does |
|---|---|
| `npm run android` / `npm run ios` | Build and run the example on a connected device |
| `npm run start` | Start Metro for the dev client |
| `npm run build` | Compile `src/` and `plugin/` to `build/` and `plugin/build/` |
| `npm run open:android` / `open:ios` | Open the generated native project in Android Studio / Xcode |

The example imports the package through `tsconfig` paths (so JS changes show up
instantly) and loads the config plugin through a self-link that `npm install`
creates in `node_modules`. After editing native code (`android/` or `ios/`),
just run `npm run android` / `npm run ios` again.

### Publishing

```bash
npm run build
npm pack --dry-run   # check: build/, plugin/build/, app.plugin.js, android/, ios/ — and no example/
npm publish --access public
```

---

## Legal

Not affiliated with or endorsed by any government authority. Reading, storing or
sharing someone else's identity document without their consent may breach data
protection law. For commercial or government use, contact the issuing authority
for authorisation.

---

## نبذة بالعربي

مكتبة لمسح **إجازة السياقة العراقية** بالكاميرا من تطبيقات Expo — الإصدار
**الاتحادي** وإصدار **إقليم كردستان**. تقرأ الوجه ثم الظهر، وتطلّع رقم الإجازة
والحقول المطبوعة و**كل فئة بتواريخها وحالتها (سارية / منتهية)**. كل المعالجة على
الجهاز ولا تُرفع أي صورة.

```ts
const data = await scanFull();
console.log(data.licenceNumber, data.categories);
```

**تنبيه مهم:** هذا OCR مو قراءة شريحة. إجازة السياقة ما فيها شريحة NFC، فما أكو
طريقة تشفيرية تثبت أصالتها. لا تستعملها كإثبات هوية أو بأنظمة التحقق (KYC).

الموثوقية: **رقم الإجازة** (من الـ MRZ) عالية، **الفئات وتواريخها** متوسطة،
و**حقول الوجه** تقريبية — راجعها مع المستخدم قبل ما تخزنها.

**ملاحظة:** محرّكا الـ OCR يشتغلان بالحروف اللاتينية فقط، فالاسم العربي
والعنوان (`nameArabic` و `address`) غالباً يطلعون فاضيين — استعمل `nameLatin`.

---

## License

MIT
