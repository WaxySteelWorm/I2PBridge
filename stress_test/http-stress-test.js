// HTTP browsing stress test for I2P Bridge

const axios = require('axios');
const crypto = require('crypto');
const yargs = require('yargs');
const colors = require('colors');
const AuthHelper = require('./utils/auth-helper');
const config = require('./config');

class HttpStressTest {
  constructor(options = {}) {
    this.users = options.users || 10;
    this.duration = options.duration || 60; // seconds
    this.verbose = options.verbose || false;
    
    this.authHelper = new AuthHelper();
    this.metrics = {
      totalRequests: 0,
      successfulRequests: 0,
      failedRequests: 0,
      responseTimes: [],
      errors: {},
      startTime: null,
      endTime: null
    };
    
    this.activeUsers = [];
    this.isRunning = false;
  }

  /**
   * Generate a random I2P URL for testing
   */
  getRandomI2pUrl() {
    const sites = config.I2P_SITES;
    const randomSite = sites[Math.floor(Math.random() * sites.length)];
    
    // Sometimes add paths for more realistic browsing
    const paths = ['', '/', '/index.html', '/about', '/forum', '/search'];
    const randomPath = paths[Math.floor(Math.random() * paths.length)];
    
    return `http://${randomSite}${randomPath}`;
  }

  /**
   * Generate search queries for shinobi.i2p
   */
  getRandomSearchQuery() {
    const queries = [
      'i2p tutorial',
      'privacy tools',
      'anonymous browsing',
      'secure communication',
      'darknet markets',
      'encryption',
      'torrent sites',
      'forums'
    ];
    return queries[Math.floor(Math.random() * queries.length)];
  }

  /**
   * Simulate a single user's browsing session
   */
  async simulateUser(userId, testDuration) {
    const startTime = Date.now();
    const userMetrics = {
      requests: 0,
      errors: 0,
      responseTimes: []
    };

    try {
      // Authenticate user
      await this.authHelper.getToken(`user-${userId}`);
      
      while (this.isRunning && (Date.now() - startTime) < testDuration * 1000) {
        try {
          const requestStart = Date.now();
          
          // Choose between browsing and searching
          let targetUrl;
          if (Math.random() < 0.3) {
            // 30% chance of doing a search
            const query = this.getRandomSearchQuery();
            targetUrl = `http://shinobi.i2p/search?query=${encodeURIComponent(query)}`;
          } else {
            // 70% chance of browsing a site
            targetUrl = this.getRandomI2pUrl();
          }

          // Get authentication headers
          const headers = await this.authHelper.getAuthHeaders(`user-${userId}`);
          
          // Make request to bridge server
          const response = await axios.get(
            `https://${config.BRIDGE_HOST}${config.ENDPOINTS.BROWSE}`,
            {
              params: { url: targetUrl },
              headers: {
                ...headers,
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                'Accept-Language': 'en-US,en;q=0.5',
                'Accept-Encoding': 'gzip, deflate',
                'Connection': 'keep-alive',
                'DNT': '1'
              },
              timeout: config.TIMINGS.REQUEST_TIMEOUT
            }
          );

          const responseTime = Date.now() - requestStart;
          
          // Record metrics
          this.metrics.totalRequests++;
          userMetrics.requests++;
          
          if (response.status === 200) {
            this.metrics.successfulRequests++;
            this.metrics.responseTimes.push(responseTime);
            userMetrics.responseTimes.push(responseTime);
            
            if (this.verbose) {
              console.log(`✅ User ${userId}: ${targetUrl} (${responseTime}ms)`.green);
            }
          } else {
            this.metrics.failedRequests++;
            userMetrics.errors++;
            console.log(`⚠️ User ${userId}: ${targetUrl} failed with status ${response.status}`.yellow);
          }

          // Random delay between requests (1-3 seconds)
          const delay = 1000 + Math.random() * 2000;
          await this.sleep(delay);
          
        } catch (error) {
          this.metrics.totalRequests++;
          this.metrics.failedRequests++;
          userMetrics.errors++;
          
          const errorType = error.code || error.response?.status || 'unknown';
          this.metrics.errors[errorType] = (this.metrics.errors[errorType] || 0) + 1;
          
          if (this.verbose) {
            console.log(`❌ User ${userId}: Request failed - ${error.message}`.red);
          }
          
          // Shorter delay on error
          await this.sleep(1000);
        }
      }
      
      console.log(`👤 User ${userId} completed: ${userMetrics.requests} requests, ${userMetrics.errors} errors`);
      
    } catch (error) {
      console.error(`❌ User ${userId} failed to start:`, error.message);
    }
  }

  /**
   * Sleep for specified milliseconds
   */
  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * Calculate performance statistics
   */
  calculateStats() {
    const { responseTimes } = this.metrics;
    const totalDuration = (this.metrics.endTime - this.metrics.startTime) / 1000;
    
    if (responseTimes.length === 0) {
      return {
        totalRequests: this.metrics.totalRequests,
        successfulRequests: this.metrics.successfulRequests,
        failedRequests: this.metrics.failedRequests,
        errorRate: this.metrics.totalRequests > 0 ? this.metrics.failedRequests / this.metrics.totalRequests : 0,
        throughput: this.metrics.totalRequests / totalDuration,
        duration: totalDuration,
        errors: this.metrics.errors
      };
    }
    
    responseTimes.sort((a, b) => a - b);
    
    return {
      totalRequests: this.metrics.totalRequests,
      successfulRequests: this.metrics.successfulRequests,
      failedRequests: this.metrics.failedRequests,
      errorRate: this.metrics.totalRequests > 0 ? this.metrics.failedRequests / this.metrics.totalRequests : 0,
      throughput: this.metrics.totalRequests / totalDuration,
      responseTime: {
        min: Math.min(...responseTimes),
        max: Math.max(...responseTimes),
        avg: responseTimes.reduce((a, b) => a + b, 0) / responseTimes.length,
        p50: responseTimes[Math.floor(responseTimes.length * 0.5)],
        p95: responseTimes[Math.floor(responseTimes.length * 0.95)],
        p99: responseTimes[Math.floor(responseTimes.length * 0.99)]
      },
      duration: totalDuration,
      errors: this.metrics.errors
    };
  }

