# API Documentation

## Overview

The Advanced Threat Detection System provides a comprehensive REST API built with FastAPI. The API includes endpoints for user management, todo operations, and security monitoring.

## Base URL
- **Development**: `http://localhost:8000`
- **API Documentation**: `http://localhost:8000/docs` (Interactive Swagger UI)
- **API Schema**: `http://localhost:8000/redoc` (ReDoc documentation)

## Authentication

The API uses JWT (JSON Web Token) based authentication. Include the token in the Authorization header:

```
Authorization: Bearer <your-jwt-token>
```

### Token Expiration
- Default expiration: 30 minutes
- Configurable via `ACCESS_TOKEN_EXPIRE_MINUTES` environment variable

## API Endpoints

### Health & Monitoring

#### GET /health
Returns system health status including database and Redis connectivity.

**Response:**
```json
{
  "status": "healthy",
  "database": "ok",
  "redis": "ok"
}
```

#### GET /metrics
Returns Prometheus metrics for system monitoring.

**Response:** Plain text metrics format

### User Management (`/api/v1/users`)

#### POST /api/v1/users/register
Register a new user account.

**Request Body:**
```json
{
  "username": "johndoe",
  "email": "john@example.com",
  "password": "securepassword123"
}
```

**Response:**
```json
{
  "id": "uuid",
  "username": "johndoe",
  "email": "john@example.com",
  "is_active": true,
  "created_at": "2024-11-19T10:30:00Z",
  "updated_at": "2024-11-19T10:30:00Z"
}
```

#### POST /api/v1/users/login
Authenticate user and receive JWT token.

**Request Body:**
```json
{
  "email": "john@example.com",
  "password": "securepassword123"
}
```

**Response:**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "bearer"
}
```

#### GET /api/v1/users/me
Get current user profile (requires authentication).

**Response:**
```json
{
  "id": "uuid",
  "username": "johndoe",
  "email": "john@example.com",
  "is_active": true,
  "created_at": "2024-11-19T10:30:00Z",
  "updated_at": "2024-11-19T10:30:00Z"
}
```

### Todo Management (`/api/v1/todos`)

#### GET /api/v1/todos
Retrieve user's todos with optional filtering.

**Query Parameters:**
- `completed`: Filter by completion status (true/false)
- `priority`: Filter by priority level (low/medium/high)
- `search`: Search in title and description
- `skip`: Number of items to skip (pagination)
- `limit`: Maximum number of items to return

**Response:**
```json
[
  {
    "id": "uuid",
    "title": "Complete security audit",
    "description": "Review all security configurations",
    "completed": false,
    "priority": "high",
    "due_date": "2024-11-25T09:00:00Z",
    "created_at": "2024-11-19T10:30:00Z",
    "updated_at": "2024-11-19T10:30:00Z"
  }
]
```

#### POST /api/v1/todos
Create a new todo item.

**Request Body:**
```json
{
  "title": "Complete security audit",
  "description": "Review all security configurations",
  "priority": "high",
  "due_date": "2024-11-25T09:00:00Z"
}
```

**Response:** Same as GET todo response

#### GET /api/v1/todos/{todo_id}
Retrieve a specific todo by ID.

**Response:** Single todo object

#### PUT /api/v1/todos/{todo_id}
Update a specific todo.

**Request Body:**
```json
{
  "title": "Updated title",
  "description": "Updated description",
  "completed": true,
  "priority": "medium",
  "due_date": "2024-11-26T09:00:00Z"
}
```

#### DELETE /api/v1/todos/{todo_id}
Delete a specific todo.

**Response:** `204 No Content`

### Security Monitoring (`/api/v1/security`)

#### GET /api/v1/security/threats/brute-force
Detect brute force attack patterns.

**Response:**
```json
{
  "threat_type": "brute_force",
  "risk_score": 7,
  "events_found": 12,
  "time_window": "15 minutes",
  "affected_users": ["admin", "user1"],
  "timestamp": "2024-11-19T10:30:00Z"
}
```

#### GET /api/v1/security/threats/data-exfiltration
Monitor for data exfiltration attempts.

**Response:**
```json
{
  "threat_type": "data_exfiltration",
  "risk_score": 8,
  "data_transferred": "150MB",
  "suspicious_destinations": ["external-ip-1", "external-ip-2"],
  "timestamp": "2024-11-19T10:30:00Z"
}
```

#### GET /api/v1/security/threats/powershell
Detect PowerShell-based attacks.

**Response:**
```json
{
  "threat_type": "powershell_attack",
  "risk_score": 9,
  "encoded_commands": 5,
  "bypass_techniques": ["ExecutionPolicy bypass", "AMSI bypass"],
  "timestamp": "2024-11-19T10:30:00Z"
}
```

#### GET /api/v1/security/threats/apt-correlation
Analyze APT kill-chain correlations.

**Response:**
```json
{
  "threat_type": "apt_correlation",
  "risk_score": 10,
  "kill_chain_stages": ["initial_access", "persistence", "lateral_movement"],
  "correlated_events": 25,
  "campaign_indicators": ["apt29", "cozy_bear"],
  "timestamp": "2024-11-19T10:30:00Z"
}
```

#### POST /api/v1/security/alerts/test
Test the alerting system.

**Response:**
```json
{
  "message": "Test alert sent successfully",
  "channels": ["elasticsearch", "console"],
  "timestamp": "2024-11-19T10:30:00Z"
}
```

## Data Models

### User
```typescript
interface User {
  id: string;
  username: string;
  email: string;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}
