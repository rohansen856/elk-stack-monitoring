export interface ErrorResponse {
  message: string
  code: string
  statusCode: number
}

export class AppError extends Error {
  constructor(
    public code: string,
    public statusCode: number,
    message: string
  ) {
    super(message)
    this.name = 'AppError'
  }
}

export const errorMessages = {
  UNAUTHORIZED: 'Please log in to continue',
  FORBIDDEN: 'You do not have permission to perform this action',
  NOT_FOUND: 'The requested resource was not found',
  VALIDATION_ERROR: 'Please check your input and try again',
  SERVER_ERROR: 'An error occurred. Please try again later',
  NETWORK_ERROR: 'Network error. Please check your connection',
}

export function handleError(error: unknown): ErrorResponse {
  if (error instanceof AppError) {
    return {
      message: error.message,
      code: error.code,
      statusCode: error.statusCode,
    }
  }

  if (error instanceof Error) {
    return {
      message: error.message,
      code: 'UNKNOWN_ERROR',
      statusCode: 500,
    }
  }

  return {
    message: errorMessages.SERVER_ERROR,
    code: 'UNKNOWN_ERROR',
    statusCode: 500,
  }
}

export function getErrorMessage(code: string): string {
  return errorMessages[code as keyof typeof errorMessages] || errorMessages.SERVER_ERROR
}
