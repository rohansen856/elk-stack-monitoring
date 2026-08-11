import { NextRequest, NextResponse } from 'next/server'

/**
 * Server-side session handling.
 *
 * The JWT lives in an httpOnly cookie that JavaScript cannot read. Route
 * handlers read it server-side and attach the Authorization header when
 * calling the backend, so the token never reaches the browser at all.
 *
 * Previously the token was written with `httpOnly: false` ("Allow client-side
 * access") and kept for 30 days, so any XSS yielded full account takeover.
 * See AUDIT SEC-006.
 */
export const AUTH_COOKIE = 'auth_token'
export const USER_COOKIE = 'user_data'

/** Matches the backend's ACCESS_TOKEN_EXPIRE_MINUTES (30 minutes). */
export const SESSION_MAX_AGE_SECONDS = 30 * 60

const isProduction = process.env.NODE_ENV === 'production'

export function setSessionCookie(response: NextResponse, token: string): NextResponse {
  response.cookies.set(AUTH_COOKIE, token, {
    httpOnly: true,
    secure: isProduction,
    sameSite: 'lax',
    path: '/',
    maxAge: SESSION_MAX_AGE_SECONDS,
  })
  return response
}

/**
 * Non-sensitive profile data for the UI. Readable by client code by design -
 * it holds no credential.
 */
export function setUserCookie(
  response: NextResponse,
  user: { id: number | string; email: string; username: string }
): NextResponse {
  response.cookies.set(USER_COOKIE, JSON.stringify(user), {
    httpOnly: false,
    secure: isProduction,
    sameSite: 'lax',
    path: '/',
    maxAge: SESSION_MAX_AGE_SECONDS,
  })
  return response
}

export function clearSession(response: NextResponse): NextResponse {
  response.cookies.delete(AUTH_COOKIE)
  response.cookies.delete(USER_COOKIE)
  return response
}

/** The raw token, server-side only. */
export function getSessionToken(request: NextRequest): string | undefined {
  return request.cookies.get(AUTH_COOKIE)?.value
}

/**
 * Authorization header built from the session cookie.
 * Returns null when there is no session, so callers answer 401 rather than
 * forwarding an unauthenticated request to the backend.
 */
export function getAuthHeader(request: NextRequest): string | null {
  const token = getSessionToken(request)
  return token ? `Bearer ${token}` : null
}

export function unauthorized(): NextResponse {
  return NextResponse.json({ detail: 'Not authenticated' }, { status: 401 })
}
