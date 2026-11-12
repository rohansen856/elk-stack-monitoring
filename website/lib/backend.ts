import { NextRequest, NextResponse } from 'next/server'

/**
 * Server-side access to the FastAPI backend, shared by every route handler.
 * Import only from app/api route handlers: BACKEND_URL is an internal address.
 *
 * - One base URL. Two handlers used to fall back to `http://localhost:8000`
 *   without the `/api/v1` prefix the others used.
 * - Forwards the browser's address. Without it every login, registration and
 *   reset reached the backend from the frontend container's IP, so the
 *   backend's per-IP rate limits became one site-wide bucket (three
 *   forgot-password calls a minute for everybody) and security events blamed
 *   a single internal address.
 * - Normalises FastAPI error bodies. On a 422, `detail` is an array of
 *   objects, which the UI rendered as "[object Object]".
 */
export const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:8000/api/v1'

/** The client address as nginx reported it (nginx overwrites, never appends). */
function clientIp(request: NextRequest): string | null {
  const forwarded = request.headers.get('x-forwarded-for')
  if (forwarded) return forwarded.split(',')[0].trim()
  return request.headers.get('x-real-ip')
}

export function backendFetch(
  request: NextRequest,
  path: string,
  init: RequestInit = {}
): Promise<Response> {
  const headers = new Headers(init.headers)
  const ip = clientIp(request)
  if (ip) {
    headers.set('X-Forwarded-For', ip)
    headers.set('X-Real-IP', ip)
  }
  const userAgent = request.headers.get('user-agent')
  if (userAgent) headers.set('User-Agent', userAgent)

  return fetch(`${BACKEND_URL}${path}`, { ...init, headers, cache: 'no-store' })
}

interface ValidationIssue {
  msg?: string
  loc?: (string | number)[]
}

/** Turn any FastAPI `detail` shape into one human-readable sentence. */
export function errorDetail(body: unknown, fallback: string): string {
  const detail = (body as { detail?: unknown } | null)?.detail
  if (typeof detail === 'string' && detail) return detail
  if (Array.isArray(detail) && detail.length > 0) {
    return detail
      .map((issue: ValidationIssue) => {
        const field = issue.loc?.filter((p) => p !== 'body').join('.')
        const msg = (issue.msg ?? 'is invalid').replace(/^Value error, /, '')
        return field ? `${field}: ${msg}` : msg
      })
      .join('; ')
  }
  return fallback
}

/** Relay a failed backend response with its status and a readable detail. */
export async function relayError(response: Response, fallback: string): Promise<NextResponse> {
  const body = await response.json().catch(() => null)
  return NextResponse.json({ detail: errorDetail(body, fallback) }, { status: response.status })
}
