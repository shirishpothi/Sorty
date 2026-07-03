export const SITE_BASE_PATH = process.env.NEXT_PUBLIC_BASE_PATH ?? ''

export function sitePath(path: string): string {
  if (!path || path.startsWith('http') || path.startsWith('#')) {
    return path
  }

  if (!path.startsWith('/')) {
    return `${SITE_BASE_PATH}/${path}`
  }

  return `${SITE_BASE_PATH}${path}`
}
