# Flutter App Structure

## Entry Point & State Management
- **main.dart**: Application entry point with MultiProvider setup
  - Configures IrcService and Pop3MailService providers
  - Sets up global state management architecture

## Directory Structure

### /lib
The main Flutter application source code directory.

### /lib/pages
Contains all UI screens and user interface components:
- **browser_page.dart**: Web browsing interface for .i2p sites
- **enhanced_browser_page.dart**: Enhanced browser with additional features
- **irc_page.dart**: Chat interface with channel management
- **mail_page.dart**: Email client with POP3/SMTP integration
- **compose_mail_page.dart**: Email composition interface
- **read_mail_page.dart**: Email reading interface
- **upload_page.dart**: File upload interface to drop.i2p
- **settings_page.dart**: Configuration and preferences
- **irc_settings_page.dart**: IRC-specific settings
- **email_settings_page.dart**: Email configuration
- **create_account_page.dart**: Mail account creation
- **privacy_policy_page.dart**: Privacy policy display
- **tos_page.dart**: Terms of service display

### /lib/services
Core business logic and network communication:

#### Key Services
- **irc_service.dart**: 
  - WebSocket IRC communication with session-based encryption
  - Channel management and message handling
  - AES-256-CBC encryption for chat security

- **pop3_mail_service.dart**:
  - Email service integration with I2P network
  - Encrypted credential management
  - POP3/SMTP proxy communication

- **mail.service.dart**:
  - Additional mail service functionality
  - Mail protocol handling

- **debug_service.dart**:
  - Debug logging and server status monitoring
  - Development and troubleshooting utilities
  - Consistent logging across client-server

- **encryption_service.dart**:
  - Client-side encryption utilities
  - AES-256-CBC implementation
  - Secure key management

### /lib/assets
- **app_logo.dart**: Application logo as Dart constants
- **drop_logo.dart**: Drop.i2p service logo
- **stormycloud_logo.dart**: StormyCloud branding
- **privacy_policy_text.dart**: Privacy policy content
- **tos_text.dart**: Terms of service content

### /lib/data
- **popular_sites.dart**: Popular I2P sites data

### Configuration Files
- **theme.dart**: Application theming and styling configuration
- **pubspec.yaml**: Dependencies and Flutter project configuration

## State Management Pattern
- Uses Provider pattern for service injection
- ChangeNotifier pattern for reactive UI updates
- Centralized service management through MultiProvider

## Key Integration Points
- HTTPS API calls to Node.js backend server
- WebSocket connections for real-time IRC communication
- Encrypted data transmission for sensitive operations
- Debug mode synchronization with server logging

## UI/UX Considerations
- Mobile-first design for I2P network access
- Responsive layouts for various screen sizes
- Privacy-focused interface with minimal data exposure
- User-friendly error handling and network timeout management
- Dark/light theme support through theme.dart

## Testing Structure
```
test/
└── widget_test.dart    # Flutter widget tests
```

## Platform Support
- **Android**: Full support with native Android integration
- **iOS**: Full support with native iOS integration
- **Web**: Basic web support for development/testing
- **macOS**: Desktop support
- **Linux**: Desktop support
- **Windows**: Desktop support