import { transformSync } from 'esbuild';

// Keep release builds and browser fixtures on the same minification settings.
export function minifyFrontend(source) {
  return transformSync(source, {
    loader: 'js',
    minify: true,
    format: 'esm',
    target: 'es2022',
  }).code;
}
