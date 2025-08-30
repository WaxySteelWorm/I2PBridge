// Real-time monitoring dashboard for stress tests

const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const colors = require('colors');
const axios = require('axios');
const config = require('./config');

class MonitoringDashboard {
  constructor(options = {}) {
    this.port = options.port || 3000;
    this.monitoringInterval = options.interval || 5000; // 5 seconds
    
    this.app = express();
    this.server = http.createServer(this.app);
    this.io = socketIo(this.server, {
      cors: {
        origin: "*",
        methods: ["GET", "POST"]
      }
    });
    
    this.metrics = {
      timestamp: Date.now(),
      bridgeServer: {
        status: 'unknown',
        responseTime: null,
        lastCheck: null
      },
      activeTests: [],
      systemHealth: {
        cpu: null,
        memory: null,
        connections: null
      }
    };
    
    this.setupRoutes();
    this.setupSocketHandlers();
  }

  /**
   * Setup Express routes
   */
  setupRoutes() {
    // Serve static dashboard HTML
    this.app.get('/', (req, res) => {
      res.send(this.getDashboardHTML());
    });

    // API endpoint for current metrics
    this.app.get('/api/metrics', (req, res) => {
      res.json(this.metrics);
    });

    // API endpoint to trigger test
    this.app.post('/api/test/:type', express.json(), async (req, res) => {
      try {
        const testType = req.params.type;
        const options = req.body;
        
        console.log(`🚀 Triggering ${testType} test via API...`.cyan);
        
        // This would integrate with the test runners
        // For now, just acknowledge the request
        res.json({
          status: 'started',
          testType,
          options,
          timestamp: new Date().toISOString()
        });
        
      } catch (error) {
        res.status(500).json({
          error: error.message,
          timestamp: new Date().toISOString()
        });
      }
    });
  }

  /**
   * Setup Socket.IO handlers
   */
  setupSocketHandlers() {
    this.io.on('connection', (socket) => {
      console.log(`👀 Dashboard client connected: ${socket.id}`.green);
      
      // Send current metrics to new client
      socket.emit('metrics', this.metrics);
      
      socket.on('disconnect', () => {
        console.log(`👋 Dashboard client disconnected: ${socket.id}`.yellow);
      });
      
      // Handle test execution requests from dashboard
      socket.on('start_test', async (testConfig) => {
        try {
          console.log(`🎯 Starting test from dashboard:`, testConfig);
          // Integration point for running tests
          socket.emit('test_status', { status: 'started', config: testConfig });
        } catch (error) {
          socket.emit('test_error', { error: error.message });
        }
      });
    });
  }

  /**
   * Monitor bridge server health
   */
  async checkBridgeHealth() {
    try {
      const start = Date.now();
      
      const response = await axios.get(`https://${config.BRIDGE_HOST}${config.ENDPOINTS.DEBUG}`, {
        timeout: 10000,
        validateStatus: (status) => status < 500
      });
      
      const responseTime = Date.now() - start;
      
      this.metrics.bridgeServer = {
        status: response.status < 400 ? 'healthy' : 'degraded',
        responseTime,
        lastCheck: new Date().toISOString(),
        statusCode: response.status
      };
      
    } catch (error) {
      this.metrics.bridgeServer = {
        status: 'unhealthy',
        responseTime: null,
        lastCheck: new Date().toISOString(),
        error: error.message
      };
    }
  }

  /**
   * Collect system metrics
   */
  collectSystemMetrics() {
    const used = process.memoryUsage();
    
    this.metrics.systemHealth = {
      memory: {
        rss: Math.round(used.rss / 1024 / 1024 * 100) / 100, // MB
        heapTotal: Math.round(used.heapTotal / 1024 / 1024 * 100) / 100,
        heapUsed: Math.round(used.heapUsed / 1024 / 1024 * 100) / 100,
        external: Math.round(used.external / 1024 / 1024 * 100) / 100
      },
      uptime: Math.round(process.uptime()),
      timestamp: new Date().toISOString()
    };
  }

