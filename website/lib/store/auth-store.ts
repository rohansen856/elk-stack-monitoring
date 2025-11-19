import { create } from "zustand"
import { persist, createJSONStorage } from "zustand/middleware"
import { clientAuthCookies } from "../auth-cookies"

interface AuthState {
  token: string | null
  user: { id: string; email: string; username: string } | null
  isLoading: boolean
  error: string | null
  isHydrated: boolean
  login: (email: string, password: string) => Promise<void>
  register: (username: string, email: string, password: string) => Promise<void>
  logout: () => void
  clearError: () => void
  setToken: (
    token: string,
    user: { id: string; email: string; username: string }
  ) => void
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set) => ({
      token: null,
      user: null,
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
            const error = await response.json()
            throw new Error(error.detail || "Login failed")
          }

          const data = await response.json()

          // Fetch user details to get the actual username
          const userResponse = await fetch("/api/auth/me", {
            headers: {
              Authorization: `Bearer ${data.access_token}`,
            },
          })

          let userData = {
            id: "1",
            email: email,
            username: email.split("@")[0],
          }
          if (userResponse.ok) {
            const userInfo = await userResponse.json()
            userData = {
              id: userInfo.id?.toString() || "1",
              email: userInfo.email || email,
              username: userInfo.username || email.split("@")[0],
            }
          }

          // Store in cookies
          clientAuthCookies.setAuth(data.access_token, userData)

          set({
            token: data.access_token,
            user: userData,
            isLoading: false,
          })
        } catch (error) {
          set({
            error: error instanceof Error ? error.message : "Login failed",
            isLoading: false,
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
            const error = await response.json()
            throw new Error(error.detail || "Registration failed")
          }

          const data = await response.json()

          // Fetch user details to get the actual username
          const userResponse = await fetch("/api/auth/me", {
            headers: {
              Authorization: `Bearer ${data.access_token}`,
            },
          })

          let userData = { id: "1", email: email, username: username }
          if (userResponse.ok) {
            const userInfo = await userResponse.json()
            userData = {
              id: userInfo.id?.toString() || "1",
              email: userInfo.email || email,
              username: userInfo.username || username,
            }
          }

          // Store in cookies
          clientAuthCookies.setAuth(data.access_token, userData)

          set({
            token: data.access_token,
            user: userData,
            isLoading: false,
          })
        } catch (error) {
          set({
            error:
              error instanceof Error ? error.message : "Registration failed",
            isLoading: false,
          })
          throw error
        }
      },

      logout: () => {
        clientAuthCookies.clearAuth()
        set({ token: null, user: null, error: null })
      },

      clearError: () => {
        set({ error: null })
      },

      setToken: (token: string, user: { id: string; email: string; username: string }) => {
        clientAuthCookies.setAuth(token, user)
        set({ token, user })
      },
    }),
    {
      name: "auth-store",
      storage: createJSONStorage(() => ({
        getItem: (name: string) => {
          if (typeof window === "undefined") return null
          const token = clientAuthCookies.getToken()
          const user = clientAuthCookies.getUser()
          if (!token || !user) return null
          return JSON.stringify({ state: { token, user, isHydrated: true } })
        },
        setItem: (name: string, value: string) => {
          // Cookies are set directly in login/register/setToken methods
          // This is just for Zustand compatibility
        },
        removeItem: (name: string) => {
          clientAuthCookies.clearAuth()
        },
      })),
      onRehydrateStorage: () => (state) => {
        if (state) {
          state.isHydrated = true
        }
      },
    }
  )
)