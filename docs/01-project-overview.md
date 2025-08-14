# I2P Bridge - Project Overview

## Purpose
I2P Bridge is a Flutter mobile application that provides a user-friendly interface for accessing I2P (Invisible Internet Project) network services. The app serves as a bridge between mobile users and the I2P anonymity network, offering secure and private access to various I2P services.

## Core Features
- **HTTP Browsing**: Browse .i2p websites through I2P proxy
- **IRC Chat**: Encrypted IRC communication via WebSocket
- **Email Services**: POP3/SMTP mail access with encryption
- **File Upload**: Upload files to drop.i2p service
- **Settings Management**: Configure I2P services and debug options

## High-Level Architecture

### Client-Server Model
- **Flutter App**: Mobile frontend providing UI and local services
- **Node.js Server**: Backend bridge server handling I2P network communication
- **I2P Network**: Anonymous network providing privacy-focused services

### Technology Stack
- **Frontend**: Flutter/Dart with Provider state management
- **Backend**: Node.js with Express.js and WebSocket
- **Database**: SQLite for anonymous usage statistics
- **Security**: AES-256-CBC encryption, SSL/TLS certificates
- **Network**: I2P proxy integration, TCP proxies for mail

## Key Design Principles
1. **Privacy First**: Anonymous usage tracking with minimal data retention
2. **End-to-End Encryption**: All sensitive communications encrypted
3. **I2P Integration**: Native support for I2P network constraints
4. **Security Focus**: Secure credential handling and network communication
5. **User Experience**: Simple mobile interface for complex anonymity network

## Development Status
- Current branch: `ui`
- Recent focus: UI improvements, mail account creation, debugging features
- Architecture: Established with core services implemented

## Project Structure
```
i2p_bridge/
├── lib/                    # Flutter app source code
├── server.js              # Node.js backend server
├── docs/                  # Project documentation
├── test/                  # Flutter tests
└── CLAUDE.md             # Development instructions
```