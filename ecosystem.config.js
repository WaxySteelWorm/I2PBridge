module.exports = {
  apps: [
    {
      name: 'i2p-bridge',
      script: 'flutter',
      args: 'run lib/main.dart',
      cwd: '/Users/dustinfields/git/i2p_bridge',
      env: {
        NODE_ENV: 'production'
      }
    },
    {
      name: 'i2p-bridge-debug',
      script: 'flutter',
      args: 'run lib/main.dart -- --debug',
      cwd: '/Users/dustinfields/git/i2p_bridge',
      env: {
        NODE_ENV: 'development'
      }
    }
  ]
};