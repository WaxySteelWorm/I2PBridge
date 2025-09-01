// Example script showing how to use the stress testing components individually

const HttpStressTest = require('./http-stress-test');
const IrcStressTest = require('./irc-stress-test');
const UploadStressTest = require('./upload-stress-test');
const TestOrchestrator = require('./test-orchestrator');
const MonitoringDashboard = require('./monitoring-dashboard');

async function exampleUsage() {
  console.log('🧪 I2P Bridge Stress Testing Examples\n');

  try {
    // Example 1: Simple HTTP test
    console.log('Example 1: Simple HTTP browsing test');
    const httpTest = new HttpStressTest({
      users: 5,
      duration: 30,
      verbose: true
    });
    
    const httpResults = await httpTest.run();
    console.log('HTTP Test Results:', httpResults);

    // Wait between tests
    await new Promise(resolve => setTimeout(resolve, 5000));

    // Example 2: IRC test with custom parameters
    console.log('\nExample 2: IRC connection test');
    const ircTest = new IrcStressTest({
      users: 3,
      duration: 60,
      verbose: false
    });
    
    const ircResults = await ircTest.run();
    console.log('IRC Test Results:', ircResults);

    // Wait between tests
    await new Promise(resolve => setTimeout(resolve, 5000));

    // Example 3: Upload test
    console.log('\nExample 3: File upload test');
    const uploadTest = new UploadStressTest({
      users: 2,
      duration: 45,
      verbose: true
    });
    
    const uploadResults = await uploadTest.run();
    console.log('Upload Test Results:', uploadResults);

    // Example 4: Orchestrated test (all services)
    console.log('\nExample 4: Orchestrated multi-service test');
    const orchestrator = new TestOrchestrator({
      users: 15,
      duration: 90,
      tests: ['http', 'irc', 'upload'],
      verbose: false
    });
    
    const combinedResults = await orchestrator.run();
    console.log('Combined Test Results:', combinedResults);

    console.log('\n✅ All example tests completed successfully!');

  } catch (error) {
    console.error('❌ Example test failed:', error.message);
    process.exit(1);
  }
}

// Example of starting monitoring dashboard programmatically
async function startDashboardExample() {
  console.log('📊 Starting monitoring dashboard example...');
  
  const dashboard = new MonitoringDashboard({
    port: 3001,
    interval: 3000
  });
  
  await dashboard.start();
  
  console.log('Dashboard running on http://localhost:3001');
  console.log('Press Ctrl+C to stop');
  
  // Keep running until interrupted
  process.on('SIGINT', async () => {
    console.log('\n🛑 Stopping dashboard...');
    await dashboard.stop();
    process.exit(0);
  });
}

// Example of custom test configuration
async function customTestExample() {
  console.log('🎯 Custom test configuration example...');
  
  // Custom HTTP test targeting specific sites
  const customHttpTest = new HttpStressTest({
    users: 20,
    duration: 180,
    verbose: true
  });
  
  // Override the site selection for focused testing
  const originalGetRandomUrl = customHttpTest.getRandomI2pUrl;
  customHttpTest.getRandomI2pUrl = function() {
    // Focus testing on shinobi.i2p search functionality
    const queries = ['privacy', 'security', 'anonymity', 'encryption'];
    const randomQuery = queries[Math.floor(Math.random() * queries.length)];
    return `http://shinobi.i2p/search?query=${encodeURIComponent(randomQuery)}`;
  };
  
  console.log('Running focused search engine stress test...');
  const results = await customHttpTest.run();
  
  console.log('Search engine stress test completed');
  return results;
}

// Main execution
if (require.main === module) {
  const args = process.argv.slice(2);
  
  if (args.includes('--dashboard')) {
    startDashboardExample();
  } else if (args.includes('--custom')) {
    customTestExample();
  } else {
    exampleUsage();
  }
}

module.exports = {
  HttpStressTest,
  IrcStressTest, 
  UploadStressTest,
  TestOrchestrator,
  MonitoringDashboard
};