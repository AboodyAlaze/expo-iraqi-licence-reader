#!/usr/bin/env node
/**
 * يشتغل تلقائياً بعد `npm install`:
 *   1) يبني الحزمة والـ plugin
 *   2) يربط الحزمة بنفسها حتى يلقاها Expo كـ plugin
 *
 * ملاحظة: noEmit لازم false بـ tsconfig.json — expo/tsconfig.base يخليه
 * true، وبدونها tsc ينجح بس ما ينبني build/ أبداً.
 */
const { spawnSyncWithAutoShell } = require('./util');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..', '..');

function run(cmd, args = []) {
  const result = spawnSyncWithAutoShell(cmd, args, { stdio: 'inherit', cwd: root });
  if (result.status !== 0) process.exit(result.status ?? 1);
}

fs.rmSync(path.join(root, 'build'), { recursive: true, force: true });
fs.rmSync(path.join(root, 'plugin', 'build'), { recursive: true, force: true });

console.log('Building package…');
run('tsc');

console.log('Building plugin…');
run('tsc', ['--project', 'plugin']);

require('./link-self');
