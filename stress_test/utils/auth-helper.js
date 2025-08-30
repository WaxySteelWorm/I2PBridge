// Authentication helper for stress testing

const axios = require('axios');
const config = require('../config');

class AuthHelper {
  constructor() {
    this.tokenCache = new Map();
    this.tokenExpiry = new Map();
  }

  /**
   * Get or create JWT token for a user
   * @param {string} userId - Unique identifier for the test user
   * @returns {Promise<string>} JWT token
   */
  async getToken(userId = 'default') {
    // Check if we have a valid cached token
    if (this.isTokenValid(userId)) {
      return this.tokenCache.get(userId);
    }

    try {
      console.log(`🔄 AUTH: Authenticating user ${userId}...`);
      
      const response = await axios.post(
        `https://${config.BRIDGE_HOST}${config.ENDPOINTS.AUTH}`,
        {
          apiKey: config.getApiKey()
        },
        {
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': config.SECURITY.USER_AGENT
          },
          timeout: config.TIMINGS.REQUEST_TIMEOUT
        }
      );

      if (response.status === 200) {
        const { token, expiresIn } = response.data;
        
        // Parse expiry (assuming format like "24h")
        const hours = parseInt(expiresIn.replace('h', ''));
        const expiry = new Date(Date.now() + (hours * 60 * 60 * 1000));
        
        // Cache the token
        this.tokenCache.set(userId, token);
        this.tokenExpiry.set(userId, expiry);
        
        console.log(`✅ AUTH: User ${userId} authenticated successfully`);
        return token;
      } else {
        throw new Error(`Authentication failed: ${response.status}`);
      }
    } catch (error) {
      console.error(`❌ AUTH: Authentication failed for user ${userId}:`, error.message);
      throw error;
    }
  }

  /**
   * Check if cached token is still valid
   * @param {string} userId - User identifier
   * @returns {boolean} True if token is valid
   */
  isTokenValid(userId) {
    const token = this.tokenCache.get(userId);
    const expiry = this.tokenExpiry.get(userId);
    
    if (!token || !expiry) {
      return false;
    }
    
    // Check if token expires within 5 minutes (buffer)
    const fiveMinutesFromNow = new Date(Date.now() + (5 * 60 * 1000));
    return expiry > fiveMinutesFromNow;
  }

  /**
   * Get authentication headers for API requests
   * @param {string} userId - User identifier
   * @returns {Promise<Object>} Headers object
   */
  async getAuthHeaders(userId = 'default') {
    const token = await this.getToken(userId);
    
    return {
      'Authorization': `Bearer ${token}`,
      'User-Agent': config.SECURITY.USER_AGENT,
      'X-Requested-With': 'I2PBridge-StressTest'
    };
  }

  /**
   * Clear all cached tokens
   */
  clearCache() {
    this.tokenCache.clear();
    this.tokenExpiry.clear();
    console.log('🔄 AUTH: Token cache cleared');
  }

  /**
   * Get cache statistics
   * @returns {Object} Cache stats
   */
  getCacheStats() {
    return {
      cachedTokens: this.tokenCache.size,
      validTokens: Array.from(this.tokenCache.keys()).filter(userId => this.isTokenValid(userId)).length
    };
  }
}

module.exports = AuthHelper;