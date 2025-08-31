#!/usr/bin/env node

const crypto = require('crypto');
const sqlite3 = require('sqlite3').verbose();
const path = require('path');

// The API key from the dashboard
const apiKey = 'b79946fde96aadc7a3cb32bc170c98ae63fab7e832b1545080cfb89cc3c1d9ce';
const expectedHash = crypto.createHash('sha256').update(apiKey).digest('hex');

console.log('Checking API key:', apiKey);
console.log('Expected hash:', expectedHash);

// Open database
const dbPath = path.join(__dirname, 'bridge_stats.db');
const db = new sqlite3.Database(dbPath);

db.serialize(() => {
  // Check if the API key exists
  db.get(
    `SELECT key_id, key_hash, description, is_active, created_at FROM api_keys WHERE key_hash = ?`,
    [expectedHash],
    (err, row) => {
      if (err) {
        console.error('Error checking API key:', err);
      } else if (row) {
        console.log('\n✅ API key found in database:');
        console.log('  Key ID:', row.key_id);
        console.log('  Description:', row.description);
        console.log('  Is Active:', row.is_active ? 'YES' : 'NO');
        console.log('  Created:', new Date(row.created_at).toLocaleString());
        
        if (!row.is_active) {
          console.log('\n⚠️  WARNING: This API key is DISABLED!');
          console.log('Enabling the API key...');
          
          // Enable the API key
          db.run(
            `UPDATE api_keys SET is_active = 1 WHERE key_hash = ?`,
            [expectedHash],
            (err) => {
              if (err) {
                console.error('Error enabling API key:', err);
              } else {
                console.log('✅ API key has been enabled!');
              }
              db.close();
            }
          );
        } else {
          console.log('\n✅ API key is active and ready to use!');
          db.close();
        }
      } else {
        console.log('\n❌ API key NOT found in database!');
        console.log('This key needs to be added to the database.');
        
        // Insert the API key
        console.log('Adding API key to database...');
        db.run(
          `INSERT INTO api_keys (key_hash, description, is_active, created_at) VALUES (?, ?, 1, ?)`,
          [expectedHash, 'Flutter App Key', Date.now()],
          (err) => {
            if (err) {
              console.error('Error adding API key:', err);
            } else {
              console.log('✅ API key has been added and activated!');
            }
            db.close();
          }
        );
      }
    }
  );
});