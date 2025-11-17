package envoy.authz

import rego.v1

# Default deny
default allow := false

# Authentication Settings
# In the actual PoC, implement JWT token verification logic here
allow if {
    # Check if a bearer token exists
    token := input.attributes.request.http.headers.authorization
    startswith(token, "Bearer ")

    # Simplified Authentication: Treat “test-token” as a valid token
    token == "Bearer test-token"
}

# Users with administrator privileges have access to all resources.
allow if {
    input.attributes.request.http.headers.authorization == "Bearer admin-token"
}

# Specific paths are accessible without authentication
allow if {
    public_paths := {"/health", "/v1/data"}
    input.attributes.request.http.path in public_paths
}

# Read-only operations are possible for authenticated users.
allow if {
    input.attributes.request.http.method == "GET"
    token := input.attributes.request.http.headers.authorization
    startswith(token, "Bearer ")
    token != ""
}

# For debugging: Log request information
debug_info := {
    "method": input.attributes.request.http.method,
    "path": input.attributes.request.http.path,
    "headers": input.attributes.request.http.headers
}
