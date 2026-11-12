import { NextRequest, NextResponse } from 'next/server'

import { backendFetch, relayError } from '@/lib/backend'
import { getAuthHeader, unauthorized } from '@/lib/server-session'

export async function GET(request: NextRequest) {
  try {
    const authHeader = getAuthHeader(request)
    if (!authHeader) return unauthorized()

    const response = await backendFetch(request, '/todos/', {
      headers: { Authorization: authHeader },
    })
    if (!response.ok) return relayError(response, 'Failed to fetch todos')

    return NextResponse.json(await response.json())
  } catch (error) {
    console.error('[TODOS] GET error:', error)
    return NextResponse.json({ detail: 'Internal server error' }, { status: 500 })
  }
}

export async function POST(request: NextRequest) {
  try {
    const authHeader = getAuthHeader(request)
    if (!authHeader) return unauthorized()
    const body = await request.json()

    const response = await backendFetch(request, '/todos/', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: authHeader },
      body: JSON.stringify(body),
    })
    if (!response.ok) return relayError(response, 'Failed to create todo')

    return NextResponse.json(await response.json(), { status: 201 })
  } catch (error) {
    console.error('[TODOS] POST error:', error)
    return NextResponse.json({ detail: 'Internal server error' }, { status: 500 })
  }
}
