# Development Workflow & Commands

## Flutter Development Commands

### Core Flutter Commands
```bash
# Development
flutter run                    # Run app in development mode
flutter run -d chrome         # Run in Chrome (web debugging)
flutter run --debug          # Run with debug mode enabled

# Building
flutter build apk             # Build Android APK
flutter build appbundle      # Build Android App Bundle
flutter build ios            # Build iOS app
flutter build web            # Build web version

# Testing & Quality
flutter test                  # Run unit tests
flutter test --coverage      # Run tests with coverage
flutter analyze              # Run static analysis (flutter_lints)
flutter doctor               # Check Flutter installation

# Dependencies
flutter pub get               # Install dependencies
flutter pub upgrade          # Upgrade dependencies
flutter pub deps             # Show dependency tree
flutter clean                # Clean build artifacts
```

### Development Workflow
1. **Code Changes**: Make changes to Dart files
2. **Hot Reload**: Press `r` in terminal or save files in IDE
3. **Testing**: Run `flutter test` for unit tests
4. **Analysis**: Run `flutter analyze` before commits
5. **Build**: Test builds periodically with `flutter build apk`

## Server Development Commands

### Node.js Server Commands
```bash
# Development
node server.js --debug       # Run with debug logging enabled
node server.js -d           # Short form debug flag
node server.js              # Run in production mode

# Process Management (Production)
pm2 start ecosystem.config.js    # Start with PM2
pm2 restart i2p-bridge          # Restart service
pm2 stop i2p-bridge             # Stop service
pm2 logs i2p-bridge             # View logs
pm2 status                       # Check status
```

### Server Development Workflow
1. **Code Changes**: Modify server.js or related files
2. **Restart Server**: Stop and restart Node.js process
3. **Debug Mode**: Use `--debug` flag for detailed logging
4. **Test Integration**: Verify Flutter app can connect
5. **Production Deploy**: Use PM2 for production management

## Testing Strategy

### Flutter Testing
```bash
# Unit Tests
flutter test test/                    # Run all tests
flutter test test/widget_test.dart    # Test specific file

# Integration Tests (if implemented)
flutter test integration_test/       # Run integration tests
flutter drive --target=test_driver/app.dart  # UI tests
```

### Test File Structure
```
test/
└── widget_test.dart    # Flutter widget tests
```

## Code Quality & Analysis

### Static Analysis (flutter_lints)
```bash
flutter analyze                # Check for issues
flutter analyze --fatal-infos # Treat info as errors
```

### Code Formatting
```bash
dart format .                  # Format all Dart files
dart format lib/ test/         # Format specific directories
```

### Common Linting Rules
- Follow Flutter/Dart style guidelines
- Use proper widget structure and naming
- Implement proper error handling
- Maintain consistent code organization

## Debug Mode Features

### Client Debug Mode
- Enable detailed logging in Flutter app
- Debug service integration with server
- Network request/response logging
- UI state debugging

### Server Debug Mode
```bash
node server.js --debug
```
- Verbose HTTP request logging
- WebSocket connection details
- I2P proxy communication logs
- Database operation logging
- SSL certificate status

### Debug Synchronization
- Client and server debug modes work together
- Consistent logging format across platforms
- Cross-platform debug session correlation

## Git Workflow

### Branch Strategy
- **main**: Production-ready code
- **ui**: Current development branch (UI improvements)
- **feature/***: Feature development branches
- **hotfix/***: Critical bug fixes

### Common Git Commands
```bash
git status                     # Check working directory
git add .                      # Stage all changes
git commit -m "message"        # Commit changes
git push origin ui             # Push to ui branch
git pull origin main           # Pull latest from main
```

### Recent Development Focus
- UI improvements and user experience
- Mail account creation (#2)
- Bug fixes for malformed URLs (#4)
- Debug mode implementation
- WebView integration

## Development Environment Setup

### Prerequisites
- Flutter SDK (latest stable)
- Node.js (v16+ recommended)
- I2P router running locally
- SSL certificates for HTTPS server

### Local Development Setup
1. Clone repository
2. Install Flutter dependencies: `flutter pub get`
3. Install Node.js dependencies: `npm install` (if applicable)
4. Start I2P router
5. Configure SSL certificates
6. Start server: `node server.js --debug`
7. Run Flutter app: `flutter run`

## Production Deployment

### Server Deployment
```bash
# PM2 Configuration
pm2 start ecosystem.config.js

# SSL Certificate Management
certbot renew --dry-run       # Test certificate renewal
certbot renew                 # Renew certificates
```

### App Store Deployment
```bash
# Android
flutter build appbundle      # For Google Play Store
flutter build apk           # For direct APK distribution

# iOS (requires Xcode)
flutter build ios           # Build iOS app
# Then use Xcode for App Store submission
```

## Troubleshooting Common Issues

### Flutter Issues
- **Build Failures**: Run `flutter clean` then `flutter pub get`
- **Hot Reload Not Working**: Restart Flutter app
- **Dependencies**: Check pubspec.yaml for conflicts
- **Platform Issues**: Check platform-specific configurations

### Server Issues
- **SSL Certificate Errors**: Check certificate paths and permissions
- **I2P Connectivity**: Verify I2P router is running
- **Port Conflicts**: Ensure ports 443, 8110, 8025 are available
- **Permission Issues**: Check file permissions for certificates

### Integration Issues
- **Client-Server Communication**: Check server URL in Flutter code
- **WebSocket Connections**: Verify WSS connection and certificates
- **Debug Mode**: Ensure both client and server use consistent debug settings

## Development Best Practices

### Code Organization
- Keep services focused and single-purpose
- Use proper error handling throughout
- Implement consistent logging
- Follow Flutter/Dart conventions

### Security Considerations
- Never commit credentials or certificates
- Test encryption implementations thoroughly
- Validate all user inputs
- Use secure communication protocols

### Performance
- Optimize for I2P network constraints
- Implement proper caching strategies
- Monitor memory usage
- Test under various network conditions

## Documentation
- Keep CLAUDE.md updated with changes
- Document API changes
- Update this documentation as needed
- Maintain inline code comments for complex logic