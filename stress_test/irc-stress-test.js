// IRC stress test for I2P Bridge

const WebSocket = require('ws');
const crypto = require('crypto');
const yargs = require('yargs');
const colors = require('colors');
const AuthHelper = require('./utils/auth-helper');
const config = require('./config');

class IrcStressTest {
  constructor(options = {}) {
    this.users = options.users || 10;
    this.duration = options.duration || 120; // seconds
    this.verbose = options.verbose || false;
    
    this.authHelper = new AuthHelper();
    this.metrics = {
      totalConnections: 0,
      successfulConnections: 0,
      failedConnections: 0,
      totalMessages: 0,
      successfulMessages: 0,
      failedMessages: 0,
      connectionTimes: [],
      messageTimes: [],
      errors: {},
      startTime: null,
      endTime: null
    };
    
    this.activeConnections = [];
    this.isRunning = false;
  }

  /**
   * Generate random IRC nickname
   */
  generateNickname(userId) {
    const prefixes = ['test', 'user', 'guest', 'anon', 'stress'];
    const prefix = prefixes[Math.floor(Math.random() * prefixes.length)];
    return `${prefix}${userId}_${Math.floor(Math.random() * 1000)}`;
  }

  /**
   * Generate random IRC messages
   */
  getRandomMessage() {
    const messages = [
      'Hello everyone!',
      'How is everyone doing?',
      'This is a stress test message',
      'Testing IRC functionality',
      'Anonymous messaging test',
      'Bridge connection test',
      'Performance testing in progress',
      'I2P network is working well',
      'Secure communication test',
      'Load testing the bridge'
    ];
    return messages[Math.floor(Math.random() * messages.length)];
  }

  /**
   * Get random IRC channel
   */
  getRandomChannel() {
    return config.IRC_CHANNELS[Math.floor(Math.random() * config.IRC_CHANNELS.length)];
  }

  /**
   * AES encryption (matching Flutter implementation)
   */
  encryptMessage(message, key, iv) {
    try {
      const cipher = crypto.createCipher('aes-256-cbc', key);
      let encrypted = cipher.update(message, 'utf8', 'base64');
      encrypted += cipher.final('base64');
      return encrypted;
    } catch (error) {
      console.error('Encryption error:', error);
      return message; // Fallback to unencrypted
    }
  }

  /**
   * Simulate a single IRC user session
   */
  async simulateIrcUser(userId, testDuration) {
    const nickname = this.generateNickname(userId);
    const channel = this.getRandomChannel();
    const startTime = Date.now();
    
    let ws = null;
    let sessionKey = null;
    let sessionIV = null;
    let encryptionReady = false;
    let registrationComplete = false;
    let hasJoinedChannel = false;
    
    const userMetrics = {
      messages: 0,
      errors: 0,
      connectionTime: null
    };

    try {
      // Create WebSocket connection
      const connectionStart = Date.now();
      this.metrics.totalConnections++;
      
      if (this.verbose) {
        console.log(`🔌 User ${userId} (${nickname}): Connecting to IRC...`);
      }

      ws = new WebSocket(config.IRC_WEBSOCKET_URL, {
        headers: {
          'User-Agent': config.SECURITY.USER_AGENT
        },
        timeout: config.TIMINGS.CONNECTION_TIMEOUT
      });

      // Handle connection establishment
      await new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          reject(new Error('Connection timeout'));
        }, config.TIMINGS.CONNECTION_TIMEOUT);

        ws.on('open', () => {
          clearTimeout(timeout);
          const connectionTime = Date.now() - connectionStart;
          userMetrics.connectionTime = connectionTime;
          this.metrics.connectionTimes.push(connectionTime);
          this.metrics.successfulConnections++;
          
          if (this.verbose) {
            console.log(`✅ User ${userId} (${nickname}): Connected (${connectionTime}ms)`.green);
          }
          resolve();
        });

