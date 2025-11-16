'use client'

import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'
import { Card } from '@/components/ui/card'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Label } from '@/components/ui/label'
import { Plus, Loader2 } from 'lucide-react'
import { Priority } from '@/lib/store/todo-store'

interface AddTodoFormProps {
  onSubmit: (title: string, description?: string, priority?: Priority, due_date?: string) => Promise<void>
  isLoading?: boolean
}

export function AddTodoForm({ onSubmit, isLoading = false }: AddTodoFormProps) {
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [priority, setPriority] = useState<Priority>('medium')
  const [dueDate, setDueDate] = useState('')
  const [isExpanded, setIsExpanded] = useState(false)
  const [isSubmitting, setIsSubmitting] = useState(false)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!title.trim()) return

    setIsSubmitting(true)
    try {
      // Convert date to ISO format if provided
      const due_date = dueDate ? new Date(dueDate + 'T23:59:59Z').toISOString() : undefined
      await onSubmit(title, description || undefined, priority, due_date)
      setTitle('')
      setDescription('')
      setPriority('medium')
      setDueDate('')
      setIsExpanded(false)
    } finally {
      setIsSubmitting(false)
    }
  }

  return (
    <Card className="p-4 sticky top-0 z-10">
      <form onSubmit={handleSubmit} className="space-y-3">
        <div className="flex items-center gap-2">
          <Input
            type="text"
            placeholder="Add a new task..."
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            disabled={isSubmitting || isLoading}
            onFocus={() => setIsExpanded(true)}
            className="bg-input"
          />
          <Button
            type="submit"
            disabled={!title.trim() || isSubmitting || isLoading}
            size="sm"
          >
            {isSubmitting ? (
              <Loader2 className="w-4 h-4 animate-spin" />
            ) : (
              <Plus className="w-4 h-4" />
            )}
          </Button>
        </div>

        {isExpanded && (
          <>
            <Textarea
              placeholder="Add a description (optional)..."
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              disabled={isSubmitting || isLoading}
              className="min-h-24 bg-input"
            />

            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-2">
                <Label htmlFor="priority" className="text-sm font-medium">
                  Priority
                </Label>
                <Select value={priority} onValueChange={(value: Priority) => setPriority(value)}>
                  <SelectTrigger id="priority" disabled={isSubmitting || isLoading}>
                    <SelectValue placeholder="Select priority" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="low">🔵 Low</SelectItem>
                    <SelectItem value="medium">🟡 Medium</SelectItem>
                    <SelectItem value="high">🔴 High</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              <div className="space-y-2">
                <Label htmlFor="due-date" className="text-sm font-medium">
                  Due Date
                </Label>
                <Input
                  id="due-date"
                  type="date"
                  value={dueDate}
                  onChange={(e) => setDueDate(e.target.value)}
                  disabled={isSubmitting || isLoading}
                  className="bg-input"
                />
              </div>
            </div>

            <div className="flex gap-2 justify-end">
              <Button
                type="button"
                variant="outline"
                onClick={() => {
                  setIsExpanded(false)
                  setDescription('')
                  setPriority('medium')
                  setDueDate('')
                }}
                disabled={isSubmitting}
              >
                Cancel
              </Button>
              <Button
                type="submit"
                disabled={!title.trim() || isSubmitting || isLoading}
              >
                {isSubmitting ? (
                  <>
                    <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                    Adding...
                  </>
                ) : (
                  'Add Task'
                )}
              </Button>
            </div>
          </>
        )}
      </form>
    </Card>
  )
}
