import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import path from 'node:path'

// https://vite.dev/config/
export default defineConfig({
  base: '/control-panel/',
  plugins: [react(), tailwindcss()],
  build: {
    outDir: '../Sources/SSSHTTP/Resources/WebUI',
    emptyOutDir: true,
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    proxy: {
      '/backend': 'http://127.0.0.1:7338',
      '/configuration': 'http://127.0.0.1:7338',
      '/generation': 'http://127.0.0.1:7338',
      '/healthz': 'http://127.0.0.1:7338',
      '/models': 'http://127.0.0.1:7338',
      '/network-audio': 'http://127.0.0.1:7338',
      '/overview': 'http://127.0.0.1:7338',
      '/playback': 'http://127.0.0.1:7338',
      '/readyz': 'http://127.0.0.1:7338',
      '/requests': 'http://127.0.0.1:7338',
      '/speech': 'http://127.0.0.1:7338',
      '/status': 'http://127.0.0.1:7338',
      '/text-profiles': 'http://127.0.0.1:7338',
      '/voices': 'http://127.0.0.1:7338',
    },
  },
})
