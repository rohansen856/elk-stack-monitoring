'use client'

import { useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { useAuthStore } from '@/lib/store/auth-store'
import { RegisterForm } from '@/components/auth/register-form'

export default function RegisterPage() {
  const router = useRouter()
  const { token } = useAuthStore()

  useEffect(() => {
    if (token) {
      router.push('/dashboard')
    }
  }, [token, router])

  return (
    <main className="flex items-center justify-center min-h-screen bg-background px-4">
      <RegisterForm />
    </main>
  )
}
