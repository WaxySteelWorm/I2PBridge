# API Key Management Guide

## Overview

The I2P Bridge Server now supports database-managed API keys with app-specific metadata. This allows for better key management, rotation, and tracking of different app deployments.

## Key Features

- **Database-Managed Keys**: API keys are stored securely in SQLite database (hashed)
- **App-Specific Keys**: Each Flutter app version/platform can have its own key
- **Legacy Support**: Environment variable `I2P_BRIDGE_API_KEY` still works for backward compatibility
- **Zero-Downtime Rotation**: Rotate keys with grace periods
- **Admin Dashboard**: Manage keys through the web interface at `/dashboard`

## Creating API Keys

### Method 1: Admin Dashboard (Recommended)

1. Access the admin dashboard from a Tailscale-connected device: `https://your-server/dashboard`
2. Navigate to "API Keys" section
3. Click "Generate New Key"
4. Fill in:
   - **Description**: e.g., "Flutter iOS v1.2.0 Production"
   - **App Version**: e.g., "1.2.0"
   - **App Platform**: Select from dropdown (flutter-ios, flutter-android, etc.)
   - **Expiration**: Choose expiration period or "Never"
5. Copy the generated key - it won't be shown again!

### Method 2: Migration Script

Use the migration script to create keys programmatically:

```bash
# Create default keys for all platforms
node migrate-api-keys.js

# Create a custom app-specific key
node migrate-api-keys.js --create-app-key

# List existing keys
node migrate-api-keys.js --list
```

### Method 3: Direct API Call

```bash
curl -X POST https://your-server/api/v1/admin/apikey/create \
  -H "Content-Type: application/json" \
  -d '{
    "description": "Flutter iOS Production",
    "appVersion": "1.2.0",
    "appPlatform": "flutter-ios",
    "expiresInDays": 365
  }'
```

## Using API Keys in Flutter Apps

### Build-Time Configuration (Recommended for Production)

Include the API key when building your Flutter app:

```bash
# iOS
flutter build ios --dart-define=I2P_BRIDGE_API_KEY=your-api-key-here

# Android
flutter build apk --dart-define=I2P_BRIDGE_API_KEY=your-api-key-here

# Web
flutter build web --dart-define=I2P_BRIDGE_API_KEY=your-api-key-here

# macOS
flutter build macos --dart-define=I2P_BRIDGE_API_KEY=your-api-key-here
```

### Development Configuration

For development, you can use a `.env` file (don't commit this!):

```bash
# .env.local
I2P_BRIDGE_API_KEY=your-dev-api-key-here
```

Then run:
```bash
flutter run --dart-define-from-file=.env.local
```

## Key Rotation Strategy

### Automatic Rotation

Keys can be set to expire automatically. The system will:
1. Notify admins 7 days before expiration
2. Allow grace period during rotation
3. Track old key usage during transition

### Manual Rotation

1. Generate new key via dashboard
2. Update your Flutter build with new key
3. Deploy new app version
4. Old key remains active for 48 hours (configurable)
5. Monitor dashboard for old key usage
6. Old key automatically deactivates after grace period

## Best Practices

### App Versioning

Create separate keys for:
- Different platforms (iOS, Android, Web)
- Different environments (Dev, Staging, Production)
- Major version releases

Example naming convention:
- `Flutter iOS v1.0.0 Production`
- `Flutter Android v1.0.0 Production`
- `Flutter iOS v1.0.0 Development`
- `Flutter Web Beta Testing`

### Security

1. **Never commit API keys** to version control
2. **Use environment variables** or secure build systems
3. **Rotate keys regularly** (every 90-365 days)
4. **Monitor key usage** via admin dashboard
5. **Revoke compromised keys** immediately

### Deployment Workflow

1. **Development Phase**
   - Use development key with short expiration
   - Track usage in dashboard

2. **Testing Phase**
   - Create beta testing keys
   - Monitor for unusual patterns

3. **Production Release**
   - Generate production keys with appropriate expiration
   - Document key ID and version in release notes
   - Monitor usage metrics

4. **Post-Release**
   - Track key usage by version
   - Plan rotation schedule
   - Deprecate old versions

## Monitoring & Analytics

The admin dashboard shows:
- **Active Keys**: Total count and list
- **Usage Metrics**: Requests per key
- **Platform Distribution**: iOS vs Android vs Web usage
- **Version Tracking**: Which app versions are active
- **Expiration Warnings**: Keys expiring soon

## Troubleshooting

### Common Issues

1. **"Invalid API Key" Error**
   - Verify key is active in dashboard
   - Check for typos or truncation
   - Ensure key hasn't expired

2. **Flutter Build Issues**
   - Verify `--dart-define` syntax
   - Check for special characters in key
   - Ensure quotes are properly escaped

3. **Key Not Working After Rotation**
   - Confirm new key is active
   - Verify app is using new key
   - Check grace period hasn't expired

### Debug Commands

```bash
# Check if key exists in database
sqlite3 bridge_analytics.db "SELECT key_id, description, is_active FROM api_keys WHERE description LIKE '%search-term%';"

# View recent key usage
sqlite3 bridge_analytics.db "SELECT * FROM api_key_audit ORDER BY timestamp DESC LIMIT 10;"

# Check active keys count
sqlite3 bridge_analytics.db "SELECT COUNT(*) FROM api_keys WHERE is_active = 1;"
```

## Migration from Environment Variable

If you're currently using `I2P_BRIDGE_API_KEY` environment variable:

1. Run migration script: `node migrate-api-keys.js`
2. Script will create a database entry for existing key
3. Generate new app-specific keys for future deployments
4. Update Flutter apps with new keys
5. Remove environment variable after transition

## API Endpoints

### Admin Endpoints (Tailscale network only)

- `GET /api/v1/admin/apikey/list` - List all API keys
- `POST /api/v1/admin/apikey/create` - Create new key
- `POST /api/v1/admin/apikey/rotate` - Rotate existing key
- `DELETE /api/v1/admin/apikey/:keyId` - Revoke key

### Regular Authentication

- `POST /api/v1/auth/token` - Exchange API key for JWT token
- `POST /api/v1/auth/verify` - Verify token validity

## Support

For issues or questions:
1. Check admin dashboard for key status
2. Review server logs for authentication errors
3. Use debug mode for detailed logging: `node server.js --debug`