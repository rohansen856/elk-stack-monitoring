import { NextRequest, NextResponse } from 'next/server'

import { backendFetch } from '@/lib/backend'
import { clearSession, getAuthHeader, unauthorized } from '@/lib/server-session'

export async function GET(request: NextRequest) {
  try {
    const authHeader = getAuthHeader(request)
    if (!authHeader) return unauthorized()

    const response = await backendFetch(request, '/users/me', {
      headers: { Authorization: authHeader },
    })

    if (!response.ok) {
      // A rejected token (expired, password changed, user deactivated, secret
      // rotated) must also be removed. The proxy only checks that the cookie
      // exists, so a stale cookie used to bounce the user between /login and
      // /dashboard forever.
      const status = response.status === 401 || response.status === 403 ? 401 : response.status
      const result = NextResponse.json({ detail: 'Unauthorized' }, { status })
      return status === 401 ? clearSession(result) : result
    }

    return NextResponse.json(await response.json())
  } catch (error) {
    console.error('[AUTH] ME error:', error)
    return NextResponse.json({ detail: 'Internal server error' }, { status: 500 })
  }
}
