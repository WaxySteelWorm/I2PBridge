// Main orchestrator for running all I2P Bridge stress tests

const yargs = require('yargs');
const colors = require('colors');
const Table = require('cli-table3');
const HttpStressTest = require('./http-stress-test');
const IrcStressTest = require('./irc-stress-test');
const UploadStressTest = require('./upload-stress-test');
const config = require('./config');

class TestOrchestrator {
  constructor(options = {}) {
    this.users = options.users || config.DEFAULT_CONCURRENT_USERS;
    this.duration = options.duration || config.DEFAULT_TEST_DURATION;
    this.verbose = options.verbose || false;
    this.testTypes = options.tests || ['http', 'irc', 'upload'];
    
    this.results = {};
    this.startTime = null;
    this.endTime = null;
  }

  /**
   * Validate environment and configuration
   */
  async validateEnvironment() {
    console.log('🔍 Validating test environment...'.yellow);
    
    try {
      // Check API key
      const apiKey = config.getApiKey();
      console.log(`✅ API key configured: ${apiKey.substring(0, 8)}...`);
      
      // Test basic connectivity
      const axios = require('axios');
      const response = await axios.get(`https://${config.BRIDGE_HOST}${config.ENDPOINTS.DEBUG}`, {
        timeout: 5000,
        validateStatus: (status) => status < 500 // Accept 401/403 as valid connectivity
      });
      
      console.log(`✅ Bridge server connectivity: ${response.status}`);
      
    } catch (error) {
      console.error(`❌ Environment validation failed: ${error.message}`.red);
      throw error;
    }
  }

  /**
   * Run HTTP browsing stress test
   */
  async runHttpTest() {
    console.log('\n🌐 Starting HTTP Browsing Test...'.blue.bold);
    
    const httpTest = new HttpStressTest({
      users: Math.floor(this.users * 0.6), // 60% of users for HTTP
      duration: this.duration,
      verbose: this.verbose
    });
    
    this.results.http = await httpTest.run();
  }

  /**
   * Run IRC stress test
   */
  async runIrcTest() {
    console.log('\n💬 Starting IRC Test...'.green.bold);
    
    const ircTest = new IrcStressTest({
      users: Math.floor(this.users * 0.3), // 30% of users for IRC
      duration: this.duration,
      verbose: this.verbose
    });
    
    this.results.irc = await ircTest.run();
  }

  /**
   * Run upload stress test
   */
  async runUploadTest() {
    console.log('\n📤 Starting Upload Test...'.magenta.bold);
    
    const uploadTest = new UploadStressTest({
      users: Math.floor(this.users * 0.1), // 10% of users for uploads
      duration: this.duration,
      verbose: this.verbose
    });
    
    this.results.upload = await uploadTest.run();
  }

