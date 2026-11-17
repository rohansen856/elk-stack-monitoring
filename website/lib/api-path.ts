/**
 * Prefix a same-origin path with the app's basePath.
 *
 * Next.js applies basePath to <Link> and router navigation but not to
 * fetch(), so client code must add it itself. See next.config.mjs.
 */
export function apiPath(path: string): string {
  return `${process.env.NEXT_PUBLIC_BASE_PATH ?? ''}${path}`
}
