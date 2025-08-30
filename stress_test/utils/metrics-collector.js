// Metrics collection utilities for stress testing

const fs = require('fs');
const path = require('path');

class MetricsCollector {
  constructor(testName = 'stress-test') {
    this.testName = testName;
    this.startTime = Date.now();
    this.metrics = [];
    this.resultDir = path.join(__dirname, '..', 'results');
    
    // Ensure results directory exists
    if (!fs.existsSync(this.resultDir)) {
      fs.mkdirSync(this.resultDir, { recursive: true });
    }
  }

  /**
   * Record a metric data point
   */
  recordMetric(metric) {
    const timestamp = Date.now();
    const dataPoint = {
      timestamp,
      elapsed: timestamp - this.startTime,
      ...metric
    };
    
    this.metrics.push(dataPoint);
  }

  /**
   * Record HTTP request metric
   */
  recordHttpRequest(userId, url, responseTime, statusCode, error = null) {
    this.recordMetric({
      type: 'http_request',
      userId,
      url,
      responseTime,
      statusCode,
      success: statusCode >= 200 && statusCode < 300,
      error
    });
  }

  /**
   * Record IRC connection metric
   */
  recordIrcConnection(userId, connectionTime, success, error = null) {
    this.recordMetric({
      type: 'irc_connection',
      userId,
      connectionTime,
      success,
      error
    });
  }

  /**
   * Record IRC message metric
   */
  recordIrcMessage(userId, channel, messageSize, responseTime, success, error = null) {
    this.recordMetric({
      type: 'irc_message',
      userId,
      channel,
      messageSize,
      responseTime,
      success,
      error
    });
  }

  /**
   * Record upload metric
   */
  recordUpload(userId, fileSize, uploadTime, success, url = null, error = null) {
    this.recordMetric({
      type: 'upload',
      userId,
      fileSize,
      uploadTime,
      success,
      url,
      error
    });
  }

  /**
   * Generate performance statistics
   */
  generateStats() {
    const httpMetrics = this.metrics.filter(m => m.type === 'http_request');
    const ircConnectionMetrics = this.metrics.filter(m => m.type === 'irc_connection');
    const ircMessageMetrics = this.metrics.filter(m => m.type === 'irc_message');
    const uploadMetrics = this.metrics.filter(m => m.type === 'upload');
    
    const totalDuration = (Date.now() - this.startTime) / 1000;
    
    return {
      testName: this.testName,
      startTime: new Date(this.startTime).toISOString(),
      duration: totalDuration,
      
      http: this.calculateServiceStats(httpMetrics, 'responseTime'),
      ircConnections: this.calculateServiceStats(ircConnectionMetrics, 'connectionTime'),
      ircMessages: this.calculateServiceStats(ircMessageMetrics, 'responseTime'),
      uploads: this.calculateServiceStats(uploadMetrics, 'uploadTime'),
      
      timeline: this.generateTimeline(),
      errorAnalysis: this.analyzeErrors()
    };
  }

  /**
   * Calculate statistics for a service type
   */
  calculateServiceStats(metrics, timeField) {
    if (metrics.length === 0) {
      return {
        total: 0,
        successful: 0,
        failed: 0,
        successRate: 0,
        throughput: 0
      };
    }

    const successful = metrics.filter(m => m.success);
    const failed = metrics.filter(m => !m.success);
    const times = successful.map(m => m[timeField]).filter(t => t != null);
    
    const totalDuration = (Date.now() - this.startTime) / 1000;
    
    const stats = {
      total: metrics.length,
      successful: successful.length,
      failed: failed.length,
      successRate: successful.length / metrics.length,
      throughput: metrics.length / totalDuration,
      errorTypes: {}
    };

    // Calculate timing statistics if available
    if (times.length > 0) {
      times.sort((a, b) => a - b);
      
      stats.timing = {
        min: Math.min(...times),
        max: Math.max(...times),
        avg: times.reduce((a, b) => a + b, 0) / times.length,
        p50: times[Math.floor(times.length * 0.5)],
        p95: times[Math.floor(times.length * 0.95)],
        p99: times[Math.floor(times.length * 0.99)]
      };
    }

    // Analyze errors
    failed.forEach(metric => {
      const errorType = metric.error || 'unknown';
      stats.errorTypes[errorType] = (stats.errorTypes[errorType] || 0) + 1;
    });

    return stats;
  }