  /**
   * Generate comprehensive test report
   */
  generateReport() {
    console.log('\n' + '='.repeat(80).cyan);
    console.log('📋 COMPREHENSIVE STRESS TEST REPORT'.cyan.bold);
    console.log('='.repeat(80).cyan);
    
    const totalDuration = (this.endTime - this.startTime) / 1000;
    console.log(`⏱️  Total Test Duration: ${totalDuration.toFixed(1)}s`);
    console.log(`👥 Target Concurrent Users: ${this.users}`);
    console.log(`🧪 Tests Executed: ${this.testTypes.join(', ')}`);
    
    // Create results table
    const table = new Table({
      head: ['Service', 'Requests', 'Success Rate', 'Avg Response', 'P95 Response', 'Throughput', 'Status'],
      style: { head: ['cyan'] }
    });

    let overallStatus = '✅ PASS';
    
    // HTTP results
    if (this.results.http) {
      const http = this.results.http;
      const successRate = (http.successfulRequests / http.totalRequests * 100).toFixed(1);
      const avgResponse = http.responseTime ? `${http.responseTime.avg.toFixed(0)}ms` : 'N/A';
      const p95Response = http.responseTime ? `${http.responseTime.p95}ms` : 'N/A';
      const throughput = `${http.throughput.toFixed(1)} req/s`;
      
      let status = '✅ PASS';
      if (http.errorRate > config.THRESHOLDS.MAX_ERROR_RATE) {
        status = '❌ FAIL (High Error Rate)';
        overallStatus = '❌ FAIL';
      } else if (http.responseTime?.p95 > config.THRESHOLDS.MAX_RESPONSE_TIME) {
        status = '⚠️ WARN (Slow Response)';
        if (overallStatus === '✅ PASS') overallStatus = '⚠️ WARN';
      }
      
      table.push(['HTTP Browse', http.totalRequests, `${successRate}%`, avgResponse, p95Response, throughput, status]);
    }

    // IRC results
    if (this.results.irc) {
      const irc = this.results.irc;
      const connectionRate = (irc.connectionSuccessRate * 100).toFixed(1);
      const messageRate = (irc.messageSuccessRate * 100).toFixed(1);
      const avgConnection = irc.connectionTime ? `${irc.connectionTime.avg.toFixed(0)}ms` : 'N/A';
      const throughput = `${irc.messageThroughput.toFixed(1)} msg/s`;
      
      let status = '✅ PASS';
      if (irc.connectionSuccessRate < 0.95 || irc.messageSuccessRate < 0.95) {
        status = '❌ FAIL (Low Success Rate)';
        overallStatus = '❌ FAIL';
      }
      
      table.push(['IRC', `${irc.totalConnections} conn`, `${connectionRate}% conn`, avgConnection, 'N/A', throughput, status]);
      table.push(['', `${irc.totalMessages} msg`, `${messageRate}% msg`, '', '', '', '']);
    }

    // Upload results
    if (this.results.upload) {
      const upload = this.results.upload;
      const successRate = (upload.successfulUploads / upload.totalUploads * 100).toFixed(1);
      const avgUpload = upload.uploadTime ? `${(upload.uploadTime.avg/1000).toFixed(1)}s` : 'N/A';
      const p95Upload = upload.uploadTime ? `${(upload.uploadTime.p95/1000).toFixed(1)}s` : 'N/A';
      const throughput = `${upload.throughput.toFixed(2)} up/s`;
      
      let status = '✅ PASS';
      if (upload.errorRate > config.THRESHOLDS.MAX_ERROR_RATE) {
        status = '❌ FAIL (High Error Rate)';
        overallStatus = '❌ FAIL';
      } else if (upload.uploadTime?.p95 > config.THRESHOLDS.MAX_RESPONSE_TIME) {
        status = '⚠️ WARN (Slow Uploads)';
        if (overallStatus === '✅ PASS') overallStatus = '⚠️ WARN';
      }
      
      table.push(['Upload', upload.totalUploads, `${successRate}%`, avgUpload, p95Upload, throughput, status]);
    }

    console.log(table.toString());
    
    // Overall assessment
    console.log(`\n🎯 Overall Status: ${overallStatus}`.bold);
    
    if (overallStatus === '✅ PASS') {
      console.log('🎉 All systems performed well under stress test conditions!'.green);
    } else if (overallStatus === '⚠️ WARN') {
      console.log('⚠️ Some performance concerns detected. Review slow response times.'.yellow);
    } else {
      console.log('❌ Critical issues detected. Review error rates and failed requests.'.red);
    }

    // Recommendations
    console.log('\n💡 Recommendations:');
    if (this.results.http?.errorRate > 0.02) {
      console.log('   • Investigate HTTP browsing errors and server capacity');
    }
    if (this.results.irc?.connectionSuccessRate < 0.98) {
      console.log('   • Review IRC WebSocket connection handling and limits');
    }
    if (this.results.upload?.errorRate > 0.05) {
      console.log('   • Check upload service capacity and file handling');
    }
    
    const maxResponseTime = Math.max(
      this.results.http?.responseTime?.p95 || 0,
      this.results.upload?.uploadTime?.p95 || 0
    );
    
    if (maxResponseTime > config.THRESHOLDS.MAX_RESPONSE_TIME) {
      console.log('   • Consider scaling bridge server or optimizing request handling');
    }
  }

  /**
   * Run all stress tests
   */
  async run() {
    console.log('🎯 I2P Bridge Comprehensive Stress Test'.rainbow.bold);
    console.log(`📅 Started at: ${new Date().toISOString()}`);
    console.log('');

    this.startTime = Date.now();

    try {
      // Validate environment first
      await this.validateEnvironment();
      
      // Run selected tests
      if (this.testTypes.includes('http')) {
        await this.runHttpTest();
      }
      
      if (this.testTypes.includes('irc')) {
        await this.runIrcTest();
      }
      
      if (this.testTypes.includes('upload')) {
        await this.runUploadTest();
      }
      
    } catch (error) {
      console.error(`❌ Test orchestration failed: ${error.message}`.red);
      process.exit(1);
    } finally {
      this.endTime = Date.now();
    }

    // Generate comprehensive report
    this.generateReport();
    
    console.log(`\n📅 Completed at: ${new Date().toISOString()}`);
    return this.results;
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
      default: config.DEFAULT_CONCURRENT_USERS,
      description: 'Number of concurrent users'
    })
    .option('duration', {
      alias: 'd',
      type: 'number',
      default: config.DEFAULT_TEST_DURATION,
      description: 'Test duration in seconds'
    })
    .option('tests', {
      alias: 't',
      type: 'array',
      default: ['http', 'irc', 'upload'],
      choices: ['http', 'irc', 'upload'],
      description: 'Tests to run'
    })
    .option('verbose', {
      alias: 'v',
      type: 'boolean',
      default: false,
      description: 'Enable verbose logging'
    })
    .help()
    .example('$0 --users=50 --duration=120', 'Run all tests with 50 users for 2 minutes')
    .example('$0 --tests=http --users=100', 'Run only HTTP test with 100 users')
    .argv;

  const orchestrator = new TestOrchestrator(argv);
  
  orchestrator.run().catch(error => {
    console.error('❌ Stress test failed:', error.message);
    process.exit(1);
  });
}

module.exports = TestOrchestrator;