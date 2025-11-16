'use client'

import { useEffect } from 'react'
import { Button } from '@/components/ui/button'
import { AlertCircle } from 'lucide-react'

export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string }
  reset: () => void
}) {
  useEffect(() => {
    console.error('[ERROR] Page error:', error)
  }, [error])

  return (
    <main className="flex items-center justify-center min-h-screen bg-background px-4">
      <div className="max-w-md w-full text-center space-y-6">
        <div className="flex justify-center">
          <AlertCircle className="w-16 h-16 text-destructive" />
        </div>

        <div>
          <h1 className="text-2xl font-bold text-foreground mb-2">Something went wrong</h1>
          <p className="text-muted-foreground">
            {error.message || 'An unexpected error occurred while processing your request.'}
          </p>
        </div>

        <div className="flex gap-3 justify-center">
          <Button variant="outline" onClick={() => (window.location.href = '/')}>
            Go Home
          </Button>
          <Button onClick={reset}>Try again</Button>
        </div>

        {error.digest && (
          <p className="text-xs text-muted-foreground/50 font-mono mt-4">
            Error ID: {error.digest}
          </p>
        )}
      </div>
    </main>
  )
}
