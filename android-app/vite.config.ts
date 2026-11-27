import { defineConfig, transformWithEsbuild, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'node:path';
import fs from 'node:fs';

const harmonyEtsRoot = path.resolve(__dirname, '../harmony-app/entry/src/main/ets');
const harmonyMediaRoot = path.resolve(__dirname, '../harmony-app/entry/src/main/resources/base/media');

/**
 * Resolves and transpiles HarmonyOS `.ets` pure-TypeScript modules without
 * modifying any files inside `harmony-app/`.
 */
function harmonyEtsPlugin(): Plugin {
  return {
    name: 'harmony-ets-resolver',
    enforce: 'pre',
    resolveId(source, importer) {
      if (source === '@kit.ArkTS') {
        return path.resolve(__dirname, 'src/shims/arkts-util.ts');
      }
      if (source.startsWith('@harmony/')) {
        const rel = source.slice('@harmony/'.length);
        const base = path.resolve(harmonyEtsRoot, rel);
        if (fs.existsSync(base + '.ets')) return base + '.ets';
        if (fs.existsSync(base)) return base;
      }
      if (
        importer &&
        importer.startsWith(harmonyEtsRoot) &&
        (source.startsWith('./') || source.startsWith('../'))
      ) {
        const base = path.resolve(path.dirname(importer), source);
        if (fs.existsSync(base + '.ets')) return base + '.ets';
        if (fs.existsSync(base + '.ts')) return base + '.ts';
      }
      return null;
    },
    async transform(code, id) {
      if (id.endsWith('.ets')) {
        return transformWithEsbuild(code, id, { loader: 'ts', target: 'es2020' });
      }
      return null;
    },
  };
}

export default defineConfig({
  plugins: [harmonyEtsPlugin(), react()],
  resolve: {
    extensions: ['.mjs', '.js', '.mts', '.ts', '.ets', '.jsx', '.tsx', '.json'],
    alias: {
      '@': path.resolve(__dirname, 'src'),
      '@harmony': harmonyEtsRoot,
      '@harmony-media': harmonyMediaRoot,
      '@kit.ArkTS': path.resolve(__dirname, 'src/shims/arkts-util.ts'),
    },
  },
  worker: {
    format: 'es',
    plugins: () => [harmonyEtsPlugin()],
  },
  server: {
    fs: {
      allow: [path.resolve(__dirname, '..')],
    },
  },
  build: {
    target: 'es2020',
    outDir: 'dist',
    emptyOutDir: true,
  },
});
