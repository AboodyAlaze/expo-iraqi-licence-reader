#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..', '..');
for (const p of ['build', path.join('plugin', 'build')]) {
  fs.rmSync(path.join(root, p), { recursive: true, force: true });
}
console.log('cleaned build/ and plugin/build/');
