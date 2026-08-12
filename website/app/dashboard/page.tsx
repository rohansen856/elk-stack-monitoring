"use client"

import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { useAuthStore } from "@/lib/store/auth-store"
import { useTodoStore, Priority } from "@/lib/store/todo-store"
import { Header } from "@/components/layout/header"
import { AddTodoForm } from "@/components/todos/add-todo-form"
import { TodoFilters } from "@/components/todos/todo-filters"
import { TodoList } from "@/components/todos/todo-list"
import { AlertCircle, Loader2 } from "lucide-react"

export default function DashboardPage() {
  const router = useRouter()
  const { user, isAuthenticated, isHydrated, loadSession } = useAuthStore()
  const {
    todos,
    isLoading,
    error,
    filter,
    fetchTodos,
    createTodo,
    updateTodo,
    deleteTodo,
    setFilter,
    clearError,
  } = useTodoStore()

  useEffect(() => {
    // Ask the server who we are; the session cookie is httpOnly, so the client
    // cannot inspect it directly.
    if (!isHydrated) {
      void loadSession()
      return
    }

    if (!isAuthenticated) {
      router.push("/login")
      return
    }

    void fetchTodos()
  }, [isAuthenticated, isHydrated, router, fetchTodos, loadSession])

  if (!isHydrated || !isAuthenticated) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <Loader2 className="w-8 h-8 animate-spin text-primary" />
      </div>
    )
  }

  const activeTodos = todos.filter((t) => !t.completed).length
  const completedTodos = todos.filter((t) => t.completed).length

  const handleCreateTodo = async (
    title: string,
    description?: string,
    priority?: Priority,
    due_date?: string
  ) => {
    await createTodo(title, description, priority, due_date)
  }

  const handleToggleTodo = async (id: number) => {
    const todo = todos.find((t) => t.id === id)
    if (todo) {
      await updateTodo(id, { completed: !todo.completed })
    }
  }

  const handleDeleteTodo = async (id: number) => {
    await deleteTodo(id)
  }

  return (
    <main className="min-h-screen bg-background">
      <Header />

      <div className="max-w-4xl mx-auto px-4 py-8">
        {error && (
          <div className="mb-6 flex items-center gap-2 p-4 bg-destructive/10 border border-destructive/30 rounded-lg">
            <AlertCircle className="w-5 h-5 text-destructive shrink-0" />
            <p className="text-sm text-destructive flex-1">{error}</p>
            <button
              onClick={clearError}
              className="text-destructive/70 hover:text-destructive text-sm font-medium"
            >
              Dismiss
            </button>
          </div>
        )}

        <div className="space-y-6">
          <div className="text-center mb-8">
            <h2 className="text-3xl font-bold text-foreground mb-2">
              Welcome, {user?.username}
            </h2>
            <p className="text-muted-foreground">
              Stay organized and productive
            </p>
          </div>

          {isLoading && !todos.length ? (
            <div className="flex flex-col items-center justify-center py-12">
              <Loader2 className="w-8 h-8 animate-spin text-primary mb-2" />
              <p className="text-muted-foreground">Loading your tasks...</p>
            </div>
          ) : (
            <>
              <AddTodoForm onSubmit={handleCreateTodo} isLoading={isLoading} />

              <TodoFilters
                activeFilter={filter}
                onFilterChange={setFilter}
                totalTodos={todos.length}
                activeTodos={activeTodos}
                completedTodos={completedTodos}
              />

              <TodoList
                todos={todos}
                filter={filter}
                onToggle={handleToggleTodo}
                onDelete={handleDeleteTodo}
                isLoading={isLoading}
              />
            </>
          )}
        </div>
      </div>
    </main>
  )
}
