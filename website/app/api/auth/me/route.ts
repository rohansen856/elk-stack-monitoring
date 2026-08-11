import { NextRequest, NextResponse } from 'next/server'

import { getAuthHeader, unauthorized } from '@/lib/server-session'

const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:8000/api/v1'

export async function GET(request: NextRequest) {
  try {
    const authHeader = getAuthHeader(request)
    if (!authHeader) return unauthorized()

    const response = await fetch(`${BACKEND_URL}/users/me`, {
      method: 'GET',
      headers: {
        Authorization: authHeader,
      },
    })

    if (!response.ok) {
      return NextResponse.json(
        { detail: 'Unauthorized' },
        { status: 401 }
      )
    }

    const data = await response.json()
    return NextResponse.json(data)
  } catch (error) {
    console.error('[AUTH] ME error:', error)
    return NextResponse.json(
      { detail: 'Internal server error' },
      { status: 500 }
    )
  }
}
