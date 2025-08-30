// Upload stress test for I2P Bridge

const axios = require('axios');
const FormData = require('form-data');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const yargs = require('yargs');
const colors = require('colors');
const AuthHelper = require('./utils/auth-helper');
const config = require('./config');

class UploadStressTest {
  constructor(options = {}) {
    this.users = options.users || 5;
    this.duration = options.duration || 60; // seconds
    this.verbose = options.verbose || false;
    
    this.authHelper = new AuthHelper();
    this.metrics = {
      totalUploads: 0,
      successfulUploads: 0,
      failedUploads: 0,
      uploadTimes: [],
      filesCreated: [],
      errors: {},
      startTime: null,
      endTime: null
    };
    
    this.isRunning = false;
    this.testFilesDir = path.join(__dirname, 'test-files');
  }

  /**
   * Create test directory and generate test files
   */
  async setupTestFiles() {
    try {
      // Create test files directory
      if (!fs.existsSync(this.testFilesDir)) {
        fs.mkdirSync(this.testFilesDir, { recursive: true });
      }

      console.log(`📁 Creating test files in ${this.testFilesDir}...`);

      // Generate test images of various sizes
      for (const size of config.UPLOAD_FILE_SIZES) {
        const filename = `test-image-${size}.jpg`;
        const filepath = path.join(this.testFilesDir, filename);
        
        if (!fs.existsSync(filepath)) {
          // Create a simple test image file (JPEG-like structure)
          const buffer = this.generateTestImageBuffer(size);
          fs.writeFileSync(filepath, buffer);
          this.metrics.filesCreated.push(filepath);
          
          if (this.verbose) {
            console.log(`📄 Created test file: ${filename} (${size} bytes)`);
          }
        }
      }

      console.log(`✅ Test files ready: ${this.metrics.filesCreated.length} files created`);

    } catch (error) {
      console.error('❌ Failed to setup test files:', error.message);
      throw error;
    }
  }

  /**
   * Generate a test image buffer of specified size
   */
  generateTestImageBuffer(targetSize) {
    // Create a minimal JPEG-like header
    const jpegHeader = Buffer.from([
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
      0x01, 0x01, 0x00, 0x48, 0x00, 0x48, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43
    ]);
    
    // Fill remaining bytes with random data
    const remainingSize = Math.max(targetSize - jpegHeader.length - 2, 0);
    const randomData = crypto.randomBytes(remainingSize);
    
    // JPEG end marker
    const jpegEnd = Buffer.from([0xFF, 0xD9]);
    
    return Buffer.concat([jpegHeader, randomData, jpegEnd]);
  }

  /**
   * Get random upload parameters
   */
  getRandomUploadParams() {
    const expiries = ['1h', '6h', '24h', '7d', '30d'];
    const maxViews = ['', '10', '50', '100', '500'];
    const passwords = ['', 'test123', 'upload456', ''];
    
    return {
      expiry: expiries[Math.floor(Math.random() * expiries.length)],
      maxViews: maxViews[Math.floor(Math.random() * maxViews.length)],
      password: passwords[Math.floor(Math.random() * passwords.length)]
    };
  }

  /**
   * Get random test file
   */
  getRandomTestFile() {
    const files = fs.readdirSync(this.testFilesDir).filter(f => f.endsWith('.jpg'));
    const randomFile = files[Math.floor(Math.random() * files.length)];
    return path.join(this.testFilesDir, randomFile);
  }

