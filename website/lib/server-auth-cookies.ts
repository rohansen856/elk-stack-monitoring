import { cookies } from "next/headers"

const TOKEN_COOKIE = "auth_token"
const USER_COOKIE = "user_data"
const COOKIE_MAX_AGE = 60 * 60 * 24 * 30 // 30 days in seconds

interface UserData {
  id: string
  email: string
  username: string
}

// Server-side cookie operations (use with cookies() from next/headers)
export const serverAuthCookies = {
  getToken: async (): Promise<string | null> => {
    const cookieStore = await cookies()
    return cookieStore.get(TOKEN_COOKIE)?.value || null
  },

  getUser: async (): Promise<UserData | null> => {
    const cookieStore = await cookies()
    const userData = cookieStore.get(USER_COOKIE)?.value
    if (!userData) return null

    try {
      return JSON.parse(userData)
    } catch {
      return null
    }
  },

  setAuth: async (token: string, user: UserData): Promise<void> => {
    const cookieStore = await cookies()

    cookieStore.set(TOKEN_COOKIE, token, {
      httpOnly: false, // Allow client-side access
      secure: process.env.NODE_ENV === "production",
      sameSite: "lax",
      maxAge: COOKIE_MAX_AGE,
      path: "/",
    })

    cookieStore.set(USER_COOKIE, JSON.stringify(user), {
      httpOnly: false,
      secure: process.env.NODE_ENV === "production",
      sameSite: "lax",
      maxAge: COOKIE_MAX_AGE,
      path: "/",
    })
  },

  clearAuth: async (): Promise<void> => {
    const cookieStore = await cookies()
    cookieStore.delete(TOKEN_COOKIE)
    cookieStore.delete(USER_COOKIE)
  },
}