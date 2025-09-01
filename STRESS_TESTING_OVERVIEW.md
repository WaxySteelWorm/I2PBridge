# I2P Bridge Stress Testing Suite

## 🎯 Overview

A comprehensive stress testing suite designed to validate the I2P Bridge application and backend server performance under various load conditions. The suite simulates real user behavior across HTTP browsing, IRC communications, and file upload services.

## 🏗️ Architecture

### Application Architecture
- **Flutter App**: Mobile/desktop client application
- **Bridge Server**: Central proxy server at `bridge.stormycloud.org`
- **I2P Network**: Anonymous network services accessed through the bridge

### Services Tested
1. **HTTP Browsing**: Access to I2P websites through `/api/v1/browse`
2. **IRC Communication**: WebSocket-based IRC client with encryption
3. **File Upload**: Image upload service via `/api/v1/upload`

## 🚀 Quick Start

### 1. Setup Environment
```bash
cd stress_test
./setup.sh
```

### 2. Configure API Key
```bash
export I2P_BRIDGE_API_KEY=your-actual-api-key
```

### 3. Run Quick Validation
```bash
./quick-test.sh
```

### 4. Run Comprehensive Tests
```bash
./run-all-tests.sh
```

## 📊 Test Types

### HTTP Browsing Stress Test
- **Purpose**: Validate web browsing performance through I2P bridge
- **Simulates**: Users browsing I2P sites and performing searches
- **Key Metrics**: Response time, throughput, success rate
- **Test Sites**: notbob.i2p, shinobi.i2p, i2pforum.i2p, ramble.i2p, natter.i2p

```bash
# Examples
node http-stress-test.js --users=25 --duration=120
npm run test:medium
```

### IRC Connection Stress Test  
- **Purpose**: Validate IRC WebSocket connections and messaging
- **Simulates**: Users connecting to IRC channels and sending messages
- **Key Metrics**: Connection success rate, message throughput, encryption handling
- **Test Channels**: #test, #general, #random, #bridge-test

```bash
# Examples
node irc-stress-test.js --users=15 --duration=180
```

### Upload Stress Test
- **Purpose**: Validate file upload service under load
- **Simulates**: Users uploading files of various sizes
- **Key Metrics**: Upload time, success rate, throughput
- **File Sizes**: 1KB to 10MB with various parameters

```bash
# Examples  
node upload-stress-test.js --users=8 --duration=120
```

### Orchestrated Testing
- **Purpose**: Test all services simultaneously under realistic load
- **Simulates**: Mixed user behavior across all services
- **Distribution**: 60% HTTP, 30% IRC, 10% Upload

```bash
# Examples
node test-orchestrator.js --users=50 --duration=300
```

## 📈 Load Test Levels

| Level | HTTP Users | IRC Users | Upload Users | Duration | Purpose |
|-------|------------|-----------|--------------|----------|---------|
| **Light** | 10 | 5 | 3 | 60s | Baseline performance |
| **Medium** | 25 | 15 | 8 | 120s | Expected normal load |
| **Heavy** | 50 | 25 | 12 | 180s | Peak usage scenarios |
| **Extreme** | 100+ | 50+ | 20+ | 300s+ | Breaking point testing |

## 🎛️ Real-time Monitoring

Start the monitoring dashboard for live metrics:
```bash
npm run monitor
# Open http://localhost:3000
```

### Dashboard Features
- Real-time bridge server health monitoring
- System resource tracking
- Live test execution controls
- Historical performance data
- Error analysis and alerts

## 📋 Test Results Interpretation

### Success Criteria
- ✅ **PASS**: Error rate < 5%, P95 response < 5s, 95%+ success rate
- ⚠️ **WARN**: Error rate 5-10%, P95 response 5-10s, some degradation  
- ❌ **FAIL**: Error rate > 10%, P95 response > 10s, significant failures

### Key Metrics Explained

**Response Time Percentiles**:
- P50 (median): 50% of requests complete faster than this
- P95: 95% of requests complete faster than this (key SLA metric)
- P99: 99% of requests complete faster than this (worst-case performance)

