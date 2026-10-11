import { NativeModule, requireNativeModule } from 'expo';

/**
 * الوحدة الأصلية. تفتح الكاميرا وترجع النتيجة كـ JSON نصي،
 * وطبقة TypeScript تحلّله وتضيف الحقول المشتقة.
 */
declare class ExpoIraqiLicenceReaderModule extends NativeModule {
  hasCameraPermission(): boolean;
  scanFront(): Promise<string>;
  scanBack(): Promise<string>;
}

export default requireNativeModule<ExpoIraqiLicenceReaderModule>('ExpoIraqiLicenceReader');
