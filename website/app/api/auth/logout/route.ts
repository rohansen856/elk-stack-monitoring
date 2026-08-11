import { NextResponse } from 'next/server'

import { clearSession } from '@/lib/server-session'

/**
 * Clears the session cookie. There was previously no logout at all: the only
 * way to end a session was to wait for the token to expire. See AUDIT SEC-012.
 */
export async function POST() {
  return clearSession(NextResponse.json({ success: true }))
}
