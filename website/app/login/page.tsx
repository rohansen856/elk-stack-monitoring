'use client'

import { useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { useAuthStore } from '@/lib/store/auth-store'
import { LoginForm } from '@/components/auth/login-form'

export default function LoginPage() {
  const router = useRouter()
  const { isAuthenticated } = useAuthStore()

  useEffect(() => {
    if (isAuthenticated) {
      router.push('/dashboard')
    }
  }, [isAuthenticated, router])

  return (
    <main className="flex items-center justify-center min-h-screen bg-background px-4">
      <LoginForm />
    </main>
  )
}
