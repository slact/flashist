import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const file = fileURLToPath(new URL('../dist/index.html', import.meta.url));
const launchers = {
  darwin: ['open', [file]],
  linux: ['xdg-open', [file]],
  win32: ['cmd', ['/c', 'start', '', file]]
};
const launcher = launchers[process.platform];

if (!launcher) throw new Error(`Unsupported platform: ${process.platform}`);

const child = spawn(...launcher, {stdio: 'inherit'});
child.on('error', error => {
  console.error(`Could not open ${file}: ${error.message}`);
  process.exitCode = 1;
});
child.on('exit', code => {
  if (code) process.exitCode = code;
});