  /**
   * Start monitoring loop
   */
  startMonitoring() {
    console.log('📊 Starting monitoring loop...'.blue);
    
    setInterval(async () => {
      try {
        await this.checkBridgeHealth();
        this.collectSystemMetrics();
        
        // Update timestamp
        this.metrics.timestamp = Date.now();
        
        // Broadcast to all connected clients
        this.io.emit('metrics', this.metrics);
        
        // Console status
        const status = this.metrics.bridgeServer.status;
        const responseTime = this.metrics.bridgeServer.responseTime;
        const memory = this.metrics.systemHealth.memory.heapUsed;
        
        process.stdout.write(`\r📊 Bridge: ${status} (${responseTime}ms) | Memory: ${memory}MB | Clients: ${this.io.engine.clientsCount}`);
        
      } catch (error) {
        console.error(`\n⚠️ Monitoring error: ${error.message}`);
      }
    }, this.monitoringInterval);
  }

  /**
   * Generate dashboard HTML
   */
  getDashboardHTML() {
    return `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>I2P Bridge Stress Test Dashboard</title>
    <script src="https://cdn.socket.io/4.7.5/socket.io.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body { 
            font-family: 'Courier New', monospace; 
            background: #1a1a1a; 
            color: #00ff00; 
            margin: 0; 
            padding: 20px; 
        }
        .header { 
            text-align: center; 
            margin-bottom: 30px; 
            border-bottom: 2px solid #00ff00; 
            padding-bottom: 10px; 
        }
        .metrics-grid { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); 
            gap: 20px; 
            margin-bottom: 30px; 
        }
        .metric-card { 
            background: #2a2a2a; 
            border: 1px solid #00ff00; 
            padding: 15px; 
            border-radius: 5px; 
        }
        .metric-title { 
            color: #00ffff; 
            font-weight: bold; 
            margin-bottom: 10px; 
        }
        .status-healthy { color: #00ff00; }
        .status-degraded { color: #ffff00; }
        .status-unhealthy { color: #ff0000; }
        .controls { 
            margin: 20px 0; 
            text-align: center; 
        }
        button { 
            background: #2a2a2a; 
            color: #00ff00; 
            border: 1px solid #00ff00; 
            padding: 10px 20px; 
            margin: 0 10px; 
            cursor: pointer; 
            border-radius: 3px; 
        }
        button:hover { 
            background: #00ff00; 
            color: #1a1a1a; 
        }
        #log { 
            background: #000; 
            color: #00ff00; 
            padding: 10px; 
            height: 200px; 
            overflow-y: scroll; 
            font-size: 12px; 
            border: 1px solid #00ff00; 
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>🎯 I2P Bridge Stress Test Dashboard</h1>
        <p>Real-time monitoring and control</p>
    </div>

    <div class="metrics-grid">
        <div class="metric-card">
            <div class="metric-title">🌉 Bridge Server Health</div>
            <div>Status: <span id="bridge-status">Checking...</span></div>
            <div>Response Time: <span id="bridge-response">-</span></div>
            <div>Last Check: <span id="bridge-lastcheck">-</span></div>
        </div>

        <div class="metric-card">
            <div class="metric-title">💾 System Resources</div>
            <div>Memory Usage: <span id="memory-usage">-</span></div>
            <div>Uptime: <span id="uptime">-</span></div>
            <div>Connected Clients: <span id="client-count">0</span></div>
        </div>

        <div class="metric-card">
            <div class="metric-title">🧪 Active Tests</div>
            <div id="active-tests">No tests running</div>
        </div>

        <div class="metric-card">
            <div class="metric-title">📊 Quick Stats</div>
            <div id="quick-stats">Waiting for test data...</div>
        </div>
    </div>

    <div class="controls">
        <h3>Test Controls</h3>
        <button onclick="startTest('http', 20, 60)">🌐 HTTP Test (20 users, 1min)</button>
        <button onclick="startTest('irc', 10, 120)">💬 IRC Test (10 users, 2min)</button>
        <button onclick="startTest('upload', 5, 60)">📤 Upload Test (5 users, 1min)</button>
        <button onclick="startTest('all', 50, 180)">🎯 Full Test (50 users, 3min)</button>
    </div>

    <div class="metric-card">
        <div class="metric-title">📝 Real-time Log</div>
        <div id="log"></div>
    </div>

    <script>
        const socket = io();
        
        // Update metrics display
        socket.on('metrics', (data) => {
            updateBridgeHealth(data.bridgeServer);
            updateSystemHealth(data.systemHealth);
        });
        
        socket.on('test_status', (data) => {
            log(\`🎯 Test \${data.config?.type || 'unknown'} started\`);
        });
        
        socket.on('test_error', (data) => {
            log(\`❌ Test error: \${data.error}\`, 'error');
        });
        
        function updateBridgeHealth(health) {
            const status = document.getElementById('bridge-status');
            const response = document.getElementById('bridge-response');
            const lastcheck = document.getElementById('bridge-lastcheck');
            
            status.textContent = health.status;
            status.className = \`status-\${health.status}\`;
            
            response.textContent = health.responseTime ? \`\${health.responseTime}ms\` : 'N/A';
            lastcheck.textContent = health.lastCheck ? new Date(health.lastCheck).toLocaleTimeString() : 'Never';
        }
        
        function updateSystemHealth(health) {
            if (!health) return;
            
            const memory = document.getElementById('memory-usage');
            const uptime = document.getElementById('uptime');
            
            if (health.memory) {
                memory.textContent = \`\${health.memory.heapUsed}MB / \${health.memory.heapTotal}MB\`;
            }
            
            uptime.textContent = \`\${health.uptime}s\`;
        }
        
        function startTest(type, users, duration) {
            log(\`🚀 Starting \${type} test with \${users} users for \${duration}s\`);
            
            socket.emit('start_test', {
                type,
                users,
                duration,
                timestamp: new Date().toISOString()
            });
        }
        
        function log(message, level = 'info') {
            const logDiv = document.getElementById('log');
            const timestamp = new Date().toLocaleTimeString();
            const logEntry = \`[\${timestamp}] \${message}\`;
            
            const div = document.createElement('div');
            div.textContent = logEntry;
            if (level === 'error') div.style.color = '#ff0000';
            if (level === 'warn') div.style.color = '#ffff00';
            
            logDiv.appendChild(div);
            logDiv.scrollTop = logDiv.scrollHeight;
        }
        
        // Initial connection
        socket.on('connect', () => {
            log('🔌 Connected to monitoring dashboard');
        });
        
        socket.on('disconnect', () => {
            log('❌ Disconnected from dashboard', 'error');
        });
    </script>
</body>
</html>`;
  }

