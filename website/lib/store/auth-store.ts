import { create } from "zustand"

export interface AuthUser {
  id: number
  email: string
  username: string
}

/**
 * Client-side auth state.
 *
 * Deliberately holds NO token. The JWT lives in an httpOnly cookie that this
 * code cannot read; every request to /api/* is same-origin, so the browser
 * attaches the cookie automatically and the server-side route handler converts
 * it into an Authorization header.
 *
 * Previously the token was kept here and in a JS-readable cookie for 30 days,
 * so any XSS meant full account takeover. See AUDIT SEC-006.
 */
interface AuthState {
  user: AuthUser | null
  isAuthenticated: boolean
  isLoading: boolean
  error: string | null
  isHydrated: boolean
  login: (email: string, password: string) => Promise<void>
  register: (username: string, email: string, password: string) => Promise<void>
  logout: () => Promise<void>
  loadSession: () => Promise<void>
  clearError: () => void
}

export const useAuthStore = create<AuthState>()((set) => ({
  user: null,
  isAuthenticated: false,
  isLoading: false,
  error: null,
  isHydrated: false,

  login: async (email: string, password: string) => {
    set({ isLoading: true, error: null })
    try {
      const response = await fetch("/api/auth/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, password }),
      })

      if (!response.ok) {
        const error = await response.json().catch(() => ({}))
        throw new Error(error.detail || "Login failed")
      }

      const data = await response.json()
      set({
        user: data.user ?? null,
        isAuthenticated: true,
        isLoading: false,
        isHydrated: true,
      })
    } catch (error) {
      set({
        error: error instanceof Error ? error.message : "Login failed",
        isLoading: false,
        isAuthenticated: false,
      })
      throw error
    }
  },

  register: async (username: string, email: string, password: string) => {
    set({ isLoading: true, error: null })
    try {
      const response = await fetch("/api/auth/register", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username, email, password }),
      })

      if (!response.ok) {
        const error = await response.json().catch(() => ({}))
        throw new Error(error.detail || "Registration failed")
      }

      const data = await response.json()
      set({
        user: data.user ?? null,
        isAuthenticated: true,
        isLoading: false,
        isHydrated: true,
      })
    } catch (error) {
      set({
        error: error instanceof Error ? error.message : "Registration failed",
        isLoading: false,
        isAuthenticated: false,
      })
      throw error
    }
  },

  logout: async () => {
    try {
      // Server-side so the httpOnly cookie is actually cleared; client code
      // cannot delete it.
      await fetch("/api/auth/logout", { method: "POST" })
    } finally {
      set({ user: null, isAuthenticated: false, isHydrated: true })
    }
  },

  /** Restore session state on load by asking the server who we are. */
  loadSession: async () => {
    try {
      const response = await fetch("/api/auth/me")
      if (response.ok) {
        const user = await response.json()
        set({ user, isAuthenticated: true, isHydrated: true })
      } else {
        set({ user: null, isAuthenticated: false, isHydrated: true })
      }
    } catch {
      set({ user: null, isAuthenticated: false, isHydrated: true })
    }
  },

  clearError: () => set({ error: null }),
}))
