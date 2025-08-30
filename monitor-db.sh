#!/bin/bash

echo "=== ARC Database Monitor ==="
echo

# Check metamorph transactions table
echo "--- Metamorph Transactions ---"
psql -d metamorph -c "
SELECT 
    encode(hash, 'hex') as txid,
    status,
    block_height,
    stored_at,
    last_submitted_at,
    retries
FROM metamorph.transactions 
ORDER BY stored_at DESC 
LIMIT 10;
"

echo
echo "--- BlockTx Registered Transactions ---"
psql -d blocktx -c "
SELECT 
    encode(hash, 'hex') as txid,
    inserted_at
FROM blocktx.registered_transactions 
ORDER BY inserted_at DESC 
LIMIT 10;
"

echo
echo "--- BlockTx Blocks ---"
psql -d blocktx -c "
SELECT 
    height,
    encode(hash, 'hex') as block_hash,
    processed_at
FROM blocktx.blocks 
ORDER BY height DESC 
LIMIT 5;
"

echo
echo "--- Callbacker Queue ---"
psql -d callbacker -c "\dt" | head -5
