type LogLevel = 'debug' | 'info' | 'warn' | 'error'

interface LogEntry {
  timestamp: string
  level: LogLevel
  message: string
  data?: unknown
}

const isDevelopment = process.env.NODE_ENV === 'development'

function formatLog(level: LogLevel, message: string, data?: unknown): string {
  const timestamp = new Date().toISOString()
  const dataStr = data ? ` ${JSON.stringify(data)}` : ''
  return `[${timestamp}] [${level.toUpperCase()}] ${message}${dataStr}`
}

export const logger = {
  debug: (message: string, data?: unknown) => {
    if (isDevelopment) {
      console.log(formatLog('debug', message, data))
    }
  },

  info: (message: string, data?: unknown) => {
    console.log(formatLog('info', message, data))
  },

  warn: (message: string, data?: unknown) => {
    console.warn(formatLog('warn', message, data))
  },

  error: (message: string, data?: unknown) => {
    console.error(formatLog('error', message, data))
  },

  // Track API calls
  api: (method: string, endpoint: string, status?: number, duration?: number) => {
    const logData = { method, endpoint, status, duration: `${duration}ms` }
    if (status && status >= 400) {
      logger.warn(`API ${method} ${endpoint}`, logData)
    } else if (isDevelopment) {
      logger.debug(`API ${method} ${endpoint}`, logData)
    }
  },

  // Track user actions
  track: (action: string, properties?: Record<string, unknown>) => {
    if (isDevelopment) {
      logger.debug(`TRACK: ${action}`, properties)
    }
  },
}
