import { NextRequest, NextResponse } from 'next/server'

import { backendFetch, relayError } from '@/lib/backend'
import { getAuthHeader, unauthorized } from '@/lib/server-session'

/**
 * Todo statistics. The client called /api/todos/stats, which had no handler:
 * it fell through to [id]/route.ts with id="stats" and returned 405.
 */
export async function GET(request: NextRequest) {
  try {
    const authHeader = getAuthHeader(request)
    if (!authHeader) return unauthorized()

    const response = await backendFetch(request, '/todos/stats/summary', {
      headers: { Authorization: authHeader },
    })
    if (!response.ok) return relayError(response, 'Failed to fetch statistics')

    return NextResponse.json(await response.json())
  } catch (error) {
    console.error('[TODOS] STATS error:', error)
    return NextResponse.json({ detail: 'Internal server error' }, { status: 500 })
  }
}
