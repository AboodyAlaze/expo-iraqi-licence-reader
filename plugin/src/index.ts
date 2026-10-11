import {
  AndroidConfig,
  ConfigPlugin,
  createRunOncePlugin,
  withAndroidManifest,
  withInfoPlist,
} from 'expo/config-plugins';

type Options = {
  /** نص إذن الكاميرا اللي يظهر للمستخدم على iOS */
  cameraPermission?: string;
};

const DEFAULT_CAMERA_TEXT =
  'Used to scan your driving licence. Images are processed on the device and never uploaded.';

/** أندرويد: صلاحية الكاميرا (المكتبة نفسها تضيفها، هذا للتأكيد) */
const withCameraAndroid: ConfigPlugin = (config) =>
  withAndroidManifest(config, (cfg) => {
    AndroidConfig.Permissions.ensurePermission(cfg.modResults, 'android.permission.CAMERA');
    return cfg;
  });

/** iOS: وصف إذن الكاميرا — iOS يرفض الوصول بدونه */
const withCameraIos: ConfigPlugin<Options> = (config, opts = {}) =>
  withInfoPlist(config, (cfg) => {
    cfg.modResults.NSCameraUsageDescription =
      opts.cameraPermission ?? cfg.modResults.NSCameraUsageDescription ?? DEFAULT_CAMERA_TEXT;
    return cfg;
  });

const withIraqiLicenceReader: ConfigPlugin<Options> = (config, opts = {}) => {
  config = withCameraAndroid(config);
  config = withCameraIos(config, opts);
  return config;
};

export default createRunOncePlugin(
  withIraqiLicenceReader,
  'expo-iraqi-licence-reader',
  '0.1.0'
);
