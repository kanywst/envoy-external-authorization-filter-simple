.PHONY: help deploy k8s-clean test clean port-forward

help:
	@echo "Envoy External Authorization Filter Simple PoC"
	@echo ""
	@echo "Available targets:"
	@echo "  deploy   - Deploy to Kubernetes"
	@echo "  k8s-clean    - Delete resources from Kubernetes"
	@echo "  test         - Run tests"
	@echo "  clean        - Clean up all resources"

deploy:
	@echo "Deploying to Kubernetes..."
	kubectl apply -f kubernetes/namespace.yaml
	kubectl apply -f kubernetes/configmap.yaml
	kubectl apply -f kubernetes/deployment.yaml
	kubectl apply -f kubernetes/service.yaml
	@echo "Deploy complete. Waiting for pods to be ready..."
	kubectl wait --for=condition=ready pod -l app=envoy-ext-authz-opa -n envoy-authz-poc --timeout=60s
	@echo "All pods are up and running."

k8s-clean:
	@echo "Deleting resources from Kubernetes..."
	kubectl delete -f kubernetes/service.yaml --ignore-not-found=true
	kubectl delete -f kubernetes/deployment.yaml --ignore-not-found=true
	kubectl delete -f kubernetes/configmap.yaml --ignore-not-found=true
	kubectl delete -f kubernetes/namespace.yaml --ignore-not-found=true

port-forward:
	@echo "Starting port-forward to envoy-entrypoint..."
	kubectl port-forward -n envoy-authz-poc service/envoy-entrypoint 8080:8080

test:
	@echo "Checking connection to localhost:8080..."
	@# Check if port-forward is running
	@curl -s http://localhost:8080/health > /dev/null || (echo "❌ Error: Cannot connect to localhost:8080. Please run 'make port-forward' in a separate terminal." && exit 1)
	@echo "✅ Connection established. Running tests..."
	@echo "--------------------------------------------------"

	@echo "1. Health check (no authentication)"
	@echo "   Expect: 200 OK"
	@CODE=$$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health); \
	if [ "$$CODE" -eq 200 ]; then echo "   Result: $$CODE [PASS]"; else echo "   Result: $$CODE [FAIL]"; fi
	@echo ""

	@echo "2. API access without authentication"
	@echo "   Expect: 403 Forbidden"
	@CODE=$$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/test); \
	if [ "$$CODE" -eq 403 ]; then echo "   Result: $$CODE [PASS]"; else echo "   Result: $$CODE [FAIL]"; fi
	@echo ""

	@echo "3. API access with valid token"
	@echo "   Expect: 200 OK"
	@CODE=$$(curl -s -H "Authorization: Bearer test-token" -o /dev/null -w "%{http_code}" http://localhost:8080/api/test); \
	if [ "$$CODE" -eq 200 ]; then echo "   Result: $$CODE [PASS]"; else echo "   Result: $$CODE [FAIL]"; fi
	@echo ""

	@echo "4. API access with admin token"
	@echo "   Expect: 200 OK"
	@CODE=$$(curl -s -H "Authorization: Bearer admin-token" -o /dev/null -w "%{http_code}" http://localhost:8080/api/test); \
	if [ "$$CODE" -eq 200 ]; then echo "   Result: $$CODE [PASS]"; else echo "   Result: $$CODE [FAIL]"; fi
	@echo "--------------------------------------------------"
