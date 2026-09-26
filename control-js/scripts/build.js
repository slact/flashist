import {build} from 'esbuild-wasm';
import {mkdir, readFile, writeFile} from 'node:fs/promises';

const {outputFiles: [{text}]} = await build({
  entryPoints: ['src/demo.js'],
  bundle: true,
  format: 'iife',
  minify: true,
  target: 'es2022',
  write: false
});
const source = await readFile('index.html', 'utf8');
const html = source.replace(
  '<script type="module" src="/src/demo.js"></script>',
  `<script>${text.replaceAll('</script>', '<\\/script>')}</script>`
);

await mkdir('dist', {recursive: true});
await writeFile('dist/index.html', html);
