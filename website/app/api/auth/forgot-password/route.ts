import { NextRequest, NextResponse } from 'next/server'

import { backendFetch, relayError } from '@/lib/backend'

export async function POST(request: NextRequest) {
  try {
    const { email } = await request.json()

    if (!email) {
      return NextResponse.json({ detail: 'Email is required' }, { status: 400 })
    }

    const response = await backendFetch(request, '/users/forgot-password', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email }),
    })

    if (!response.ok) return relayError(response, 'Failed to send reset email')

    return NextResponse.json(await response.json())
  } catch (error) {
    console.error('[AUTH] Forgot password error:', error)
    return NextResponse.json({ detail: 'Internal server error' }, { status: 500 })
  }
}
