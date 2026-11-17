import { NextRequest, NextResponse } from 'next/server'

import { backendFetch, relayError } from '@/lib/backend'
import { setSessionCookie, setUserCookie } from '@/lib/server-session'

export async function POST(request: NextRequest) {
  try {
    const { email, password } = await request.json()

    if (!email || !password) {
      return NextResponse.json(
        { detail: 'Email and password are required' },
        { status: 400 }
      )
    }

    const response = await backendFetch(request, '/users/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ username: email, password }),
    })

    if (!response.ok) return relayError(response, 'Login failed')

    const data = await response.json()

    // Fetch the profile server-side so the client gets user details without
    // ever handling the token itself.
    const meResponse = await backendFetch(request, '/users/me', {
      headers: { Authorization: `Bearer ${data.access_token}` },
    })
    const user = meResponse.ok ? await meResponse.json() : null

    // The token is deliberately NOT included in the response body: it goes
    // into an httpOnly cookie that client JavaScript cannot read.
    const result = NextResponse.json({ success: true, user })
    setSessionCookie(result, data.access_token)
    if (user) {
      setUserCookie(result, { id: user.id, email: user.email, username: user.username })
    }
    return result
  } catch (error) {
    console.error('[AUTH] Login error:', error)
    return NextResponse.json({ detail: 'Internal server error' }, { status: 500 })
  }
}