  /**
   * Generate timeline data for visualization
   */
  generateTimeline() {
    const timeWindows = [];
    const windowSize = 10000; // 10 second windows
    const startTime = this.startTime;
    const endTime = Date.now();
    
    for (let t = startTime; t < endTime; t += windowSize) {
      const windowEnd = Math.min(t + windowSize, endTime);
      const windowMetrics = this.metrics.filter(m => 
        m.timestamp >= t && m.timestamp < windowEnd
      );
      
      timeWindows.push({
        start: t,
        end: windowEnd,
        total: windowMetrics.length,
        successful: windowMetrics.filter(m => m.success).length,
        failed: windowMetrics.filter(m => !m.success).length,
        http: windowMetrics.filter(m => m.type === 'http_request').length,
        irc: windowMetrics.filter(m => m.type.startsWith('irc')).length,
        upload: windowMetrics.filter(m => m.type === 'upload').length
      });
    }
    
    return timeWindows;
  }

  /**
   * Analyze error patterns
   */
  analyzeErrors() {
    const errors = this.metrics.filter(m => !m.success);
    const errorAnalysis = {
      total: errors.length,
      byType: {},
      byService: {},
      timeline: []
    };

    // Group errors by type and service
    errors.forEach(error => {
      const type = error.error || 'unknown';
      const service = error.type;
      
      errorAnalysis.byType[type] = (errorAnalysis.byType[type] || 0) + 1;
      errorAnalysis.byService[service] = (errorAnalysis.byService[service] || 0) + 1;
    });

    return errorAnalysis;
  }

  /**
   * Save results to file
   */
  async saveResults(additionalData = {}) {
    const stats = this.generateStats();
    const results = {
      ...stats,
      ...additionalData,
      generatedAt: new Date().toISOString()
    };

    const filename = `stress-test-${this.testName}-${new Date().toISOString().split('T')[0]}.json`;
    const filepath = path.join(this.resultDir, filename);
    
    try {
      fs.writeFileSync(filepath, JSON.stringify(results, null, 2));
      console.log(`💾 Results saved to: ${filepath}`.green);
      return filepath;
    } catch (error) {
      console.error(`❌ Failed to save results: ${error.message}`.red);
      throw error;
    }
  }

  /**
   * Generate CSV export for further analysis
   */
  async exportToCsv() {
    const csvFilename = `stress-test-${this.testName}-${new Date().toISOString().split('T')[0]}.csv`;
    const csvPath = path.join(this.resultDir, csvFilename);
    
    try {
      const csvHeader = 'timestamp,elapsed,type,userId,success,responseTime,error\n';
      let csvContent = csvHeader;
      
      this.metrics.forEach(metric => {
        const row = [
          metric.timestamp,
          metric.elapsed,
          metric.type,
          metric.userId || '',
          metric.success,
          metric.responseTime || metric.connectionTime || metric.uploadTime || '',
          metric.error || ''
        ].join(',');
        csvContent += row + '\n';
      });
      
      fs.writeFileSync(csvPath, csvContent);
      console.log(`📊 CSV export saved to: ${csvPath}`.green);
      return csvPath;
      
    } catch (error) {
      console.error(`❌ Failed to export CSV: ${error.message}`.red);
      throw error;
    }
  }

  /**
   * Print summary statistics to console
   */
  printSummary() {
    const stats = this.generateStats();
    
    console.log('\n' + '='.repeat(80).cyan);
    console.log('📈 METRICS SUMMARY'.cyan.bold);
    console.log('='.repeat(80).cyan);
    
    console.log(`📊 Total Data Points: ${this.metrics.length}`);
    console.log(`⏱️  Test Duration: ${stats.duration.toFixed(1)}s`);
    
    if (stats.http.total > 0) {
      console.log(`\n🌐 HTTP: ${stats.http.successful}/${stats.http.total} (${(stats.http.successRate*100).toFixed(1)}%)`);
      if (stats.http.timing) {
        console.log(`   Avg Response: ${stats.http.timing.avg.toFixed(0)}ms`);
      }
    }
    
    if (stats.uploads.total > 0) {
      console.log(`📤 Upload: ${stats.uploads.successful}/${stats.uploads.total} (${(stats.uploads.successRate*100).toFixed(1)}%)`);
      if (stats.uploads.timing) {
        console.log(`   Avg Upload: ${(stats.uploads.timing.avg/1000).toFixed(1)}s`);
      }
    }
    
    if (stats.ircConnections.total > 0) {
      console.log(`💬 IRC Connections: ${stats.ircConnections.successful}/${stats.ircConnections.total} (${(stats.ircConnections.successRate*100).toFixed(1)}%)`);
    }
  }
}

module.exports = MetricsCollector;