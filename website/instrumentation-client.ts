import { initializeWebsiteAnalytics } from './lib/analytics'

const initializeAnalyticsAfterInteraction = () => initializeWebsiteAnalytics()

window.addEventListener('pointerdown', initializeAnalyticsAfterInteraction, {
  once: true,
  passive: true,
})
window.addEventListener('keydown', initializeAnalyticsAfterInteraction, {
  once: true,
})
window.setTimeout(initializeWebsiteAnalytics, 10_000)

let reliabilityModule: Promise<typeof import('./lib/reliability')> | undefined

const initializeReliabilityAfterInteraction = () => {
  reliabilityModule ??= import('./lib/reliability')
  void reliabilityModule.then(({ initializeWebsiteReliability }) =>
    initializeWebsiteReliability(),
  )
}

window.addEventListener('pointerdown', initializeReliabilityAfterInteraction, {
  once: true,
  passive: true,
})
window.addEventListener('keydown', initializeReliabilityAfterInteraction, {
  once: true,
})

type RouterTransitionStart = (typeof import('./lib/reliability'))['onRouterTransitionStart']

export function onRouterTransitionStart(
  ...args: Parameters<RouterTransitionStart>
): void {
  void reliabilityModule?.then(({ onRouterTransitionStart }) =>
    onRouterTransitionStart(...args),
  )
}
