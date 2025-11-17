.PHONY: help k8s-deploy k8s-clean test clean

# Default target
help:
	@echo "Envoy External Authorization Filter Simple PoC"
	@echo ""
	@echo "Available targets:"
	@echo "  k8s-deploy   - Deploy to Kubernetes"
	@echo "  k8s-clean    - Delete resources from Kubernetes"
	@echo "  test         - Run tests"
	@echo "  clean        - Clean up all resources"

k8s-deploy:
	@echo "Deploying to Kubernetes..."
	kubectl apply -f kubernetes/namespace.yaml
	kubectl apply -f kubernetes/configmap.yaml
	kubectl apply -f kubernetes/deployment.yaml
	kubectl apply -f kubernetes/service.yaml
	@echo "Deploy complete. Waiting for pods to be ready..."
	kubectl wait --for=condition=ready pod -l app=opa -n envoy-authz-poc --timeout=60s
	kubectl wait --for=condition=ready pod -l app=echo-server -n envoy-authz-poc --timeout=60s
	kubectl wait --for=condition=ready pod -l app=envoy -n envoy-authz-poc --timeout=60s
	@echo "All pods are up and running."
k8s-clean:
	@echo "Deleting resources from Kubernetes..."
	kubectl delete -f kubernetes/service.yaml --ignore-not-found=true
	kubectl delete -f kubernetes/deployment.yaml --ignore-not-found=true
	kubectl delete -f kubernetes/configmap.yaml --ignore-not-found=true
	kubectl delete -f kubernetes/namespace.yaml --ignore-not-found=true

# test
test:
	@echo "Running tests..."
	@echo ""
	@echo "1. Health check (no authentication):"
	curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health || echo "Testing in Docker environment..."
	@echo ""
	@echo "2. API access without authentication (expecting 403):"
	curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/test || echo "Testing in Docker environment..."
	@echo ""
	@echo "3. API access with valid token (expecting 200):"
	curl -s -H "Authorization: Bearer test-token" -o /dev/null -w "%{http_code}" http://localhost:8080/api/test || echo "Testing in Docker environment..."
	@echo ""
	@echo "4. API access with admin token (expecting 200):"
	curl -s -H "Authorization: Bearer admin-token" -o /dev/null -w "%{http_code}" http://localhost:8080/api/test || echo "Testing in Docker environment..."
	@echo ""

# Cleanup
clean: k8s-clean
	@echo "Cleaned up all resources."