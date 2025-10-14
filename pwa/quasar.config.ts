import { configure } from 'quasar/wrappers'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const __filename = fileURLToPath(import.meta.url)
const __dirname  = dirname(__filename)

export default configure(() => ({
  css: ['app.scss'],
  build: {
    vueRouterMode: 'history',
    alias: {
      '@': resolve(__dirname, 'src'),
    },
  },
  extras: ['material-icons'],
  boot: ['pinia'],
  framework: {
    plugins: ['Notify'],
    iconSet: 'material-icons',
  },
  pwa: {
    workboxMode: 'GenerateSW',
    injectPwaMetaTags: true,
    workboxOptions: {
      skipWaiting: true,
      clientsClaim: true,
      runtimeCaching: [
        {
          urlPattern: ({request}) => request.destination === 'document',
          handler: 'NetworkFirst',
          options: {cacheName: 'pages', networkTimeoutSeconds: 3}
        },
        {
          urlPattern: ({request}) => ['style', 'script', 'worker'].includes(request.destination),
          handler: 'StaleWhileRevalidate',
          options: {cacheName: 'assets'}
        },
        {
          urlPattern: ({request}) => request.destination === 'image',
          handler: 'StaleWhileRevalidate',
          options: {cacheName: 'images'}
        },
        {
          urlPattern: /\/api\//,
          handler: 'NetworkFirst',
          options: {cacheName: 'api', networkTimeoutSeconds: 5}
        }
      ]
    },
    manifest: {
      name: 'greenKasse — POS PWA POC',
      short_name: 'greenKasse',
      description: 'POS PWA POC',
      display: 'standalone',
      orientation: 'landscape',
      background_color: '#ffffff',
      theme_color: '#0b8457',
      icons: [
        {src: 'icons/icon-128x128.png', sizes: '128x128', type: 'image/png'},
        {src: 'icons/icon-192x192.png', sizes: '192x192', type: 'image/png'},
        {src: 'icons/icon-256x256.png', sizes: '256x256', type: 'image/png'},
        {src: 'icons/icon-384x384.png', sizes: '384x384', type: 'image/png'},
        {src: 'icons/icon-512x512.png', sizes: '512x512', type: 'image/png'}
      ]
    }
  }
}))
