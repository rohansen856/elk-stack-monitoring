import { NextRequest, NextResponse } from 'next/server'

import { backendFetch, relayError } from '@/lib/backend'
import { getAuthHeader, unauthorized } from '@/lib/server-session'

type Params = { params: Promise<{ id: string }> }

export async function PUT(request: NextRequest, { params }: Params) {
  try {
    const authHeader = getAuthHeader(request)
    if (!authHeader) return unauthorized()
    const body = await request.json()
    const { id } = await params

    const response = await backendFetch(request, `/todos/${encodeURIComponent(id)}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', Authorization: authHeader },
      body: JSON.stringify(body),
    })
    // The backend's own detail (e.g. "Todo not found", validation errors) is
    // relayed; it used to be replaced by a generic "Failed to update todo".
    if (!response.ok) return relayError(response, 'Failed to update todo')

    return NextResponse.json(await response.json())
  } catch (error) {
    console.error('[TODOS] PUT error:', error)
    return NextResponse.json({ detail: 'Internal server error' }, { status: 500 })
  }
}

export async function DELETE(request: NextRequest, { params }: Params) {
  try {
    const authHeader = getAuthHeader(request)
    if (!authHeader) return unauthorized()
    const { id } = await params

    const response = await backendFetch(request, `/todos/${encodeURIComponent(id)}`, {
      method: 'DELETE',
      headers: { Authorization: authHeader },
    })
    if (!response.ok) return relayError(response, 'Failed to delete todo')

    return NextResponse.json(await response.json().catch(() => ({ message: 'Todo deleted' })))
  } catch (error) {
    console.error('[TODOS] DELETE error:', error)
    return NextResponse.json({ detail: 'Internal server error' }, { status: 500 })
  }
}
