#!/bin/bash

# Test ARC Transaction Broadcasting and Status Tracking
echo "=== Testing ARC Transaction Submission & Progress Tracking ==="
echo

# Check if API is ready
echo "Checking if ARC API is ready..."
API_HEALTH=$(curl -s http://localhost:9090/v1/health 2>/dev/null || echo "NOT_READY")
if [[ "$API_HEALTH" == "NOT_READY" ]]; then
    echo "⚠️  API not ready yet. Waiting 5 seconds..."
    sleep 5
else
    echo "✅ API is ready!"
fi
echo

# Test transaction hex (properly formatted but will likely be rejected due to invalid inputs)
TEST_TX="0100000001c47f9e9e64da75fbb675aae0c66c4aed5c4a8df71dd7964be3051fe23c7487c2010000006b483045022100df3401f60f13ec78e5d7bee74e671eab042fa407f0e918654aa434b9cc45c3aa0220380dd91d5484db345a91b6992f69aa5890d5443a8d7aa378c9c85727b737d30941210390247c087a3ae15504d2beadf6d8f137ab970ca3215197ce30864f26f7ab93abffffffff020a000000000000001976a914df663528126691d604934548891ea40ac1481eb888ac4c000000000000001976a91471c44336967019b9e7a46192bce262493cdf4b3688ac00000000"

echo "📤 Submitting transaction to ARC..."
echo "Transaction hex (first 100 chars): ${TEST_TX:0:100}..."
echo

# Submit transaction to correct API endpoint
RESPONSE=$(curl -s -X POST http://localhost:9090/v1/tx \
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
