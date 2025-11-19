# Sentinel Todo Application

A modern, production-ready todo application built with Next.js 16, Zustand, and FastAPI backend integration.

## Features

- **Authentication**: Email/password registration and login with JWT tokens
- **Task Management**: Create, read, update, and delete todos
- **Filtering**: View all tasks, active tasks, or completed tasks
- **Persistent State**: Local storage integration with Zustand
- **Modern UI**: Clean, responsive design with shadcn/ui components
- **Error Handling**: Comprehensive error pages and error messages
- **Production Ready**: Security headers, CORS support, and optimized builds

## Prerequisites

- Node.js 18+ 
- npm or yarn
- FastAPI backend running on `http://localhost:8000/api/v1`

## Setup

1. **Install dependencies**
   ```bash
   npm install
   ```
2. **Configure environment variables**
   ```bash
   cp .env.example .env.local
   ```
   
   Edit `.env.local` and set your backend URL:
   ```
   BACKEND_URL=http://localhost:8000/api/v1
   NEXT_PUBLIC_APP_URL=http://localhost:3000
   ```

3. **Run the development server**
   ```bash
   npm run dev
   ```
   
   Open [http://localhost:3000](http://localhost:3000) in your browser.

## Development

### Project Structure

```
├── app/
│   ├── api/              # API routes (proxy to FastAPI)
│   ├── auth/             # Authentication pages
│   ├── dashboard/        # Main application page
│   ├── error.tsx         # Error page
│   ├── not-found.tsx     # 404 page
│   ├── globals.css       # Global styles
│   └── layout.tsx        # Root layout
├── components/
│   ├── auth/             # Authentication components
│   ├── layout/           # Layout components
│   ├── todos/            # Todo-related components
│   └── ui/               # shadcn/ui components
├── lib/
│   ├── api-client.ts     # API communication
│   ├── store/            # Zustand stores
│   └── utils/            # Utility functions
└── middleware.ts         # Route protection middleware
```

### Available Scripts

- `npm run dev` - Start development server
- `npm run build` - Build for production
- `npm start` - Start production server
- `npm run lint` - Run ESLint

## Authentication Flow

1. User registers at `/register` with email and password
2. FastAPI backend creates user and returns JWT token
3. Token is stored in localStorage via Zustand
4. Authenticated requests include `Authorization: Bearer <token>` header
5. Middleware protects `/dashboard` route
6. Users can logout which clears token and redirects to login

## API Routes

The application proxies requests to your FastAPI backend:

- `POST /api/auth/login` → `POST /auth/login` on backend
- `POST /api/auth/register` → `POST /auth/register` on backend
- `GET /api/todos` → `GET /todos` on backend (requires auth)
- `POST /api/todos` → `POST /todos` on backend (requires auth)
- `PUT /api/todos/[id]` → `PUT /todos/[id]` on backend (requires auth)
- `DELETE /api/todos/[id]` → `DELETE /todos/[id]` on backend (requires auth)

## Deployment

### Environment Variables for Production

Set these environment variables in your deployment platform:

```
BACKEND_URL=https://your-api-domain.com/api/v1
NEXT_PUBLIC_APP_URL=https://your-app-domain.com
```

### Deploy to Vercel

1. Push code to GitHub
2. Import project in Vercel dashboard
3. Set environment variables
4. Deploy

```bash
# Using Vercel CLI
vercel
```

### Deploy to Other Platforms

The application builds to a standard Next.js output and can be deployed to any Node.js-compatible platform.

```bash
npm run build
npm start
```

## Security

- JWT tokens stored in localStorage (consider httpOnly cookies for production)
- CORS headers properly configured
- Security headers set via Next.js config
- Route middleware protects authenticated pages
- Input validation on forms
- Error boundaries for graceful error handling

## Production Checklist

- [ ] Set production environment variables
- [ ] Enable HTTPS
- [ ] Configure CORS on FastAPI backend
- [ ] Set up database backups
- [ ] Configure monitoring/logging
- [ ] Enable rate limiting on API routes
- [ ] Set up SSL certificates
- [ ] Review security headers
- [ ] Test authentication flow end-to-end
- [ ] Set up error tracking (e.g., Sentry)

## Troubleshooting

### Backend Connection Issues
- Verify `BACKEND_URL` is correct and backend is running
- Check CORS headers on FastAPI backend
- Review browser console for network errors

### Authentication Failures
- Ensure backend returns correct JWT token format
- Check token is stored in localStorage
- Verify Authorization header format: `Bearer <token>`

### Build Errors
- Clear `.next` folder: `rm -rf .next`
- Reinstall dependencies: `rm -rf node_modules && npm install`
- Check Node.js version: `node --version`

## Support

For issues or questions, please open an issue on GitHub or contact the development team.

## License

MIT