  /**
   * Print test results
   */
  printResults() {
    const stats = this.calculateStats();
    
    console.log('\n' + '='.repeat(60).cyan);
    console.log('📊 HTTP BROWSING STRESS TEST RESULTS'.cyan.bold);
    console.log('='.repeat(60).cyan);
    
    console.log(`👥 Concurrent Users: ${this.users}`);
    console.log(`⏱️  Test Duration: ${stats.duration.toFixed(1)}s`);
    console.log(`📈 Total Requests: ${stats.totalRequests}`);
    console.log(`✅ Successful: ${stats.successfulRequests} (${((stats.successfulRequests/stats.totalRequests)*100).toFixed(1)}%)`);
    console.log(`❌ Failed: ${stats.failedRequests} (${(stats.errorRate*100).toFixed(1)}%)`);
    console.log(`🚀 Throughput: ${stats.throughput.toFixed(2)} req/s`);
    
    if (stats.responseTime) {
      console.log('\n📊 Response Times:');
      console.log(`   Min: ${stats.responseTime.min}ms`);
      console.log(`   Avg: ${stats.responseTime.avg.toFixed(0)}ms`);
      console.log(`   Max: ${stats.responseTime.max}ms`);
      console.log(`   P50: ${stats.responseTime.p50}ms`);
      console.log(`   P95: ${stats.responseTime.p95}ms`);
      console.log(`   P99: ${stats.responseTime.p99}ms`);
    }
    
    if (Object.keys(stats.errors).length > 0) {
      console.log('\n❌ Error Breakdown:');
      for (const [errorType, count] of Object.entries(stats.errors)) {
        console.log(`   ${errorType}: ${count}`);
      }
    }

    // Performance assessment
    console.log('\n🎯 Performance Assessment:');
    if (stats.errorRate > config.THRESHOLDS.MAX_ERROR_RATE) {
      console.log(`   ❌ High error rate: ${(stats.errorRate*100).toFixed(1)}% (threshold: ${config.THRESHOLDS.MAX_ERROR_RATE*100}%)`.red);
    } else {
      console.log(`   ✅ Error rate acceptable: ${(stats.errorRate*100).toFixed(1)}%`.green);
    }
    
    if (stats.responseTime && stats.responseTime.p95 > config.THRESHOLDS.MAX_RESPONSE_TIME) {
      console.log(`   ❌ Slow response times: P95 ${stats.responseTime.p95}ms (threshold: ${config.THRESHOLDS.MAX_RESPONSE_TIME}ms)`.red);
    } else if (stats.responseTime) {
      console.log(`   ✅ Response times acceptable: P95 ${stats.responseTime.p95}ms`.green);
    }
    
    if (stats.throughput < config.THRESHOLDS.MIN_THROUGHPUT) {
      console.log(`   ⚠️  Low throughput: ${stats.throughput.toFixed(2)} req/s (threshold: ${config.THRESHOLDS.MIN_THROUGHPUT} req/s)`.yellow);
    } else {
      console.log(`   ✅ Throughput acceptable: ${stats.throughput.toFixed(2)} req/s`.green);
    }
  }

  /**
   * Run the HTTP stress test
   */
  async run() {
    console.log('🚀 Starting HTTP Browsing Stress Test'.cyan.bold);
    console.log(`👥 Users: ${this.users}`);
    console.log(`⏱️  Duration: ${this.duration}s`);
    console.log(`🌐 Target Sites: ${config.I2P_SITES.join(', ')}`);
    console.log('');

    this.isRunning = true;
    this.metrics.startTime = Date.now();

    // Start progress indicator
    const progressInterval = setInterval(() => {
      if (this.isRunning) {
        const elapsed = (Date.now() - this.metrics.startTime) / 1000;
        const progress = Math.min(elapsed / this.duration, 1) * 100;
        process.stdout.write(`\r🔄 Progress: ${progress.toFixed(1)}% | Requests: ${this.metrics.totalRequests} | Errors: ${this.metrics.failedRequests}`);
      }
    }, 1000);

    try {
      // Launch concurrent users
      const userPromises = [];
      for (let i = 0; i < this.users; i++) {
        const userPromise = this.simulateUser(i, this.duration);
        userPromises.push(userPromise);
        
        // Stagger user start times slightly
        await this.sleep(50);
      }

      // Wait for all users to complete or timeout
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
}

// CLI interface
if (require.main === module) {
  const argv = yargs
    .option('users', {
      alias: 'u',
      type: 'number',
      default: 10,
      description: 'Number of concurrent users'
    })
    .option('duration', {
      alias: 'd', 
      type: 'number',
      default: 60,
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

  const test = new HttpStressTest(argv);
  
  test.run().catch(error => {
    console.error('❌ Test failed:', error.message);
    process.exit(1);
  });
}

module.exports = HttpStressTest;