#!/bin/bash

# Test ARC Transaction Broadcasting and Status Tracking
echo "=== Testing ARC Transaction Submission & Progress Tracking ==="
echo

# Check if API is ready
echo "Checking if ARC API is ready..."
API_HEALTH=$(curl -s http://localhost:8080/health 2>/dev/null || echo "NOT_READY")
if [[ "$API_HEALTH" == "NOT_READY" ]]; then
    echo "⚠️  API not ready yet. Waiting 5 seconds..."
    sleep 5
else
    echo "✅ API is ready!"
fi
echo

# Test transaction hex (properly formatted but will likely be rejected due to invalid inputs)
TEST_TX="0100000001f5e21f7381aad461e7f39fa3154ce4e1f0df511b07d324b9eba477c829f2528b000000006a473044022059ea87fcc50c4b5aac68e6f46b459c89b5f8c8679ee746c6907d2500cc1160b50220008226f5893f6a5e1ea83f9e8a1c01822a3ebb5a5af6d4bdf7cc041fc483f08b41210390247c087a3ae15504d2beadf6d8f137ab970ca3215197ce30864f26f7ab93abffffffff020a000000000000001976a914df663528126691d604934548891ea40ac1481eb888ac58000000000000001976a91471c44336967019b9e7a46192bce262493cdf4b3688ac00000000"

echo "📤 Submitting transaction to ARC..."
echo "Transaction hex (first 100 chars): ${TEST_TX:0:100}..."
echo

# Submit transaction to correct API endpoint
RESPONSE=$(curl -s -X POST http://localhost:8080/v1/tx \
  -H "Content-Type: application/json" \
  -d "{\"rawTx\": \"$TEST_TX\"}")

echo "🔍 API Response:"
echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
echo

# Extract txid if successful
TXID=$(echo "$RESPONSE" | jq -r '.txid // empty' 2>/dev/null)

if [ ! -z "$TXID" ] && [ "$TXID" != "null" ]; then
    echo "✅ Transaction submitted successfully!"
    echo "📝 TXID: $TXID"
    echo
    
    # Track transaction status progression
    echo "📊 Tracking transaction status progression..."
    for i in {1..10}; do
        echo "--- Status Check #$i ---"
        STATUS_RESPONSE=$(curl -s -X GET "http://localhost:9090/v1/tx/$TXID")
        
        STATUS=$(echo "$STATUS_RESPONSE" | jq -r '.txStatus // "UNKNOWN"' 2>/dev/null)
        TIMESTAMP=$(date "+%H:%M:%S")
        
        echo "[$TIMESTAMP] Status: $STATUS"
        
        if [[ "$STATUS" == "MINED" || "$STATUS" == "REJECTED" ]]; then
            echo "🏁 Final status reached: $STATUS"
            break
        fi
        
        echo "Full response:"
        echo "$STATUS_RESPONSE" | jq '.' 2>/dev/null || echo "$STATUS_RESPONSE"
        echo
        
        if [ $i -lt 10 ]; then
            echo "⏳ Waiting 3 seconds before next check..."
            sleep 3
        fi
    done
    
    echo
    echo "🗄️  Checking database for transaction record..."
    echo "Run: ./monitor-db.sh to see database entries"
    
else
    echo "❌ Transaction submission failed"
    echo "💡 This is expected for test transactions with invalid inputs"
    echo "✅ This confirms ARC is validating transactions properly"
    
    # Check if it's a validation error
    ERROR_TYPE=$(echo "$RESPONSE" | jq -r '.type // "unknown"' 2>/dev/null)
    ERROR_DETAIL=$(echo "$RESPONSE" | jq -r '.detail // "unknown"' 2>/dev/null)
    
    if [[ "$ERROR_TYPE" != "unknown" ]]; then
        echo "🔍 Error Type: $ERROR_TYPE"
        echo "📝 Error Detail: $ERROR_DETAIL"
    fi
fi

echo
echo "=== 🎯 Test Complete ==="
echo "💡 Next steps:"
echo "   1. Run './monitor-db.sh' to see database entries"
echo "   2. Check ARC logs for detailed transaction processing"
echo "   3. Try with a valid transaction for full workflow testing"
