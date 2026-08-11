import { NextRequest, NextResponse } from 'next/server'

import { getAuthHeader, unauthorized } from '@/lib/server-session'

const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:8000/api/v1'


export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const authHeader = getAuthHeader(request)
    if (!authHeader) return unauthorized()
    const body = await request.json()
    const { id } = await params

    const response = await fetch(`${BACKEND_URL}/todos/${id}`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        Authorization: authHeader,
      },
      body: JSON.stringify(body),
    })

    if (!response.ok) {
      return NextResponse.json(
        { detail: 'Failed to update todo' },
        { status: response.status }
      )
    }

    const data = await response.json()
    return NextResponse.json(data)
  } catch (error) {
    console.error('[TODOS] PUT error:', error)
    return NextResponse.json(
      { detail: 'Internal server error' },
      { status: 500 }
    )
  }
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const authHeader = getAuthHeader(request)
    if (!authHeader) return unauthorized()
    const { id } = await params

    const response = await fetch(`${BACKEND_URL}/todos/${id}`, {
      method: 'DELETE',
      headers: {
        Authorization: authHeader,
      },
    })

    if (!response.ok) {
      return NextResponse.json(
        { detail: 'Failed to delete todo' },
        { status: response.status }
      )
    }

    return NextResponse.json({ success: true })
  } catch (error) {
    console.error('[TODOS] DELETE error:', error)
    return NextResponse.json(
      { detail: 'Internal server error' },
      { status: 500 }
    )
  }
}
