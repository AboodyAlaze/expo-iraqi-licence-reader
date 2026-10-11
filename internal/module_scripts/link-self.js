#!/usr/bin/env node
/**
 * يعمل رابط رمزي: node_modules/<اسم الحزمة> → جذر المشروع.
 *
 * ليش: المثال يستورد الحزمة بالاسم، و Expo يدوّر على الـ config plugin
 * بـ node_modules. بدون الرابط يطلع "Plugin not found" — حتى لو كل شي ثاني سليم.
 * (npm workspaces يربط المجلدات الفرعية بس، وما يربط الجذر بنفسه.)
 *
 * يشتغل من `prepare` فقط، يعني بالتطوير المحلي — مو عند مستخدم
 * ثبّت الحزمة من npm.
 */
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..', '..');
const pkg = require(path.join(root, 'package.json'));

// بس إذا هذا مستودع التطوير (فيه example)
if (!fs.existsSync(path.join(root, 'example'))) process.exit(0);

const target = path.join(root, 'node_modules', pkg.name);

try {
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.rmSync(target, { recursive: true, force: true });
  fs.symlinkSync(root, target, process.platform === 'win32' ? 'junction' : 'dir');
  console.log(`linked node_modules/${pkg.name} -> ${root}`);
} catch (e) {
  // ما نكسر التثبيت بسببه
  console.warn(`warning: could not link ${pkg.name}: ${e.message}`);
}
