import { NextRequest, NextResponse } from 'next/server'

import { backendFetch, relayError } from '@/lib/backend'
import { setSessionCookie, setUserCookie } from '@/lib/server-session'

export async function POST(request: NextRequest) {
  try {
    const { username, email, password } = await request.json()

    if (!username || !email || !password) {
      return NextResponse.json(
        { detail: 'Username, email and password are required' },
        { status: 400 }
      )
    }

    const registerResponse = await backendFetch(request, '/users/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, username, password }),
    })

    if (!registerResponse.ok) return relayError(registerResponse, 'Registration failed')

    // Then automatically log them in
    const loginResponse = await backendFetch(request, '/users/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ username: email, password }),
    })

    if (!loginResponse.ok) {
      return NextResponse.json(
        { detail: 'Registration successful but auto-login failed. Please try logging in manually.' },
        { status: 502 }
      )
    }

    const loginData = await loginResponse.json()

    const meResponse = await backendFetch(request, '/users/me', {
      headers: { Authorization: `Bearer ${loginData.access_token}` },
    })
    // No invented fallback profile (it used to fabricate `id: 0`): without a
    // real profile the client re-fetches it via /api/auth/me.
    const user = meResponse.ok ? await meResponse.json() : null

    // Token goes into an httpOnly cookie, not the response body.
    const result = NextResponse.json({ success: true, user })
    setSessionCookie(result, loginData.access_token)
    if (user) {
      setUserCookie(result, { id: user.id, email: user.email, username: user.username })
    }
    return result
  } catch (error) {
    console.error('[AUTH] Register error:', error)
    return NextResponse.json({ detail: 'Internal server error' }, { status: 500 })
  }
}
