import { NextResponse } from "next/server"
import type { NextRequest } from "next/server"

/**
 * Build a redirect target that keeps the /frontend basePath. `new URL("/login",
 * request.url)` dropped it and produced `Location: /login`, which only worked
 * because nginx rewrote every relative Location header - a rewrite that also
 * double-prefixed Next's own correct redirects.
 */
function redirectTo(request: NextRequest, pathname: string) {
  const url = request.nextUrl.clone()
  url.pathname = pathname
  url.search = ""
  return url
}

// Next 16 renamed the `middleware` convention to `proxy` (middleware.ts is
// deprecated). Behaviour is unchanged: a cheap cookie-presence gate. The real
// check is server-side in /api/auth/me, which also clears a rejected cookie.
export function proxy(request: NextRequest) {
  const token = request.cookies.get("auth_token")?.value
  const pathname = request.nextUrl.pathname

  // Redirect to login if no token and trying to access protected routes
  if (!token && pathname === "/dashboard") {
    return NextResponse.redirect(redirectTo(request, "/login"))
  }

  // Redirect to dashboard if already logged in and trying to access auth pages
  if (token && (pathname === "/login" || pathname === "/register")) {
    return NextResponse.redirect(redirectTo(request, "/dashboard"))
  }

  return NextResponse.next()
}

export const config = {
  matcher: ["/dashboard", "/login", "/register"],
}