        ws.on('error', (error) => {
          clearTimeout(timeout);
          this.metrics.failedConnections++;
          reject(error);
        });
      });

      // Handle messages
      ws.on('message', (data) => {
        try {
          const jsonData = JSON.parse(data);
          
          // Handle encryption initialization
          if (jsonData.type === 'encryption_init') {
            sessionKey = Buffer.from(jsonData.key, 'base64');
            sessionIV = Buffer.from(jsonData.iv, 'base64');
            encryptionReady = true;
            
            // Send acknowledgment
            ws.send(JSON.stringify({
              type: 'encryption_ack'
            }));
            
            if (this.verbose) {
              console.log(`🔒 User ${userId} (${nickname}): Encryption established`);
            }
            
            // Send IRC registration
            this.sendEncryptedMessage(ws, `NICK ${nickname}`, sessionKey, sessionIV);
            this.sendEncryptedMessage(ws, `USER ${nickname} 0 * :Stress Test User`, sessionKey, sessionIV);
          }
          
          // Handle encrypted IRC messages
          if (jsonData.type === 'irc_message' && jsonData.encrypted === true) {
            const decrypted = this.decryptMessage(jsonData.data, sessionKey, sessionIV);
            const lines = decrypted.split('\r\n');
            
            for (const line of lines) {
              if (line.includes(' 001 ') || line.includes(' 376 ') || line.includes(' 422 ')) {
                // Registration complete
                registrationComplete = true;
                
                if (this.verbose) {
                  console.log(`✅ User ${userId} (${nickname}): Registered successfully`);
                }
                
                // Wait required time then join channel
                setTimeout(() => {
                  if (encryptionReady && !hasJoinedChannel) {
                    hasJoinedChannel = true;
                    this.sendEncryptedMessage(ws, `JOIN ${channel}`, sessionKey, sessionIV);
                    
                    if (this.verbose) {
                      console.log(`📝 User ${userId} (${nickname}): Joined ${channel}`);
                    }
                  }
                }, config.TIMINGS.IRC_REGISTRATION_DELAY);
              }
              
              // Handle PING
              if (line.startsWith('PING')) {
                const pongResponse = line.replace('PING', 'PONG');
                this.sendEncryptedMessage(ws, pongResponse, sessionKey, sessionIV);
              }
            }
          }
        } catch (error) {
          if (this.verbose) {
            console.log(`⚠️ User ${userId} (${nickname}): Message parsing error:`, error.message);
          }
        }
      });

      // Start message sending loop after initial delays
      setTimeout(async () => {
        while (this.isRunning && ws.readyState === WebSocket.OPEN && 
               (Date.now() - startTime) < testDuration * 1000) {
          
          if (encryptionReady && registrationComplete && hasJoinedChannel) {
            try {
              const messageStart = Date.now();
              const message = this.getRandomMessage();
              
              this.sendEncryptedMessage(ws, `PRIVMSG ${channel} :${message}`, sessionKey, sessionIV);
              
              const messageTime = Date.now() - messageStart;
              this.metrics.totalMessages++;
              this.metrics.successfulMessages++;
              userMetrics.messages++;
              this.metrics.messageTimes.push(messageTime);
              
              if (this.verbose) {
                console.log(`💬 User ${userId} (${nickname}): Sent message to ${channel}`.blue);
              }
              
            } catch (error) {
              this.metrics.totalMessages++;
              this.metrics.failedMessages++;
              userMetrics.errors++;
              
              if (this.verbose) {
                console.log(`❌ User ${userId} (${nickname}): Message failed:`, error.message);
              }
            }
          }
          
          // Random delay between messages (5-15 seconds)
          const delay = 5000 + Math.random() * 10000;
          await this.sleep(delay);
        }
      }, config.TIMINGS.IRC_REGISTRATION_DELAY + 2000);

      // Keep connection alive for test duration
      await this.sleep(testDuration * 1000);
      
    } catch (error) {
      this.metrics.failedConnections++;
      userMetrics.errors++;
      
      const errorType = error.code || 'connection_error';
      this.metrics.errors[errorType] = (this.metrics.errors[errorType] || 0) + 1;
      
      console.log(`❌ User ${userId} (${nickname}): Connection failed -`, error.message);
    } finally {
      if (ws && ws.readyState === WebSocket.OPEN) {
        // Send quit message
        if (encryptionReady) {
          this.sendEncryptedMessage(ws, 'QUIT :Stress test complete', sessionKey, sessionIV);
        }
        ws.close();
      }
      
      console.log(`👤 User ${userId} (${nickname}) completed: ${userMetrics.messages} messages, ${userMetrics.errors} errors`);
    }
  }

  /**
   * Send encrypted IRC message
   */
  sendEncryptedMessage(ws, message, key, iv) {
    if (!key || !iv) {
      return;
    }
    
    try {
      const encrypted = this.encryptMessage(message, key, iv);
      ws.send(JSON.stringify({
        encrypted: true,
        data: encrypted
      }));
    } catch (error) {
      console.error('Failed to send encrypted message:', error);
    }
  }

  /**
   * Decrypt IRC message (placeholder - simplified for testing)
   */
  decryptMessage(encryptedData, key, iv) {
    try {
      const decipher = crypto.createDecipher('aes-256-cbc', key);
      let decrypted = decipher.update(encryptedData, 'base64', 'utf8');
      decrypted += decipher.final('utf8');
      return decrypted;
    } catch (error) {
      return '[Decryption Error]';
    }
  }

  /**
   * Sleep for specified milliseconds
   */
  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * Calculate IRC-specific statistics
   */
  calculateStats() {
    const totalDuration = (this.metrics.endTime - this.metrics.startTime) / 1000;
    const { connectionTimes, messageTimes } = this.metrics;
    
    const stats = {
      totalConnections: this.metrics.totalConnections,
      successfulConnections: this.metrics.successfulConnections,
      failedConnections: this.metrics.failedConnections,
      connectionSuccessRate: this.metrics.totalConnections > 0 ? 
        this.metrics.successfulConnections / this.metrics.totalConnections : 0,
      totalMessages: this.metrics.totalMessages,
      successfulMessages: this.metrics.successfulMessages,
      failedMessages: this.metrics.failedMessages,
      messageSuccessRate: this.metrics.totalMessages > 0 ? 
        this.metrics.successfulMessages / this.metrics.totalMessages : 0,
      messageThroughput: this.metrics.totalMessages / totalDuration,
      duration: totalDuration,
      errors: this.metrics.errors
    };

    if (connectionTimes.length > 0) {
      connectionTimes.sort((a, b) => a - b);
      stats.connectionTime = {
        min: Math.min(...connectionTimes),
        max: Math.max(...connectionTimes),
        avg: connectionTimes.reduce((a, b) => a + b, 0) / connectionTimes.length,
        p95: connectionTimes[Math.floor(connectionTimes.length * 0.95)]
      };
    }

    if (messageTimes.length > 0) {
      messageTimes.sort((a, b) => a - b);
      stats.messageTime = {
        min: Math.min(...messageTimes),
        max: Math.max(...messageTimes),
        avg: messageTimes.reduce((a, b) => a + b, 0) / messageTimes.length,
        p95: messageTimes[Math.floor(messageTimes.length * 0.95)]
      };
    }

    return stats;
  }

  /**
   * Print IRC test results
   */
  printResults() {
    const stats = this.calculateStats();
    
    console.log('\n' + '='.repeat(60).cyan);
    console.log('📊 IRC STRESS TEST RESULTS'.cyan.bold);
    console.log('='.repeat(60).cyan);
    
    console.log(`👥 Concurrent Users: ${this.users}`);
    console.log(`⏱️  Test Duration: ${stats.duration.toFixed(1)}s`);
    
    console.log('\n🔌 Connection Metrics:');
    console.log(`   Total Attempts: ${stats.totalConnections}`);
    console.log(`   Successful: ${stats.successfulConnections} (${(stats.connectionSuccessRate*100).toFixed(1)}%)`);
    console.log(`   Failed: ${stats.failedConnections}`);
    
    if (stats.connectionTime) {
      console.log(`   Connection Time - Avg: ${stats.connectionTime.avg.toFixed(0)}ms, P95: ${stats.connectionTime.p95}ms`);
    }
    
    console.log('\n💬 Message Metrics:');
    console.log(`   Total Messages: ${stats.totalMessages}`);
    console.log(`   Successful: ${stats.successfulMessages} (${(stats.messageSuccessRate*100).toFixed(1)}%)`);
    console.log(`   Failed: ${stats.failedMessages}`);
    console.log(`   Throughput: ${stats.messageThroughput.toFixed(2)} messages/s`);
    
    if (stats.messageTime) {
      console.log(`   Message Time - Avg: ${stats.messageTime.avg.toFixed(0)}ms, P95: ${stats.messageTime.p95}ms`);
    }
    
    if (Object.keys(stats.errors).length > 0) {
      console.log('\n❌ Error Breakdown:');
      for (const [errorType, count] of Object.entries(stats.errors)) {
        console.log(`   ${errorType}: ${count}`);
      }
    }

    // Performance assessment
    console.log('\n🎯 Performance Assessment:');
    if (stats.connectionSuccessRate < 0.95) {
      console.log(`   ❌ Low connection success rate: ${(stats.connectionSuccessRate*100).toFixed(1)}%`.red);
    } else {
      console.log(`   ✅ Connection success rate acceptable: ${(stats.connectionSuccessRate*100).toFixed(1)}%`.green);
    }
    
    if (stats.messageSuccessRate < 0.95) {
      console.log(`   ❌ Low message success rate: ${(stats.messageSuccessRate*100).toFixed(1)}%`.red);
    } else {
      console.log(`   ✅ Message success rate acceptable: ${(stats.messageSuccessRate*100).toFixed(1)}%`.green);
    }
  }

  /**
   * Run the IRC stress test
   */
  async run() {
    console.log('🚀 Starting IRC Stress Test'.cyan.bold);
    console.log(`👥 Users: ${this.users}`);
    console.log(`⏱️  Duration: ${this.duration}s`);
    console.log(`💬 Target Channels: ${config.IRC_CHANNELS.join(', ')}`);
    console.log('');

    this.isRunning = true;
    this.metrics.startTime = Date.now();

    // Start progress indicator
    const progressInterval = setInterval(() => {
      if (this.isRunning) {
        const elapsed = (Date.now() - this.metrics.startTime) / 1000;
        const progress = Math.min(elapsed / this.duration, 1) * 100;
        process.stdout.write(`\r🔄 Progress: ${progress.toFixed(1)}% | Connections: ${this.metrics.successfulConnections}/${this.metrics.totalConnections} | Messages: ${this.metrics.totalMessages}`);
      }
    }, 1000);

    try {
      // Launch concurrent IRC users
      const userPromises = [];
      for (let i = 0; i < this.users; i++) {
        const userPromise = this.simulateIrcUser(i, this.duration);
        userPromises.push(userPromise);
        
        // Stagger connections to avoid overwhelming server
        await this.sleep(200);
      }

      // Wait for all users to complete
      await Promise.all(userPromises);
      
    } finally {
      this.isRunning = false;
      this.metrics.endTime = Date.now();
      clearInterval(progressInterval);
      process.stdout.write('\n');
    }

    this.printResults();
    return this.calculateStats();
  }

  /**
   * Sleep for specified milliseconds
   */
  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}

// CLI interface
if (require.main === module) {
  const argv = yargs
    .option('users', {
      alias: 'u',
      type: 'number',
      default: 10,
      description: 'Number of concurrent IRC users'
    })
    .option('duration', {
      alias: 'd',
      type: 'number',
      default: 120,
      description: 'Test duration in seconds'
    })
    .option('verbose', {
      alias: 'v',
      type: 'boolean',
      default: false,
      description: 'Enable verbose logging'
    })
    .help()
    .argv;

  const test = new IrcStressTest(argv);
  
  test.run().catch(error => {
    console.error('❌ IRC Test failed:', error.message);
    process.exit(1);
  });
}

module.exports = IrcStressTest;