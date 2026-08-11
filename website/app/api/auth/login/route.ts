import { NextRequest, NextResponse } from 'next/server'

import { setSessionCookie, setUserCookie } from '@/lib/server-session'

const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:8000/api/v1'

export async function POST(request: NextRequest) {
  try {
    const { email, password } = await request.json()

    if (!email || !password) {
      return NextResponse.json(
        { detail: 'Email and password are required' },
        { status: 400 }
      )
    }

    const response = await fetch(`${BACKEND_URL}/users/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ username: email, password }),
    })

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({ detail: 'Login failed' }))
      return NextResponse.json(errorData, { status: response.status })
    }

    const data = await response.json()

    // Fetch the profile server-side so the client gets user details without
    // ever handling the token itself.
    const meResponse = await fetch(`${BACKEND_URL}/users/me`, {
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
