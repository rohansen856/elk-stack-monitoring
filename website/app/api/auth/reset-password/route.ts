import { NextRequest, NextResponse } from 'next/server'

import { backendFetch, relayError } from '@/lib/backend'

export async function POST(request: NextRequest) {
  try {
    const { email, otp, new_password } = await request.json()

    if (!email || !otp || !new_password) {
      return NextResponse.json(
        { detail: 'Email, OTP, and new password are required' },
        { status: 400 }
      )
    }

    const response = await backendFetch(request, '/users/reset-password', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, otp, new_password }),
    })

    if (!response.ok) return relayError(response, 'Failed to reset password')

    return NextResponse.json(await response.json())
  } catch (error) {
    console.error('[AUTH] Reset password error:', error)
    return NextResponse.json({ detail: 'Internal server error' }, { status: 500 })
  }
}
