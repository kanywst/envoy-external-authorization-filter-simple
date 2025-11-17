#!/bin/bash

# Envoy External Authorization Filter Simple PoC Test Script

set -e

BASE_URL="http://localhost:8080"

echo "=== Envoy External Authorization Filter Simple PoC Test ==="
echo ""

# Health Check
echo "1. Health Check (No Authentication):"
response=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/health")
if [ "$response" == "200" ]; then
    echo "✅ PASS - Health Check Successful (HTTP $response)"
else
    echo "❌ FAIL - Health Check Failed (HTTP $response)"
fi
echo ""

# Access Protected Resource Without Authentication
echo "2. Access API Without Authentication (Expect 403):"
response=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/test")
if [ "$response" == "403" ]; then
    echo "✅ PASS - Access Denied Without Authentication (HTTP $response)"
else
    echo "❌ FAIL - Unexpected Response (HTTP $response)"
fi
echo ""

# Access with Valid Token
echo "3. Access API With Valid Token (Expect 200):"
response=$(curl -s -H "Authorization: Bearer test-token" -o /dev/null -w "%{http_code}" "$BASE_URL/api/test")
if [ "$response" == "200" ]; then
    echo "✅ PASS - Access Successful With Valid Token (HTTP $response)"
else
    echo "❌ FAIL - Unexpected Response (HTTP $response)"
fi
echo ""

# Access with Admin Token
echo "4. Access API With Admin Token (Expect 200):"
response=$(curl -s -H "Authorization: Bearer admin-token" -o /dev/null -w "%{http_code}" "$BASE_URL/api/test")
if [ "$response" == "200" ]; then
    echo "✅ PASS - Access Successful With Admin Token (HTTP $response)"
else
    echo "❌ FAIL - Unexpected Response (HTTP $response)"
fi
echo ""

# Access with Invalid Token
echo "5. Access API With Invalid Token (Expect 403):"
response=$(curl -s -H "Authorization: Bearer invalid-token" -o /dev/null -w "%{http_code}" "$BASE_URL/api/test")
if [ "$response" == "403" ]; then
    echo "✅ PASS - Access Denied With Invalid Token (HTTP $response)"
else
    echo "❌ FAIL - Unexpected Response (HTTP $response)"
fi
echo ""

# Access with GET Request (Authenticated User)
echo "6. Access with GET Request (Authenticated User):"
response=$(curl -s -H "Authorization: Bearer test-token" -o /dev/null -w "%{http_code}" "$BASE_URL/")
if [ "$response" == "200" ]; then
    echo "✅ PASS - Access Successful With GET Request (HTTP $response)"
else
    echo "❌ FAIL - Unexpected Response (HTTP $response)"
fi
echo ""

# OPA Endpoint Test
echo "7. Access OPA Endpoint:"
response=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/v1/data")
if [ "$response" == "200" ]; then
    echo "✅ PASS - Access Successful To OPA Endpoint (HTTP $response)"
else
    echo "❌ FAIL - Unexpected Response From OPA Endpoint (HTTP $response)"
fi
echo ""

echo "=== Test Completed ==="
echo ""
echo "To check detailed responses:"
echo "curl -v -H \"Authorization: Bearer test-token\" $BASE_URL/api/test"
echo ""
echo "Envoy Admin Interface:"
echo "curl http://localhost:9901/stats"
