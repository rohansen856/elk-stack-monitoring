import { create } from 'zustand'
import { todosApi } from '@/lib/api-client'

export type Priority = 'low' | 'medium' | 'high'

export interface Todo {
  id: string
  title: string
  description?: string
  completed: boolean
  priority: Priority
  due_date?: string
  created_at: string
  updated_at: string
}

interface TodoState {
  todos: Todo[]
  isLoading: boolean
  error: string | null
  filter: 'all' | 'active' | 'completed'

  fetchTodos: (token: string) => Promise<void>
  createTodo: (token: string, title: string, description?: string, priority?: Priority, due_date?: string) => Promise<void>
  updateTodo: (
    token: string,
    id: string,
    data: Partial<Omit<Todo, 'id' | 'created_at' | 'updated_at'>>
  ) => Promise<void>
  deleteTodo: (token: string, id: string) => Promise<void>
  setFilter: (filter: 'all' | 'active' | 'completed') => void
  clearError: () => void
}

export const useTodoStore = create<TodoState>((set) => ({
  todos: [],
  isLoading: false,
  error: null,
  filter: 'all',

  fetchTodos: async (token: string) => {
    set({ isLoading: true, error: null })
    try {
      const data = await todosApi.getTodos(token)
      set({ todos: data, isLoading: false })
    } catch (error) {
      set({
        error: error instanceof Error ? error.message : 'Failed to fetch todos',
        isLoading: false,
      })
    }
  },

  createTodo: async (token: string, title: string, description?: string, priority: Priority = 'medium', due_date?: string) => {
    set({ error: null })
    try {
      const newTodo = await todosApi.createTodo(token, { title, description, priority, due_date })
      set((state) => ({
        todos: [newTodo, ...state.todos],
      }))
    } catch (error) {
      set({
        error: error instanceof Error ? error.message : 'Failed to create todo',
      })
      throw error
    }
  },

  updateTodo: async (token: string, id: string, data: Partial<Omit<Todo, 'id' | 'created_at' | 'updated_at'>>) => {
    set({ error: null })
    try {
      const updated = await todosApi.updateTodo(token, id, data)
      set((state) => ({
        todos: state.todos.map((todo) => (todo.id === id ? updated : todo)),
      }))
    } catch (error) {
      set({
        error: error instanceof Error ? error.message : 'Failed to update todo',
      })
      throw error
    }
  },

  deleteTodo: async (token: string, id: string) => {
    set({ error: null })
    try {
      await todosApi.deleteTodo(token, id)
      set((state) => ({
        todos: state.todos.filter((todo) => todo.id !== id),
      }))
    } catch (error) {
      set({
        error: error instanceof Error ? error.message : 'Failed to delete todo',
      })
      throw error
    }
  },

  setFilter: (filter: 'all' | 'active' | 'completed') => {
    set({ filter })
  },

  clearError: () => {
    set({ error: null })
  },
}))
