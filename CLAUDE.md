# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository, along with general best practices for working with Claude AI.

## Project Overview

This is a Flutter application called "I2P Bridge" that provides a mobile interface for accessing I2P network services. The app includes HTTP browsing, IRC chat, email, and file upload capabilities, paired with a Node.js server that acts as a bridge to the I2P network.

## Common Development Commands

### Flutter Commands
- `flutter run` - Run the app in development mode
- `flutter build apk` - Build Android APK
- `flutter build ios` - Build iOS app
- `flutter test` - Run unit tests
- `flutter analyze` - Run static analysis (uses flutter_lints)
- `flutter pub get` - Install dependencies
- `flutter pub upgrade` - Upgrade dependencies

### Server Commands  
- `node server.js` - Run the bridge server in production mode
- `node server.js --debug` - Run the bridge server with debug logging
- `pm2 start ecosystem.config.js` - Use PM2 to manage server processes

### Testing
- Test files are located in the `test/` directory
- Run `flutter test` to execute all tests
- The project uses the default Flutter testing framework

## High-Level Architecture

### Flutter App Structure
- **main.dart**: Entry point with MultiProvider setup for IrcService and Pop3MailService
- **pages/**: Contains all UI screens (browser, IRC, mail, upload, settings)
- **services/**: Business logic and network communication
  - `irc_service.dart` - WebSocket IRC communication with encryption
  - `pop3_mail_service.dart` - Email service integration
  - `debug_service.dart` - Debug logging and server status checking
  - `encryption_service.dart` - Client-side encryption utilities
- **assets/**: Static assets and logo definitions as Dart constants
- **theme.dart**: Application theming configuration

### Server Architecture (server.js)
- Express.js HTTPS server on port 443 with SSL certificates
- WebSocket server for encrypted IRC communication  
- TCP proxies for POP3 (port 8110) and SMTP (port 8025) to I2P network
- SQLite database for anonymous usage statistics
- RESTful API with client authentication via User-Agent checking
- End-to-end encryption for mail operations using AES-256-CBC

### Key Integration Points
- Flutter app communicates with Node.js server via HTTPS API calls
- IRC uses WebSocket with session-based encryption (AES-256-CBC)
- Mail operations use encrypted credentials and content
- Debug mode can be enabled on both client and server with consistent logging

### I2P Network Integration
- Server connects to I2P proxy on localhost:4444 for HTTP browsing
- IRC proxy on localhost:6668 for chat functionality
- POP3/SMTP proxies on localhost:7660/7659 for email services
- Uploads go to drop.i2p service through I2P proxy

### Security Features
- HTTPS with Let's Encrypt certificates
- End-to-end encryption for IRC and mail
- Encrypted credential storage for mail accounts
- Anonymous session tracking with daily rotating salts
- Privacy-focused design with minimal data retention

## Project-Specific Important Notes

- The server requires SSL certificates at `/etc/letsencrypt/live/bridge.stormycloud.org/`
- Debug mode affects both client and server - use `--debug` flag or `-d` for detailed logging
- Mail credentials are encrypted before transmission and storage
- The app targets I2P network services specifically (*.i2p domains)
- Statistics collection is anonymized and aggregated for privacy

---

# Claude AI Assistant - Developer Guide

## Current Model Information

- **Model**: Claude Sonnet 4 (claude-sonnet-4-20250514)
- **Knowledge Cutoff**: January 2025
- **Access**: Web interface, API, Claude Code CLI tool

## Programming Capabilities for This Project

### Primary Technologies
- **Flutter/Dart**: Mobile app development, state management, UI components
- **Node.js**: Server-side JavaScript, Express.js, WebSocket handling
- **Security**: AES-256-CBC encryption, SSL/TLS, secure credential handling
- **Networking**: HTTP/HTTPS, WebSocket, TCP proxies, I2P integration
- **Database**: SQLite integration and queries
- **DevOps**: PM2 process management, SSL certificate handling

### Code Quality Standards for This Project

Claude follows these standards when working on the I2P Bridge project:

- **Flutter Best Practices**: Provider pattern, proper widget lifecycle, responsive design
- **Node.js Security**: Input validation, secure headers, encrypted data handling
- **I2P Integration**: Proper proxy configuration, anonymous networking principles
- **Error Handling**: Comprehensive try-catch blocks, user-friendly error messages
- **Performance**: Efficient state management, optimized network calls
- **Privacy**: Minimal data collection, encrypted storage, anonymous analytics

## Security Considerations for This Project

### Project-Specific Security Focus

- **End-to-End Encryption**: AES-256-CBC for IRC and mail communications
- **Credential Security**: Encrypted storage and transmission of mail credentials
- **Network Privacy**: I2P network integration for anonymous browsing
- **SSL/TLS**: HTTPS enforcement with Let's Encrypt certificates
- **Session Management**: Secure WebSocket sessions with rotating encryption keys
- **Data Minimization**: Anonymous statistics collection with daily salt rotation

### Security Review Checklist

When working on this project, Claude will verify:

- [ ] All network communications use encryption
- [ ] Credentials are never stored in plaintext
- [ ] I2P proxy configurations are secure
- [ ] SSL certificate paths are correctly configured
- [ ] WebSocket connections use session-based encryption
- [ ] Database queries are parameterized
- [ ] Error messages don't leak sensitive information
- [ ] Debug logging doesn't expose credentials

## Best Practices for Working with Claude on This Project

### Effective Prompting for I2P Bridge

```markdown
# Good Project-Specific Prompts:

"I need to add a new feature to the Flutter IRC service that handles 
encrypted channel joins. The feature should:
- Use the existing AES-256-CBC encryption from encryption_service.dart
- Integrate with the WebSocket connection in irc_service.dart
- Follow the privacy-first design principles
- Include proper error handling for I2P network timeouts"

"Review the server.js mail proxy code for security vulnerabilities, 
focusing on:
- Credential encryption/decryption flows
- TCP proxy connection handling
- SSL certificate validation
- Anonymous session tracking"
```

### Development Workflow

1. **Understand Context**: Reference existing services and architecture
2. **Security First**: Always consider encryption and privacy implications
3. **I2P Integration**: Ensure compatibility with I2P network constraints
4. **Testing**: Include both unit tests and I2P network integration tests
5. **Documentation**: Update relevant architecture sections

### Common Development Patterns in This Project

#### Flutter Service Integration
```dart
// Example pattern used in this project
class NewService extends ChangeNotifier {
  final EncryptionService _encryptionService;
  final DebugService _debugService;
  
  NewService(this._encryptionService, this._debugService);
  
  Future<void> performSecureOperation(String data) async {
    try {
      final encrypted = await _encryptionService.encrypt(data);
      // Process encrypted data
      _debugService.log('Operation completed successfully');
      notifyListeners();
    } catch (e) {
      _debugService.log('Error: $e');
      rethrow;
    }
  }
}
```

#### Server-Side Security Pattern
```javascript
// Example pattern from server.js
app.post('/secure-endpoint', authenticateClient, async (req, res) => {
  try {
    // Validate and sanitize input
    const sanitizedData = sanitizeInput(req.body);
    
    // Encrypt sensitive data
    const encrypted = encrypt(sanitizedData, sessionKey);
    
    // Process through I2P proxy
    const result = await processViaI2P(encrypted);
    
    res.json({ success: true, data: result });
  } catch (error) {
    logger.error('Endpoint error:', error.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});
```

## Project-Specific Limitations and Considerations

### I2P Network Constraints
- **Latency**: I2P connections can be slow; implement appropriate timeouts
- **Reliability**: Network connections may drop; include retry logic
- **Privacy**: Never log I2P addresses or user identifiers

### Flutter Development
- **State Management**: Use Provider pattern consistently
- **Platform Differences**: Consider iOS/Android specific requirements
- **Network Handling**: Implement proper timeout and retry mechanisms

### Server Configuration
- **SSL Certificates**: Automatic certificate renewal considerations
- **Process Management**: PM2 configuration for production stability
- **Resource Usage**: SQLite database optimization for mobile server

## Debugging and Monitoring

### Debug Mode Features
- **Client**: Enable detailed logging in Flutter app with `-d` flag equivalent
- **Server**: Use `--debug` flag for verbose logging
- **Integration**: Debug mode affects both client and server consistently

### Common Issues and Solutions
- **Certificate Errors**: Check Let's Encrypt certificate paths and permissions
- **I2P Connectivity**: Verify proxy configurations and I2P router status
- **WebSocket Issues**: Check encryption key synchronization
- **Mail Proxy**: Verify POP3/SMTP proxy port configurations

## Resources and Support

### Project Documentation
- Architecture details in this CLAUDE.md file
- Code comments in services/ directory
- SSL configuration in server.js

### External Resources
- **Flutter Docs**: https://docs.flutter.dev/
- **I2P Documentation**: https://geti2p.net/en/docs
- **Node.js Security**: https://nodejs.org/en/docs/guides/security/

### Claude AI Resources
- **API Docs**: https://docs.anthropic.com
- **Support**: https://support.anthropic.com
- **Claude Code**: Available in research preview for command-line development

---

*This guide is specifically tailored for the I2P Bridge project. When working on this codebase, always prioritize security, privacy, and I2P network compatibility.*