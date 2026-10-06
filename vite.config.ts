/// <reference types="vitest/config" />
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { fileURLToPath, URL } from 'node:url'

const raiz = fileURLToPath(new URL('.', import.meta.url))

// O app vive em web/; o .env fica na raiz do repositório.
export default defineConfig({
  root: 'web',
  envDir: raiz,
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: { '@': fileURLToPath(new URL('./web/src', import.meta.url)) },
  },
  server: { port: 5173, strictPort: true },
  build: { outDir: '../dist', emptyOutDir: true },
  test: {
    root: raiz,
    environment: 'node',
    include: ['web/src/**/*.test.{ts,tsx}', 'n8n/**/*.test.mjs'],
    passWithNoTests: true,
  },
})
