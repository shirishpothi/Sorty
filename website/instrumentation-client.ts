import { initializeWebsiteAnalytics } from './lib/analytics'
import {
  initializeWebsiteReliability,
  onRouterTransitionStart,
} from './lib/reliability'

initializeWebsiteAnalytics()
initializeWebsiteReliability()

export { onRouterTransitionStart }
