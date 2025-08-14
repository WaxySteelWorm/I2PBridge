# Node.js Server Architecture

## Core Server Configuration
- **Framework**: Express.js HTTPS server
- **Port**: 443 (HTTPS with SSL certificates)
- **SSL**: Let's Encrypt certificates at `/etc/letsencrypt/live/bridge.stormycloud.org/`
- **Database**: SQLite for anonymous usage statistics
- **Process Management**: PM2 with ecosystem.config.js

## Key Components

### WebSocket Server
- Real-time IRC communication with Flutter client
- Session-based encryption using AES-256-CBC
- Secure message routing and channel management
- Connection state management and error handling

### TCP Proxy Services
- **POP3 Proxy**: Port 8110 → I2P network mail servers
- **SMTP Proxy**: Port 8025 → I2P network mail servers
- **HTTP Proxy**: Port 4444 → I2P network web services
- **IRC Proxy**: Port 6668 → I2P IRC servers

### RESTful API Endpoints

#### Authentication & Security
- Client authentication via User-Agent header validation
- Session management for WebSocket connections
- Request validation and input sanitization

#### Core API Routes
- **Browser Requests**: Proxy HTTP requests to .i2p sites
- **Mail Operations**: Encrypted POP3/SMTP credential handling
- **File Upload**: Secure upload to drop.i2p service
- **IRC Management**: Channel joins, message routing
- **Debug Endpoints**: Server status and logging control

### Database Schema (SQLite)
- Anonymous usage statistics collection
- Daily rotating salts for privacy protection
- Session tracking with minimal data retention
- Performance metrics and error logging

## I2P Network Integration

### Proxy Configuration
- **I2P HTTP Proxy**: localhost:4444 for web browsing
- **I2P IRC Proxy**: localhost:6668 for chat services
- **I2P Mail Proxies**: localhost:7660 (POP3), localhost:7659 (SMTP)

### Network Handling
- Timeout management for slow I2P connections
- Retry logic for failed network requests
- Error handling for I2P service unavailability
- Connection pooling and resource management

## Security Implementation

### Encryption Features
- End-to-end AES-256-CBC encryption for sensitive data
- Secure WebSocket session key exchange
- Encrypted credential storage and transmission
- SSL/TLS termination with certificate management

### Privacy Protection
- Anonymous session tracking
- No persistent user identification
- Minimal logging of sensitive information
- Daily salt rotation for statistics

## Operational Features

### Debug Mode
- `--debug` flag for verbose logging
- Server status monitoring endpoints
- Performance metrics collection
- Error tracking and reporting

### Production Deployment
- PM2 process management for stability
- Automatic SSL certificate renewal
- Resource monitoring and optimization
- Graceful shutdown handling

## Server Startup Commands
```bash
# Development
node server.js --debug

# Production
node server.js
pm2 start ecosystem.config.js
```

## File Structure
```
server.js                 # Main server file
ecosystem.config.js       # PM2 configuration
```

## Error Handling
- Comprehensive try-catch blocks for all operations
- User-friendly error messages without sensitive data exposure
- Proper HTTP status codes and error responses
- Logging of errors for debugging without exposing credentials

## Performance Considerations
- Connection pooling for I2P proxy connections
- Request rate limiting to prevent abuse
- Memory management for long-running processes
- Efficient SQLite database operations

## Monitoring & Logging
- Structured logging with different levels (debug, info, warn, error)
- Performance metrics collection
- Health check endpoints for monitoring
- Integration with PM2 for process monitoring