**Throughput**: Operations per second the system can handle

**Error Rate**: Percentage of failed requests (network, server, timeout errors)

## 🔧 Customization

### Custom Test Scenarios
Create custom test scripts using the provided classes:

```javascript
const HttpStressTest = require('./http-stress-test');

// Custom test focusing on search functionality
const searchTest = new HttpStressTest({
  users: 20,
  duration: 180,
  verbose: true
});

// Override URL generation for focused testing
searchTest.getRandomI2pUrl = () => {
  return 'http://shinobi.i2p/search?query=privacy';
};
```

### Configuration Override
Modify `config.js` to change:
- Target endpoints
- Test sites and channels
- Performance thresholds
- Security settings
- Timing parameters

## 🚨 Troubleshooting

### Common Issues

**Authentication Errors**:
- Verify API key is correctly set
- Check API key validity and permissions
- Ensure bridge server is accepting connections

**High Error Rates**:
- Reduce concurrent users
- Increase test duration for better averaging
- Check bridge server capacity and logs

**Connection Failures**:
- Verify internet connectivity
- Check if bridge server is operational
- Ensure SSL certificate is valid

**Memory Issues**:
- Reduce number of concurrent users
- Decrease test duration
- Monitor system resources during tests

### Debug Mode
Enable verbose logging for detailed troubleshooting:
```bash
node http-stress-test.js --users=5 --duration=30 --verbose
```

## 📊 Performance Optimization

### Based on Results

**If HTTP browsing is slow**:
- Implement caching strategies
- Optimize bridge server request handling
- Consider CDN for static content

**If IRC connections fail**:
- Increase WebSocket connection limits
- Implement connection pooling
- Add IRC service redundancy  

**If uploads timeout**:
- Increase server upload limits
- Implement chunked upload support
- Add upload queue management

## 🔒 Security Considerations

- All tests use proper JWT authentication
- SSL certificate pinning validation
- Encrypted IRC communications
- No sensitive data in test files
- Automatic cleanup of temporary data

## 📦 Files Structure

```
stress_test/
├── README.md                    # Test plan overview
├── USAGE_GUIDE.md              # Detailed usage instructions  
├── setup.sh                    # Environment setup script
├── quick-test.sh               # Quick validation tests
├── run-all-tests.sh            # Comprehensive test suite
├── package.json                # Node.js dependencies
├── config.js                   # Test configuration
├── test-orchestrator.js        # Main test coordinator
├── http-stress-test.js         # HTTP browsing tests
├── irc-stress-test.js          # IRC connection tests
├── upload-stress-test.js       # File upload tests
├── monitoring-dashboard.js     # Real-time monitoring
├── example-test.js             # Usage examples
├── utils/
│   ├── auth-helper.js          # Authentication utilities
│   └── metrics-collector.js    # Metrics collection
└── results/                    # Test results (auto-created)
```

## 🎯 Recommended Testing Workflow

### Pre-Release Testing
1. **Setup**: Run `./setup.sh` to prepare environment
2. **Validation**: Run `./quick-test.sh` to verify basic functionality
3. **Load Testing**: Run `./run-all-tests.sh` for comprehensive testing
4. **Monitoring**: Use dashboard during production-like load tests
5. **Analysis**: Review results and optimize based on findings

### Continuous Testing
- Integrate quick tests into CI/CD pipeline
- Run comprehensive tests before major releases
- Monitor production performance against test baselines
- Use results to guide infrastructure scaling decisions

## 📈 Success Metrics for Release

Before releasing your app, ensure these criteria are met:

✅ **HTTP Browsing**: 25+ concurrent users with <2s P95 response time
✅ **IRC Service**: 15+ concurrent connections with >98% success rate  
✅ **Upload Service**: 8+ concurrent uploads with <10s P95 upload time
✅ **Combined Load**: 50+ total users across all services
✅ **Error Rate**: <3% across all services under normal load
✅ **Stability**: No memory leaks or connection issues during 5+ minute tests

When these criteria are met, your bridge server should handle real-world usage effectively.