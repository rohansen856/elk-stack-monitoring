import { create } from 'zustand'
import { persist } from 'zustand/middleware'

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
  setToken: (token: string, user: { id: string; email: string; username: string }) => void
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
          const response = await fetch('/api/auth/login', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ email, password }),
          })

          if (!response.ok) {
            const error = await response.json()
            throw new Error(error.detail || 'Login failed')
          }

          const data = await response.json()
          console.log('Login response data:', data)

          // Fetch user details to get the actual username
          const userResponse = await fetch('/api/auth/me', {
            headers: {
              'Authorization': `Bearer ${data.access_token}`
            }
          })

          let userData = { id: '1', email: email, username: email.split('@')[0] }
          if (userResponse.ok) {
            const userInfo = await userResponse.json()
            userData = {
              id: userInfo.id?.toString() || '1',
              email: userInfo.email || email,
              username: userInfo.username || email.split('@')[0]
            }
          }

          set({
            token: data.access_token,
            user: userData,
            isLoading: false,
          })
          console.log('Token set:', data.access_token)
        } catch (error) {
          set({
            error: error instanceof Error ? error.message : 'Login failed',
            isLoading: false,
          })
          throw error
        }
      },

      register: async (username: string, email: string, password: string) => {
        set({ isLoading: true, error: null })
        try {
          const response = await fetch('/api/auth/register', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username, email, password }),
          })

          if (!response.ok) {
            const error = await response.json()
            throw new Error(error.detail || 'Registration failed')
          }

          const data = await response.json()

          // Fetch user details to get the actual username
          const userResponse = await fetch('/api/auth/me', {
            headers: {
              'Authorization': `Bearer ${data.access_token}`
            }
          })

          let userData = { id: '1', email: email, username: username }
          if (userResponse.ok) {
            const userInfo = await userResponse.json()
            userData = {
              id: userInfo.id?.toString() || '1',
              email: userInfo.email || email,
              username: userInfo.username || username
            }
          }

          set({
            token: data.access_token,
            user: userData,
            isLoading: false,
          })
        } catch (error) {
          set({
            error: error instanceof Error ? error.message : 'Registration failed',
            isLoading: false,
          })
          throw error
        }
      },

      logout: () => {
        set({ token: null, user: null, error: null })
      },

      clearError: () => {
        set({ error: null })
      },

      setToken: (token: string, user: { id: string; email: string }) => {
        set({ token, user })
      },
    }),
    {
      name: 'auth-store',
      onRehydrateStorage: () => (state) => {
        if (state) {
          state.isHydrated = true
        }
      },
    }
  )
)
