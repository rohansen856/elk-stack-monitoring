export interface ApiError {
  detail?: string
  message?: string
}

async function apiCall<T>(
  endpoint: string,
  options: RequestInit & { token?: string } = {}
): Promise<T> {
  const { token, ...fetchOptions } = options

  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...(fetchOptions.headers as Record<string, string>),
  }

  if (token) {
    headers.Authorization = `Bearer ${token}`
  }

  const response = await fetch(endpoint, {
    ...fetchOptions,
    headers,
  })

  if (!response.ok) {
    const error = (await response.json()) as ApiError
    throw new Error(error.detail || error.message || 'API request failed')
  }

  return response.json()
}

export const todosApi = {
  getTodos: (token: string) =>
    apiCall('/api/todos', {
      token,
    }),

  createTodo: (token: string, data: { title: string; description?: string; priority?: string; due_date?: string }) =>
    apiCall('/api/todos', {
      token,
      method: 'POST',
      body: JSON.stringify({
        title: data.title,
        description: data.description,
        priority: data.priority || 'medium',
        due_date: data.due_date,
      }),
    }),

  updateTodo: (
    token: string,
    id: string,
    data: { title?: string; description?: string; completed?: boolean; priority?: string; due_date?: string }
  ) =>
    apiCall(`/api/todos/${id}`, {
      token,
      method: 'PUT',
      body: JSON.stringify(data),
    }),

  deleteTodo: (token: string, id: string) =>
    apiCall(`/api/todos/${id}`, {
      token,
      method: 'DELETE',
    }),
}
