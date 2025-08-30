# I2P Bridge Stress Testing Usage Guide

## Quick Start

### Prerequisites
1. **API Key**: Set your I2P Bridge API key as an environment variable:
   ```bash
   export I2P_BRIDGE_API_KEY=your-actual-api-key-here
   ```

2. **Node.js**: Ensure Node.js 16+ is installed

3. **Dependencies**: Install test dependencies:
   ```bash
   cd stress_test
   npm install
   ```

### Quick Validation Test
Run a quick test to verify everything works:
```bash
./quick-test.sh
```

This runs light tests on all services to validate connectivity and basic functionality.

### Comprehensive Testing
Run the full stress testing suite:
```bash
./run-all-tests.sh
```

This executes a complete test progression from light to heavy loads.

## Individual Test Scripts

### HTTP Browsing Test
Tests the web browsing functionality through the I2P bridge:

```bash
# Light test - 10 users for 1 minute
node http-stress-test.js --users=10 --duration=60

# Medium test - 25 users for 2 minutes  
node http-stress-test.js --users=25 --duration=120

# Heavy test - 50 users for 3 minutes
node http-stress-test.js --users=50 --duration=180 --verbose
```

**What it tests**:
- Concurrent browsing of I2P sites (notbob.i2p, shinobi.i2p, etc.)
- Search queries on shinobi.i2p
- Response times and throughput
- Error handling under load

### IRC Connection Test  
Tests the IRC functionality via WebSocket:

```bash
# Light test - 5 users for 2 minutes
node irc-stress-test.js --users=5 --duration=120

# Medium test - 15 users for 3 minutes
node irc-stress-test.js --users=15 --duration=180

# Heavy test - 25 users for 5 minutes
node irc-stress-test.js --users=25 --duration=300 --verbose
```

**What it tests**:
- WebSocket connection establishment
- IRC registration and authentication  
- Channel joining and message sending
- Encryption handling
- Connection resilience

### Upload Test
Tests file upload functionality:

```bash
# Light test - 3 users for 1 minute
node upload-stress-test.js --users=3 --duration=60

# Medium test - 8 users for 2 minutes
node upload-stress-test.js --users=8 --duration=120

# Heavy test - 12 users for 3 minutes  
node upload-stress-test.js --users=12 --duration=180 --verbose
```

**What it tests**:
- Concurrent file uploads with various sizes (1KB - 10MB)
- Different upload parameters (passwords, expiry, max views)
- Upload performance and error rates
- File handling under load

### Orchestrated Testing
Run multiple test types together:

```bash
# Run all services with 50 total users for 5 minutes
node test-orchestrator.js --users=50 --duration=300

# Run only specific tests
node test-orchestrator.js --tests=http,irc --users=30 --duration=120

# Maximum load test
node test-orchestrator.js --users=200 --duration=600
```

## Real-time Monitoring

Start the monitoring dashboard for real-time metrics:

```bash
npm run monitor
# or
node monitoring-dashboard.js --port=3000
```

Then open http://localhost:3000 in your browser for:
- Real-time bridge server health monitoring
- System resource usage
- Live test execution controls
- Historical metrics visualization

## Test Load Levels

### Recommended Test Progression

1. **Light Load (Baseline)**
   - HTTP: 10 users
   - IRC: 5 users  
   - Upload: 3 users
   - Purpose: Establish baseline performance

2. **Medium Load (Expected)**
   - HTTP: 25 users
   - IRC: 15 users
   - Upload: 8 users
   - Purpose: Test normal expected usage

3. **Heavy Load (Peak)**
   - HTTP: 50 users
   - IRC: 25 users
   - Upload: 12 users
   - Purpose: Test peak usage scenarios

4. **Extreme Load (Stress)**
   - HTTP: 100+ users
   - IRC: 50+ users
   - Upload: 20+ users
   - Purpose: Find breaking points

## Understanding Results

### Key Metrics

**HTTP Browsing**:
- Response Time: Time to fetch I2P page content
- Throughput: Requests per second
- Success Rate: % of successful page loads
- P95 Response: 95th percentile response time

**IRC Connections**:
- Connection Success Rate: % of successful WebSocket connections
- Registration Time: Time to complete IRC registration
- Message Throughput: Messages per second
- Connection Stability: Reconnection frequency

**File Uploads**:
- Upload Time: Time to complete file upload
- Success Rate: % of successful uploads
- Throughput: Uploads per second
- File Size Impact: Performance vs file size correlation

### Performance Thresholds

🎯 **PASS Criteria**:
- Error Rate: < 5%
- Response Time P95: < 5 seconds
- Connection Success Rate: > 95%

⚠️ **WARNING Criteria**:
- Error Rate: 5-10%
- Response Time P95: 5-10 seconds
- Some performance degradation

❌ **FAIL Criteria**:
- Error Rate: > 10%
- Response Time P95: > 10 seconds
- Significant service failures

## Troubleshooting

### Common Issues

**Authentication Failures**:
```
❌ Authentication failed: Invalid API key
```
- Verify I2P_BRIDGE_API_KEY environment variable
- Ensure API key is valid and not expired

**Connection Timeouts**:
```
❌ Connection timeout to bridge.stormycloud.org
```
- Check internet connectivity
- Verify bridge server is operational
- Try reducing concurrent users

**High Error Rates**:
```
❌ Error rate: 25% (threshold: 5%)
```
- Bridge server may be overloaded
- Reduce concurrent users
- Check server logs for capacity issues

**Memory Issues**:
```
JavaScript heap out of memory
```
- Reduce test duration or users
- Restart tests with lower load
- Monitor system resources

### Debug Mode

Run tests with verbose logging:
```bash
node http-stress-test.js --users=5 --duration=30 --verbose
```

This provides detailed request/response logging for debugging.

## Test Data

### Generated Files
- Test files are automatically created in `stress_test/test-files/`
- Files range from 1KB to 10MB
- All test files are cleaned up after upload tests

### I2P Sites Tested
- notbob.i2p - General content
- i2pforum.i2p - Forums
- shinobi.i2p - Search engine
- ramble.i2p - Social platform
- natter.i2p - Twitter alternative

### IRC Channels
- #test - Primary test channel
- #general - General discussion
- #random - Random chat
- #bridge-test - Bridge-specific testing

## Scaling Recommendations

Based on test results, consider these scaling strategies:

### If HTTP browsing is slow:
- Implement request caching
- Add CDN for static content
- Scale bridge server horizontally

### If IRC connections fail:
- Increase WebSocket connection limits
- Implement connection pooling
- Add IRC service redundancy

### If uploads timeout:
- Increase upload timeout limits
- Implement chunked uploads
- Add file processing queues

## Security Considerations

- All tests use proper authentication
- SSL certificate pinning is validated
- Encrypted WebSocket connections for IRC
- No sensitive data in test files
- Automatic cleanup of temporary files

## Integration with CI/CD

Add to your CI pipeline:

```yaml
# .github/workflows/stress-test.yml
name: Stress Test
on: [push, pull_request]

jobs:
  stress-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '18'
      - name: Install dependencies
        run: cd stress_test && npm install
      - name: Run quick stress test
        env:
          I2P_BRIDGE_API_KEY: ${{ secrets.I2P_BRIDGE_API_KEY }}
        run: cd stress_test && ./quick-test.sh
```