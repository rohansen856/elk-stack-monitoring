export interface ApiError {
  detail?: string
  message?: string
}

export interface Todo {
  id: number
  title: string
  description?: string | null
  completed: boolean
  priority: 'low' | 'medium' | 'high'
  due_date?: string | null
  created_at: string
  updated_at?: string | null
}

export interface TodoStats {
  total_todos: number
  completed_todos: number
  pending_todos: number
  completion_rate: number
}

export interface TodoInput {
  title: string
  description?: string
  priority?: string
  due_date?: string
}

/**
 * Same-origin call to a Next.js route handler.
 *
 * No token is passed: the session lives in an httpOnly cookie the browser
 * attaches automatically, and the route handler converts it into an
 * Authorization header server-side. See AUDIT SEC-006.
 *
 * The generic parameter is required at every call site - it previously
 * defaulted to `{}`, so `todos` was assigned a non-array-typed value and the
 * resulting type errors were hidden by `ignoreBuildErrors`. See AUDIT QA-002.
 */
async function apiCall<T>(endpoint: string, options: RequestInit = {}): Promise<T> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...(options.headers as Record<string, string>),
  }

  const response = await fetch(endpoint, {
    ...options,
    headers,
    credentials: 'same-origin',
  })

  if (!response.ok) {
    const error = (await response.json().catch(() => ({}))) as ApiError
    throw new Error(error.detail || error.message || 'API request failed')
  }

  return response.json() as Promise<T>
}

export const todosApi = {
  getTodos: () => apiCall<Todo[]>('/api/todos'),

  getStats: () => apiCall<TodoStats>('/api/todos/stats'),

  createTodo: (data: TodoInput) =>
    apiCall<Todo>('/api/todos', {
      method: 'POST',
      body: JSON.stringify({
        title: data.title,
        description: data.description,
        priority: data.priority || 'medium',
        due_date: data.due_date,
      }),
    }),

  updateTodo: (
    id: number,
    data: Partial<Omit<Todo, 'id' | 'created_at' | 'updated_at'>>
  ) =>
    apiCall<Todo>(`/api/todos/${id}`, {
      method: 'PUT',
      body: JSON.stringify(data),
    }),

  deleteTodo: (id: number) =>
    apiCall<{ message: string }>(`/api/todos/${id}`, {
      method: 'DELETE',
    }),
}
