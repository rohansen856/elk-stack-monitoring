import { NextRequest, NextResponse } from 'next/server'

import { setSessionCookie, setUserCookie } from '@/lib/server-session'

const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:8000/api/v1'

export async function POST(request: NextRequest) {
  try {
    const { username, email, password } = await request.json()

    if (!username || !email || !password) {
      return NextResponse.json(
        { detail: 'Username, email and password are required' },
        { status: 400 }
      )
    }

    // First register the user
    const registerResponse = await fetch(`${BACKEND_URL}/users/register`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ email, username, password }),
    })

    if (!registerResponse.ok) {
      const errorData = await registerResponse.json()
      return NextResponse.json(
        errorData,
        { status: registerResponse.status }
      )
    }

    // Then automatically log them in
    const loginResponse = await fetch(`${BACKEND_URL}/users/login`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        username: email,
        password: password,
      }),
    })

    if (!loginResponse.ok) {
      return NextResponse.json(
        { detail: 'Registration successful but auto-login failed. Please try logging in manually.' },
        { status: 500 }
      )
    }

    const loginData = await loginResponse.json()

    // Resolve the real profile rather than inventing an id.
    const meResponse = await fetch(`${BACKEND_URL}/users/me`, {
      headers: { Authorization: `Bearer ${loginData.access_token}` },
    })
    const user = meResponse.ok ? await meResponse.json() : { id: 0, email, username }

    // Token goes into an httpOnly cookie, not the response body.
    const result = NextResponse.json({ success: true, user })
    setSessionCookie(result, loginData.access_token)
    setUserCookie(result, { id: user.id, email: user.email, username: user.username })
    return result
  } catch (error) {
    console.error('[AUTH] Register error:', error)
    return NextResponse.json(
      { detail: 'Internal server error' },
      { status: 500 }
    )
  }
}
