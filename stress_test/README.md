# I2P Bridge Stress Testing Plan

## Overview
This stress testing suite simulates multiple concurrent users performing various operations to validate the I2P Bridge app and backend server performance under load.

## Architecture Analysis
The I2P Bridge app connects to a central bridge server (`bridge.stormycloud.org`) that acts as a proxy to I2P network services:

- **Authentication**: JWT tokens via API key (`/auth/token`)
- **HTTP Browsing**: `/api/v1/browse` endpoint for I2P site access
- **IRC**: WebSocket connection with AES/CBC encryption
- **Upload**: `/api/v1/upload` endpoint for file uploads

## Test Categories

### 1. HTTP Browsing Tests
**Target**: `/api/v1/browse` endpoint
**Simulates**: Users browsing I2P websites

**Test Sites**:
- notbob.i2p - General content
- i2pforum.i2p - Forums
- shinobi.i2p - Search engine  
- ramble.i2p - Social media
- natter.i2p - Twitter alternative

**Test Scenarios**:
- Concurrent page loads
- Sequential browsing sessions
- Search queries on shinobi.i2p
- Mix of encrypted/non-encrypted requests

### 2. IRC Tests
**Target**: WebSocket connection to `wss://bridge.stormycloud.org`
**Simulates**: Users connecting to IRC channels

**Test Scenarios**:
- Multiple simultaneous connections
- Channel joining/leaving
- Message sending/receiving
- Private messages
- User list updates
- Connection resilience (reconnections)

### 3. Upload Tests
**Target**: `/api/v1/upload` endpoint
**Simulates**: Users uploading files

**Test Scenarios**:
- Concurrent file uploads
- Various file sizes (1KB - 10MB)
- Different upload parameters (password, expiry, max views)
- Upload retry scenarios

## Load Testing Metrics

### Performance Metrics
- **Response Time**: P50, P95, P99 latencies
- **Throughput**: Requests per second
- **Error Rate**: % of failed requests
- **Connection Time**: WebSocket connection establishment
- **Memory Usage**: Server and client memory consumption
- **CPU Usage**: Server CPU utilization

### Stress Test Levels
1. **Light Load**: 10 concurrent users
2. **Medium Load**: 50 concurrent users  
3. **Heavy Load**: 100 concurrent users
4. **Extreme Load**: 200+ concurrent users

## Implementation Plan

1. **Node.js Test Scripts**: HTTP client simulations
2. **WebSocket Test Scripts**: IRC connection simulations
3. **File Upload Scripts**: Multipart upload testing
4. **Monitoring Dashboard**: Real-time metrics collection
5. **Test Orchestration**: Coordinated test execution

## Expected Outcomes

- Identify bottlenecks in bridge server
- Validate concurrent user limits
- Test error handling under load
- Measure resource consumption
- Validate security measures under stress