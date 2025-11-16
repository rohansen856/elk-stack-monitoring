'use client'

import { useMemo } from 'react'
import { Todo } from '@/lib/store/todo-store'
import { TodoCard } from './todo-card'
import { Card } from '@/components/ui/card'

interface TodoListProps {
  todos: Todo[]
  filter: 'all' | 'active' | 'completed'
  isLoading?: boolean
  onToggle: (id: string) => Promise<void>
  onDelete: (id: string) => Promise<void>
}

export function TodoList({
  todos,
  filter,
  isLoading = false,
  onToggle,
  onDelete,
}: TodoListProps) {
  const filteredTodos = useMemo(() => {
    switch (filter) {
      case 'active':
        return todos.filter((todo) => !todo.completed)
      case 'completed':
        return todos.filter((todo) => todo.completed)
      case 'all':
      default:
        return todos
    }
  }, [todos, filter])

  if (filteredTodos.length === 0) {
    return (
      <Card className="p-12 text-center">
        <p className="text-muted-foreground">
          {filter === 'completed' && 'No completed tasks yet'}
          {filter === 'active' && 'No active tasks'}
          {filter === 'all' && 'No tasks yet. Create one to get started!'}
        </p>
      </Card>
    )
  }

  return (
    <div className="space-y-2">
      {filteredTodos.map((todo) => (
        <TodoCard
          key={todo.id}
          todo={todo}
          onToggle={() => onToggle(todo.id)}
          onDelete={() => onDelete(todo.id)}
          isLoading={isLoading}
        />
      ))}
    </div>
  )
}
