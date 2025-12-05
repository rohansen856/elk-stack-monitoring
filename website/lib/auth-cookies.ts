const TOKEN_COOKIE = "auth_token"
const USER_COOKIE = "user_data"
const COOKIE_MAX_AGE = 60 * 60 * 24 * 30 // 30 days in seconds

interface UserData {
  id: string
  email: string
  username: string
}

// Client-side cookie operations (for browser usage)
export const clientAuthCookies = {
  getToken: (): string | null => {
    if (typeof document === "undefined") return null
    const cookies = document.cookie.split(";")
    const tokenCookie = cookies.find(cookie =>
      cookie.trim().startsWith(`${TOKEN_COOKIE}=`)
    )
    return tokenCookie ? tokenCookie.split("=")[1] : null
  },

  getUser: (): UserData | null => {
    if (typeof document === "undefined") return null
    const cookies = document.cookie.split(";")
    const userCookie = cookies.find(cookie =>
      cookie.trim().startsWith(`${USER_COOKIE}=`)
    )

    if (!userCookie) return null

    try {
      const userData = userCookie.split("=")[1]
      return JSON.parse(decodeURIComponent(userData))
    } catch {
      return null
    }
  },

  setAuth: (token: string, user: UserData): void => {
    if (typeof document === "undefined") return

    const expires = new Date()
    expires.setTime(expires.getTime() + COOKIE_MAX_AGE * 1000)

    // Get the current hostname (works for both localhost and AWS EC2 IP)
    const hostname = typeof window !== "undefined" ? window.location.hostname : ""

    // Only set Secure flag if using HTTPS (not needed for HTTP on AWS EC2)
    const isSecure = typeof window !== "undefined" && window.location.protocol === "https:"

    // For AWS EC2 with IP address, don't set Domain (browser will default to current domain)
    // For production with real domain, set Domain to allow subdomain access
    const domainPart = hostname && !hostname.match(/^\d+\.\d+\.\d+\.\d+$/) && hostname !== "localhost"
      ? `; Domain=${hostname}`
      : ""

    const cookieOptions = `expires=${expires.toUTCString()}; path=/; SameSite=Lax${
      isSecure ? "; Secure" : ""
    }${domainPart}`

    document.cookie = `${TOKEN_COOKIE}=${token}; ${cookieOptions}`
    document.cookie = `${USER_COOKIE}=${encodeURIComponent(JSON.stringify(user))}; ${cookieOptions}`
  },

  clearAuth: (): void => {
    if (typeof document === "undefined") return

    const pastDate = new Date(0).toUTCString()

    // Match the same domain logic as setAuth for proper cookie deletion
    const hostname = typeof window !== "undefined" ? window.location.hostname : ""
    const domainPart = hostname && !hostname.match(/^\d+\.\d+\.\d+\.\d+$/) && hostname !== "localhost"
      ? `; Domain=${hostname}`
      : ""

    document.cookie = `${TOKEN_COOKIE}=; expires=${pastDate}; path=/${domainPart}`
    document.cookie = `${USER_COOKIE}=; expires=${pastDate}; path=/${domainPart}`
  },
}