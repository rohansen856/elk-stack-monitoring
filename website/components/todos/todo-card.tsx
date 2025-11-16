"use client"

import { useState } from "react"
import { Todo } from "@/lib/store/todo-store"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Trash2, Loader2, Calendar, Check } from "lucide-react"

interface TodoCardProps {
  todo: Todo
  onToggle: () => Promise<void>
  onDelete: () => Promise<void>
  isLoading?: boolean
}

export function TodoCard({
  todo,
  onToggle,
  onDelete,
  isLoading = false,
}: TodoCardProps) {
  const [isDeleting, setIsDeleting] = useState(false)

  const handleDelete = async () => {
    setIsDeleting(true)
    try {
      await onDelete()
    } finally {
      setIsDeleting(false)
    }
  }

  const getPriorityColor = (priority: string) => {
    switch (priority) {
      case "high":
        return "destructive"
      case "medium":
        return "default"
      case "low":
        return "secondary"
      default:
        return "default"
    }
  }

  const getPriorityIcon = (priority: string) => {
    switch (priority) {
      case "high":
        return "🔴"
      case "medium":
        return "🟡"
      case "low":
        return "🔵"
      default:
        return "🟡"
    }
  }

  const formatDueDate = (dateString: string) => {
    const date = new Date(dateString)
    const now = new Date()
    const diffTime = date.getTime() - now.getTime()
    const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24))

    if (diffDays === 0) return "Today"
    if (diffDays === 1) return "Tomorrow"
    if (diffDays === -1) return "Yesterday"
    if (diffDays < 0) return `${Math.abs(diffDays)} days ago`
    return `in ${diffDays} days`
  }

  const isDueSoon = (dateString: string) => {
    const date = new Date(dateString)
    const now = new Date()
    const diffTime = date.getTime() - now.getTime()
    const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24))
    return diffDays <= 1 && diffDays >= 0
  }

  const isOverdue = (dateString: string) => {
    const date = new Date(dateString)
    const now = new Date()
    return date < now
  }

  return (
    <Card className="p-4 flex items-start gap-4 hover:bg-card/80 transition-colors flex-row border-l-primary">
      <div className="flex-1 min-w-0">
        <h3
          className={`font-semibold text-base transition-all ${
            todo.completed
              ? "line-through text-muted-foreground"
              : "text-foreground"
          }`}
        >
          {todo.title}
        </h3>
        {todo.description && (
          <p
            className={`text-sm mt-1 ${
              todo.completed
                ? "line-through text-muted-foreground/60"
                : "text-muted-foreground"
            }`}
          >
            {todo.description}
          </p>
        )}

        <div className="flex items-center gap-2 mt-3 flex-wrap">
          <Badge variant={getPriorityColor(todo.priority)} className="text-xs">
            {getPriorityIcon(todo.priority)} {todo.priority}
          </Badge>

          {todo.due_date && (
            <Badge
              variant={
                isOverdue(todo.due_date)
                  ? "destructive"
                  : isDueSoon(todo.due_date)
                  ? "default"
                  : "outline"
              }
              className="text-xs"
            >
              <Calendar className="w-3 h-3 mr-1" />
              {formatDueDate(todo.due_date)}
            </Badge>
          )}
        </div>

        <p className="text-xs text-muted-foreground/50 mt-2">
          Created {new Date(todo.created_at).toLocaleDateString()}
        </p>
      </div>

      <div className="flex flex-col gap-1">
        <Button
          variant="ghost"
          size="sm"
          onClick={handleDelete}
          disabled={isDeleting}
          className="text-destructive bg-destructive/20 cursor-pointer hover:text-destructive hover:bg-destructive/10"
        >
          {isDeleting ? (
            <Loader2 className="w-4 h-4 animate-spin" />
          ) : (
            <Trash2 className="w-4 h-4" />
          )}
        </Button>
        <Button
          variant="ghost"
          size="sm"
          onClick={onToggle}
          disabled={isLoading}
          className={`cursor-pointer transition-colors 
          ${
            todo.completed
              ? "text-green-500 bg-green-500/20 hover:bg-green-500/30"
              : "text-primary bg-secondary hover:bg-secondary/70 hover:text-primary/50"
          }`}
        >
          {isLoading ? (
            <Loader2 className="w-4 h-4 animate-spin" />
          ) : (
            <Check className="w-4 h-4" />
          )}
        </Button>
      </div>
    </Card>
  )
}