  /**
   * Start the monitoring dashboard
   */
  async start() {
    console.log('📊 Starting Monitoring Dashboard...'.cyan.bold);
    
    try {
      this.server.listen(this.port, () => {
        console.log(`✅ Dashboard running on http://localhost:${this.port}`.green);
        console.log(`📊 Real-time monitoring active`.blue);
        console.log(`🔄 Update interval: ${this.monitoringInterval/1000}s`.gray);
      });

      // Start monitoring loop
      this.startMonitoring();
      
    } catch (error) {
      console.error('❌ Failed to start dashboard:', error.message);
      throw error;
    }
  }

  /**
   * Start the monitoring loop
   */
  startMonitoring() {
    console.log('🎯 Monitoring bridge server health...'.blue);
    
    setInterval(async () => {
      await this.collectMetrics();
      
      // Broadcast metrics to all connected clients
      this.io.emit('metrics', this.metrics);
      
    }, this.monitoringInterval);

    // Initial metrics collection
    this.collectMetrics();
  }

  /**
   * Collect all monitoring metrics
   */
  async collectMetrics() {
    try {
      // Update timestamp
      this.metrics.timestamp = Date.now();
      
      // Check bridge server health
      await this.checkBridgeHealth();
      
      // Collect system metrics
      this.collectSystemMetrics();
      
      // Show status in console
      this.displayConsoleStatus();
      
    } catch (error) {
      console.error(`\n⚠️ Metrics collection error: ${error.message}`);
    }
  }