  /**
   * Simulate a single user's upload session
   */
  async simulateUser(userId, testDuration) {
    const startTime = Date.now();
    const userMetrics = {
      uploads: 0,
      errors: 0,
      uploadTimes: []
    };

    try {
      // Authenticate user
      await this.authHelper.getToken(`upload-user-${userId}`);
      
      while (this.isRunning && (Date.now() - startTime) < testDuration * 1000) {
        try {
          const uploadStart = Date.now();
          const testFile = this.getRandomTestFile();
          const uploadParams = this.getRandomUploadParams();
          
          if (this.verbose) {
            console.log(`📤 User ${userId}: Starting upload of ${path.basename(testFile)}...`);
          }

          // Create form data
          const formData = new FormData();
          formData.append('file', fs.createReadStream(testFile), {
            filename: `stress-test-${userId}-${Date.now()}.jpg`,
            contentType: 'image/jpeg'
          });
          
          // Add optional parameters
          if (uploadParams.password) {
            formData.append('password', uploadParams.password);
          }
          if (uploadParams.maxViews) {
            formData.append('max_views', uploadParams.maxViews);
          }
          formData.append('expiry', uploadParams.expiry);

          // Get authentication headers
          const headers = await this.authHelper.getAuthHeaders(`upload-user-${userId}`);
          
          // Merge with form data headers
          Object.assign(headers, formData.getHeaders());

          // Make upload request
          const response = await axios.post(
            `https://${config.BRIDGE_HOST}${config.ENDPOINTS.UPLOAD}`,
            formData,
            {
              headers,
              timeout: config.TIMINGS.REQUEST_TIMEOUT,
              maxContentLength: 50 * 1024 * 1024, // 50MB max
              maxBodyLength: 50 * 1024 * 1024
            }
          );

          const uploadTime = Date.now() - uploadStart;
          
          // Record metrics
          this.metrics.totalUploads++;
          userMetrics.uploads++;
          
          if (response.status === 200) {
            this.metrics.successfulUploads++;
            this.metrics.uploadTimes.push(uploadTime);
            userMetrics.uploadTimes.push(uploadTime);
            
            const { url } = response.data;
            
            if (this.verbose) {
              console.log(`✅ User ${userId}: Upload successful - ${url} (${uploadTime}ms)`.green);
            }
          } else {
            this.metrics.failedUploads++;
            userMetrics.errors++;
            console.log(`⚠️ User ${userId}: Upload failed with status ${response.status}`.yellow);
          }

          // Random delay between uploads (10-30 seconds)
          const delay = 10000 + Math.random() * 20000;
          await this.sleep(delay);
          
        } catch (error) {
          this.metrics.totalUploads++;
          this.metrics.failedUploads++;
          userMetrics.errors++;
          
          const errorType = error.code || error.response?.status || 'unknown';
          this.metrics.errors[errorType] = (this.metrics.errors[errorType] || 0) + 1;
          
          if (this.verbose) {
            console.log(`❌ User ${userId}: Upload failed - ${error.message}`.red);
          }
          
          // Shorter delay on error
          await this.sleep(5000);
        }
      }
      
      const avgUploadTime = userMetrics.uploadTimes.length > 0 
        ? userMetrics.uploadTimes.reduce((a, b) => a + b, 0) / userMetrics.uploadTimes.length 
        : 0;
      
      console.log(`👤 User ${userId} completed: ${userMetrics.uploads} uploads, ${userMetrics.errors} errors, avg time: ${avgUploadTime.toFixed(0)}ms`);
      
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
   * Calculate upload performance statistics
   */
  calculateStats() {
    const { uploadTimes } = this.metrics;
    const totalDuration = (this.metrics.endTime - this.metrics.startTime) / 1000;
    
    if (uploadTimes.length === 0) {
      return {
        totalUploads: this.metrics.totalUploads,
        successfulUploads: this.metrics.successfulUploads,
        failedUploads: this.metrics.failedUploads,
        errorRate: this.metrics.totalUploads > 0 ? this.metrics.failedUploads / this.metrics.totalUploads : 0,
        throughput: this.metrics.totalUploads / totalDuration,
        duration: totalDuration,
        errors: this.metrics.errors
      };
    }
    
    uploadTimes.sort((a, b) => a - b);
    
    return {
      totalUploads: this.metrics.totalUploads,
      successfulUploads: this.metrics.successfulUploads,
      failedUploads: this.metrics.failedUploads,
      errorRate: this.metrics.totalUploads > 0 ? this.metrics.failedUploads / this.metrics.totalUploads : 0,
      throughput: this.metrics.totalUploads / totalDuration,
      uploadTime: {
        min: Math.min(...uploadTimes),
        max: Math.max(...uploadTimes),
        avg: uploadTimes.reduce((a, b) => a + b, 0) / uploadTimes.length,
        p50: uploadTimes[Math.floor(uploadTimes.length * 0.5)],
        p95: uploadTimes[Math.floor(uploadTimes.length * 0.95)],
        p99: uploadTimes[Math.floor(uploadTimes.length * 0.99)]
      },
      duration: totalDuration,
      errors: this.metrics.errors
    };
  }

  /**
   * Print upload test results
   */
  printResults() {
    const stats = this.calculateStats();
    
    console.log('\n' + '='.repeat(60).cyan);
    console.log('📊 UPLOAD STRESS TEST RESULTS'.cyan.bold);
    console.log('='.repeat(60).cyan);
    
    console.log(`👥 Concurrent Users: ${this.users}`);
    console.log(`⏱️  Test Duration: ${stats.duration.toFixed(1)}s`);
    console.log(`📤 Total Uploads: ${stats.totalUploads}`);
    console.log(`✅ Successful: ${stats.successfulUploads} (${((stats.successfulUploads/stats.totalUploads)*100).toFixed(1)}%)`);
    console.log(`❌ Failed: ${stats.failedUploads} (${(stats.errorRate*100).toFixed(1)}%)`);
    console.log(`🚀 Throughput: ${stats.throughput.toFixed(2)} uploads/s`);
    
    if (stats.uploadTime) {
      console.log('\n⏱️ Upload Times:');
      console.log(`   Min: ${(stats.uploadTime.min/1000).toFixed(1)}s`);
      console.log(`   Avg: ${(stats.uploadTime.avg/1000).toFixed(1)}s`);
      console.log(`   Max: ${(stats.uploadTime.max/1000).toFixed(1)}s`);
      console.log(`   P50: ${(stats.uploadTime.p50/1000).toFixed(1)}s`);
      console.log(`   P95: ${(stats.uploadTime.p95/1000).toFixed(1)}s`);
      console.log(`   P99: ${(stats.uploadTime.p99/1000).toFixed(1)}s`);
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
    
    if (stats.uploadTime && stats.uploadTime.p95 > config.THRESHOLDS.MAX_RESPONSE_TIME) {
      console.log(`   ❌ Slow upload times: P95 ${(stats.uploadTime.p95/1000).toFixed(1)}s (threshold: ${config.THRESHOLDS.MAX_RESPONSE_TIME/1000}s)`.red);
    } else if (stats.uploadTime) {
      console.log(`   ✅ Upload times acceptable: P95 ${(stats.uploadTime.p95/1000).toFixed(1)}s`.green);
    }
  }

  /**
   * Cleanup test files
   */
  async cleanup() {
    try {
      if (fs.existsSync(this.testFilesDir)) {
        for (const file of this.metrics.filesCreated) {
          if (fs.existsSync(file)) {
            fs.unlinkSync(file);
          }
        }
        fs.rmdirSync(this.testFilesDir);
        console.log(`🧹 Cleaned up test files`);
      }
    } catch (error) {
      console.log(`⚠️ Cleanup warning: ${error.message}`);
    }
  }

  /**
   * Run the upload stress test
   */
  async run() {
    console.log('🚀 Starting Upload Stress Test'.cyan.bold);
    console.log(`👥 Users: ${this.users}`);
    console.log(`⏱️  Duration: ${this.duration}s`);
    console.log(`📁 File Sizes: ${config.UPLOAD_FILE_SIZES.map(s => `${(s/1024).toFixed(0)}KB`).join(', ')}`);
    console.log('');

    // Setup test files
    await this.setupTestFiles();

    this.isRunning = true;
    this.metrics.startTime = Date.now();

    // Start progress indicator
    const progressInterval = setInterval(() => {
      if (this.isRunning) {
        const elapsed = (Date.now() - this.metrics.startTime) / 1000;
        const progress = Math.min(elapsed / this.duration, 1) * 100;
        process.stdout.write(`\r🔄 Progress: ${progress.toFixed(1)}% | Uploads: ${this.metrics.totalUploads} | Errors: ${this.metrics.failedUploads}`);
      }
    }, 1000);

    try {
      // Launch concurrent upload users
      const userPromises = [];
      for (let i = 0; i < this.users; i++) {
        const userPromise = this.simulateUser(i, this.duration);
        userPromises.push(userPromise);
        
        // Stagger user starts to avoid overwhelming server
        await this.sleep(500);
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
    
    // Cleanup test files
    await this.cleanup();
    
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
      default: 5,
      description: 'Number of concurrent upload users'
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

  const test = new UploadStressTest(argv);
  
  test.run().catch(error => {
    console.error('❌ Upload Test failed:', error.message);
    process.exit(1);
  });
}

module.exports = UploadStressTest;