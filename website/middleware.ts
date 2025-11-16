import { NextResponse } from "next/server"
import type { NextRequest } from "next/server"

export function middleware(request: NextRequest) {
  console.log("Middleware called for:", request.nextUrl.pathname)
  return NextResponse.next()
}

export const config = {
  matcher: ["/dashboard", "/login", "/register"],
}