  /**
   * Check bridge server health
   */
  async checkBridgeHealth() {
    try {
      const start = Date.now();
      
      const response = await axios.get(
        `https://${config.BRIDGE_HOST}${config.ENDPOINTS.DEBUG}`,
        {
          timeout: 10000,
          validateStatus: (status) => status < 500,
          headers: {
            'User-Agent': config.SECURITY.USER_AGENT
          }
        }
      );
      
      const responseTime = Date.now() - start;
      
      this.metrics.bridgeServer = {
        status: response.status < 400 ? 'healthy' : 'degraded',
        responseTime,
        lastCheck: new Date().toISOString(),
        statusCode: response.status
      };
      
    } catch (error) {
      this.metrics.bridgeServer = {
        status: 'unhealthy',
        responseTime: null,
        lastCheck: new Date().toISOString(),
        error: error.message
      };
    }
  }

  /**
   * Collect system resource metrics
   */
  collectSystemMetrics() {
    const used = process.memoryUsage();
    
    this.metrics.systemHealth = {
      memory: {
        rss: Math.round(used.rss / 1024 / 1024 * 100) / 100,
        heapTotal: Math.round(used.heapTotal / 1024 / 1024 * 100) / 100,
        heapUsed: Math.round(used.heapUsed / 1024 / 1024 * 100) / 100,
        external: Math.round(used.external / 1024 / 1024 * 100) / 100
      },
      uptime: Math.round(process.uptime()),
      connections: this.io.engine.clientsCount,
      timestamp: new Date().toISOString()
    };
  }

  /**
   * Display status in console
   */
  displayConsoleStatus() {
    const bridge = this.metrics.bridgeServer;
    const memory = this.metrics.systemHealth.memory;
    const clients = this.metrics.systemHealth.connections;
    
    let statusColor = 'green';
    if (bridge.status === 'degraded') statusColor = 'yellow';
    if (bridge.status === 'unhealthy') statusColor = 'red';
    
    const status = bridge.status.toUpperCase()[statusColor];
    const responseTime = bridge.responseTime ? `${bridge.responseTime}ms` : 'N/A';
    const memoryUsage = `${memory.heapUsed}MB`;
    
    process.stdout.write(`\r📊 Bridge: ${status} (${responseTime}) | Memory: ${memoryUsage} | Dashboard Clients: ${clients}        `);
  }

  /**
   * Stop the dashboard
   */
  async stop() {
    console.log('\n🛑 Stopping monitoring dashboard...'.yellow);
    
    return new Promise((resolve) => {
      this.server.close(() => {
        console.log('✅ Dashboard stopped'.green);
        resolve();
      });
    });
  }
}

// CLI interface
if (require.main === module) {
  const argv = yargs
    .option('port', {
      alias: 'p',
      type: 'number',
      default: 3000,
      description: 'Dashboard port'
    })
    .option('interval', {
      alias: 'i',
      type: 'number',
      default: 5000,
      description: 'Monitoring interval in milliseconds'
    })
    .help()
    .argv;

  const dashboard = new MonitoringDashboard(argv);
  
  // Handle graceful shutdown
  process.on('SIGINT', async () => {
    console.log('\n🛑 Received SIGINT, shutting down dashboard...');
    await dashboard.stop();
    process.exit(0);
  });
  
  dashboard.start().catch(error => {
    console.error('❌ Dashboard failed:', error.message);
    process.exit(1);
  });
}

module.exports = MonitoringDashboard;