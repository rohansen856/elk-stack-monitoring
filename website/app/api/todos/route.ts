import { NextRequest, NextResponse } from 'next/server'

import { getAuthHeader, unauthorized } from '@/lib/server-session'

const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:8000/api/v1'


export async function GET(request: NextRequest) {
  try {
    const authHeader = getAuthHeader(request)
    if (!authHeader) return unauthorized()

    const response = await fetch(`${BACKEND_URL}/todos/`, {
      method: 'GET',
      headers: {
        Authorization: authHeader,
      },
    })

    if (!response.ok) {
      return NextResponse.json(
        { detail: 'Failed to fetch todos' },
        { status: response.status }
      )
    }

    const data = await response.json()
    return NextResponse.json(data)
  } catch (error) {
    console.error('[TODOS] GET error:', error)
    return NextResponse.json(
      { detail: 'Internal server error' },
      { status: 500 }
    )
  }
}

export async function POST(request: NextRequest) {
  try {
    const authHeader = getAuthHeader(request)
    if (!authHeader) return unauthorized()
    const body = await request.json()

    const response = await fetch(`${BACKEND_URL}/todos/`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: authHeader,
      },
      body: JSON.stringify(body),
    })

    if (!response.ok) {
      const errorData = await response.json()
      return NextResponse.json(
        errorData,
        { status: response.status }
      )
    }

    const data = await response.json()
    return NextResponse.json(data, { status: 201 })
  } catch (error) {
    console.error('[TODOS] POST error:', error)
    return NextResponse.json(
      { detail: 'Internal server error' },
      { status: 500 }
    )
  }
}