```

### Todo
```typescript
interface Todo {
  id: string;
  title: string;
  description?: string;
  completed: boolean;
  priority: 'low' | 'medium' | 'high';
  due_date?: string;
  created_at: string;
  updated_at: string;
}
```

### Priority Levels
- **low**: Low priority tasks
- **medium**: Standard priority tasks
- **high**: High priority tasks requiring immediate attention

## Error Handling

### Standard Error Response
```json
{
  "detail": "Error message describing what went wrong",
  "type": "error_type",
  "loc": ["field", "path"] // for validation errors
}
```

### Common HTTP Status Codes
- **200**: Success
- **201**: Created
- **204**: No Content
- **400**: Bad Request (validation error)
- **401**: Unauthorized (authentication required)
- **403**: Forbidden (insufficient permissions)
- **404**: Not Found
- **422**: Unprocessable Entity (validation error)
- **500**: Internal Server Error

## Frontend API Integration

### Next.js API Routes
The frontend uses Next.js API routes as proxies to the FastAPI backend:

- `/api/auth/login` → `POST /api/v1/users/login`
- `/api/auth/register` → `POST /api/v1/users/register`
- `/api/auth/me` → `GET /api/v1/users/me`
- `/api/todos` → `GET/POST /api/v1/todos`
- `/api/todos/[id]` → `GET/PUT/DELETE /api/v1/todos/{id}`

### API Client Configuration
```typescript
const API_BASE_URL = process.env.BACKEND_URL || 'http://localhost:8000';

// Headers for authenticated requests
const headers = {
  'Content-Type': 'application/json',
  'Authorization': `Bearer ${token}`
};
```

## Development & Testing

### Interactive Documentation
Visit `http://localhost:8000/docs` for interactive API documentation with built-in testing capabilities.

### Testing with cURL

**Login Example:**
```bash
curl -X POST "http://localhost:8000/api/v1/users/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"testpass"}'
```

**Create Todo Example:**
```bash
curl -X POST "http://localhost:8000/api/v1/todos" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-jwt-token" \
  -d '{"title":"Test Todo","priority":"medium","due_date":"2024-12-01T09:00:00Z"}'
```

**Security Monitoring Example:**
```bash
curl "http://localhost:8000/api/v1/security/threats/brute-force"
```

## Security Considerations

### Authentication
- All user endpoints (except registration/login) require valid JWT tokens
- Tokens expire after 30 minutes by default
- Use HTTPS in production environments

### Rate Limiting
Consider implementing rate limiting for:
- Authentication endpoints (prevent brute force)
- Registration endpoints (prevent spam)
- Security monitoring endpoints

### CORS Configuration
The API is configured with CORS middleware to allow frontend access. Update CORS settings in production for your specific domain.

### Environment Variables
Required environment variables:
- `SECRET_KEY`: JWT signing secret
- `DATABASE_URL`: PostgreSQL connection string
- `REDIS_URL`: Redis connection string
- `ELASTICSEARCH_URL`: Elasticsearch connection string

This API provides a complete foundation for the Advanced Threat Detection System with comprehensive user management, task organization, and security monitoring capabilities.