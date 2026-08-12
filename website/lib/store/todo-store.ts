import { create } from 'zustand'

import { Todo, todosApi } from '@/lib/api-client'

export type Priority = 'low' | 'medium' | 'high'
export type { Todo }

interface TodoState {
  todos: Todo[]
  isLoading: boolean
  error: string | null
  filter: 'all' | 'active' | 'completed'

  // No token parameter: the session cookie travels with every same-origin
  // request and is exchanged for a bearer token server-side (AUDIT SEC-006).
  fetchTodos: () => Promise<void>
  createTodo: (
    title: string,
    description?: string,
    priority?: Priority,
    due_date?: string
  ) => Promise<void>
  updateTodo: (
    id: number,
    data: Partial<Omit<Todo, 'id' | 'created_at' | 'updated_at'>>
  ) => Promise<void>
  deleteTodo: (id: number) => Promise<void>
  setFilter: (filter: 'all' | 'active' | 'completed') => void
  clearError: () => void
}

export const useTodoStore = create<TodoState>((set) => ({
  todos: [],
  isLoading: false,
  error: null,
  filter: 'all',

  fetchTodos: async () => {
    set({ isLoading: true, error: null })
    try {
      const data = await todosApi.getTodos()
      // Defensive: the API contract says an array, but an unexpected shape
      // would otherwise blow up later in .map(). apiCall is now typed, so this
      // is belt and braces rather than the only guard.
      set({ todos: Array.isArray(data) ? data : [], isLoading: false })
    } catch (error) {
      set({
        error: error instanceof Error ? error.message : 'Failed to fetch todos',
        isLoading: false,
      })
    }
  },

  createTodo: async (
    title: string,
    description?: string,
    priority: Priority = 'medium',
    due_date?: string
  ) => {
    set({ error: null })
    try {
      const newTodo = await todosApi.createTodo({ title, description, priority, due_date })
      set((state) => ({ todos: [newTodo, ...state.todos] }))
    } catch (error) {
      set({ error: error instanceof Error ? error.message : 'Failed to create todo' })
      throw error
    }
  },

  updateTodo: async (
    id: number,
    data: Partial<Omit<Todo, 'id' | 'created_at' | 'updated_at'>>
  ) => {
    set({ error: null })
    try {
      const updated = await todosApi.updateTodo(id, data)
      set((state) => ({
        todos: state.todos.map((todo) => (todo.id === id ? updated : todo)),
      }))
    } catch (error) {
      set({ error: error instanceof Error ? error.message : 'Failed to update todo' })
      throw error
    }
  },

  deleteTodo: async (id: number) => {
    set({ error: null })
    try {
      await todosApi.deleteTodo(id)
      set((state) => ({ todos: state.todos.filter((todo) => todo.id !== id) }))
    } catch (error) {
      set({ error: error instanceof Error ? error.message : 'Failed to delete todo' })
      throw error
    }
  },

  setFilter: (filter: 'all' | 'active' | 'completed') => set({ filter }),

  clearError: () => set({ error: null }),
}))
