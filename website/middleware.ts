import { NextResponse } from "next/server"
import type { NextRequest } from "next/server"

export function middleware(request: NextRequest) {
  const token = request.cookies.get("auth_token")?.value
  const pathname = request.nextUrl.pathname

  // Redirect to login if no token and trying to access protected routes
  if (!token && pathname === "/dashboard") {
    return NextResponse.redirect(new URL("/login", request.url))
  }

  // Redirect to dashboard if already logged in and trying to access auth pages
  if (token && (pathname === "/login" || pathname === "/register")) {
    return NextResponse.redirect(new URL("/dashboard", request.url))
  }

  return NextResponse.next()
}

export const config = {
  matcher: ["/dashboard", "/login", "/register"],
}
