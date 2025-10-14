
/* src-pwa/register-service-worker.js */
import { register } from 'register-service-worker'
if (process.env.PROD) {
  register(process.env.SERVICE_WORKER_FILE, {
    ready: () => console.log('PWA ready'),
    registered: () => console.log('SW registered'),
    cached: () => console.log('Assets cached'),
    updatefound: () => console.log('Update found'),
    updated: () => console.log('New content available'),
    offline: () => console.log('Offline mode'),
    error: (e) => console.error('SW error', e)
  })
}
