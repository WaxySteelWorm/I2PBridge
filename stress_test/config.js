// Configuration for I2P Bridge stress testing

module.exports = {
  // Bridge server configuration
  BRIDGE_HOST: 'bridge.stormycloud.org',
  BRIDGE_PORT: 443,
  
  // API endpoints
  ENDPOINTS: {
    AUTH: '/auth/token',
    BROWSE: '/api/v1/browse',
    UPLOAD: '/api/v1/upload',
    DEBUG: '/api/v1/debug'
  },
  
  // WebSocket endpoint for IRC
  IRC_WEBSOCKET_URL: 'wss://bridge.stormycloud.org',
  
  // Test data
  I2P_SITES: [
    'notbob.i2p',
    'i2pforum.i2p', 
    'shinobi.i2p',
    'ramble.i2p',
    'natter.i2p'
  ],
  
  // IRC test channels
  IRC_CHANNELS: [
    '#test',
    '#general',
    '#random',
    '#bridge-test'
  ],
  
  // Test files for upload (generated during test)
  UPLOAD_FILE_SIZES: [
    1024,        // 1KB
    10240,       // 10KB
    102400,      // 100KB
    1048576,     // 1MB
    5242880,     // 5MB
    10485760     // 10MB
  ],
  
  // Default test parameters
  DEFAULT_TEST_DURATION: 60, // seconds
  DEFAULT_CONCURRENT_USERS: 10,
  
  // Timing configurations
  TIMINGS: {
    REQUEST_TIMEOUT: 30000,     // 30 seconds
    CONNECTION_TIMEOUT: 10000,  // 10 seconds
    IRC_REGISTRATION_DELAY: 11000, // 11 seconds (IRC server requirement)
    RETRY_DELAY: 2000,          // 2 seconds
    METRIC_COLLECTION_INTERVAL: 1000 // 1 second
  },
  
  // Load test thresholds
  THRESHOLDS: {
    MAX_RESPONSE_TIME: 5000,    // 5 seconds
    MAX_ERROR_RATE: 0.05,       // 5%
    MIN_THROUGHPUT: 10          // requests per second
  },
  
  // Security configuration
  SECURITY: {
    SSL_PINNING: true,
    EXPECTED_CERT_FINGERPRINT: 'AO5T/CbxDzIBFkUp6jLEcAk0+ZxeN06uaKyeIzIE+E0=',
    USER_AGENT: 'I2PBridge-StressTest/1.0.0 (Node.js)',
    ENABLE_ENCRYPTION: true
  },
  
  // API Key - should be set via environment variable
  getApiKey() {
    const apiKey = process.env.I2P_BRIDGE_API_KEY;
    if (!apiKey) {
      throw new Error('I2P_BRIDGE_API_KEY environment variable is required');
    }
    return apiKey;
  }
};