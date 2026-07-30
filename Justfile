# Justfile - Lab 04 developer commands
# Place this file at the repository root.
#
# COMMON COMMANDS
#   just stack-up                 Start/configure the complete Lab 04 stack
#   just stack-status             Show service and health status
#   just stack-down               Stop this stack and retain persistent state
#   just ignition-list            List running local Ignition containers
#   just ignition-stop-all        Stop all local Ignition containers to avoid port collisions
#   just stack-logs local         Follow local gateway logs (local|test|production)
#   just stack-scan local         Trigger a gateway scan (local|test|production)
#   just repomix                  Create a sanitized repository bundle
#   just setup-python             Create the repository-local uv environment
#   just --list                   Display every available command
#
# DESTRUCTIVE COMMAND
#   just stack-reset              Stop this stack and wipe Lab 04 volumes/state

python_version := "3.12"
repo_name := file_name(justfile_directory())
repomix_output := "repomix-" + repo_name + ".xml"

default:
    @echo "Common commands:"
    @echo "  just stack-up             Start/configure the Lab 04 stack"
    @echo "  just stack-status         Show service and health status"
    @echo "  just stack-down           Stop stack; retain persistent state"
    @echo "  just ignition-list        List running Ignition containers"
    @echo "  just ignition-stop-all    Stop all local Ignition containers"
    @echo "  just stack-logs local     Follow gateway logs"
    @echo "  just stack-scan local     Trigger a gateway scan"
    @echo "  just repomix              Create sanitized Repomix XML"
    @echo "  just setup-python         Initialize Python with uv"
    @echo ""
    @echo "All commands:"
    @just --list

# =============================================================================
# STACK LIFECYCLE - LAB 04
# =============================================================================

# Run the lab's idempotent setup: preflight, environment, keys, gateways, DB, and initial scan.
stack-up:
    scripts/setup.sh

# Show this repository's Compose services and health.
stack-status:
    docker compose ps

# Stop this repository's Compose stack but retain persistent volumes and state.
stack-down:
    scripts/teardown.sh

# Restart every service in this repository's Compose stack.
stack-restart:
    docker compose restart

# Stop this stack and wipe its persistent volumes and test/production host state.
# The repository script presents its own destructive-action confirmation.
stack-reset:
    scripts/teardown.sh --volumes

# Validate the Compose model without starting containers.
stack-config:
    docker compose config -q
    @echo "Compose configuration is valid"

# Display the host ports used by this Lab 04 stack.
stack-ports:
    @echo "Lab 04 expected host ports:"
    @echo "  8088 local gateway"
    @echo "  8089 test gateway"
    @echo "  8090 production gateway"
    @echo "  5432 TimescaleDB"
    @docker compose ps

# =============================================================================
# IGNITION OPERATIONS
# =============================================================================

# List running local Docker containers whose name contains 'ignition'.
ignition-list:
    @docker ps --filter name=ignition --format "table {{'{{'}}.Names{{'}}'}}\t{{'{{'}}.Image{{'}}'}}\t{{'{{'}}.Status{{'}}'}}\t{{'{{'}}.Ports{{'}}'}}"

# Stop every running local Docker container whose name contains 'ignition'.
# Scope: current Docker context only. Containers and volumes are not deleted.
ignition-stop-all:
    @ids="$$(docker ps -q --filter name=ignition)"; \
      if [ -z "$$ids" ]; then \
        echo "No running Ignition containers found in the current Docker context"; \
      else \
        echo "Stopping these local Ignition containers:"; \
        docker ps --filter name=ignition --format "table {{'{{'}}.Names{{'}}'}}\t{{'{{'}}.Image{{'}}'}}\t{{'{{'}}.Ports{{'}}'}}"; \
        docker stop $$ids; \
      fi

# Follow logs for a gateway: local, test, or production.
stack-logs gateway="local":
    @case "{{gateway}}" in local|test|production) ;; *) echo "Gateway must be: local, test, or production"; exit 2;; esac
    docker logs -f "lab04-ignition-{{gateway}}"

# Trigger the repository scan script for local, test, or production.
stack-scan gateway="local":
    @case "{{gateway}}" in local|test|production) ;; *) echo "Gateway must be: local, test, or production"; exit 2;; esac
    scripts/scan.sh "{{gateway}}"

# Stop one Docker container by its exact name.
# Example: just container-stop lab03-ignition
container-stop name:
    @if ! docker container inspect "{{name}}" >/dev/null 2>&1; then \
        echo "Container '{{name}}' does not exist"; \
        exit 1; \
    fi
    @state="$$(docker container inspect --format '{{"{{"}}.State.Status{{"}}"}}' "{{name}}")"; \
      if [ "$$state" != "running" ]; then \
        echo "Container '{{name}}' is already $$state"; \
      else \
        echo "Stopping container '{{name}}'..."; \
        docker stop "{{name}}"; \
      fi

# =============================================================================
# REPOSITORY BUNDLING - REPOMIX
# =============================================================================

# Generate a sanitized XML bundle using the Repomix container.
repomix:
    docker run --rm \
      -v "{{justfile_directory()}}:/app" \
      -w /app \
      ghcr.io/yamadashy/repomix:latest \
      --style xml \
      --ignore ".env,.env.*,**/.resources/**,.venv/**,repomix-*.xml" \
      --output "{{repomix_output}}"
    @echo "Created {{repomix_output}}"
    @ls -lh "{{repomix_output}}"

# Review possible sensitive terms before sharing the Repomix output.
scan-repomix:
    @if [ ! -f "{{repomix_output}}" ]; then echo "Missing {{repomix_output}}; run: just repomix"; exit 1; fi
    @echo "Review every match before sharing:"
    @grep -Ein 'password|token|secret|api[_-]?key|private[_-]?key|authorization' "{{repomix_output}}" | head -n 50 || echo "No obvious sensitive terms found"

# =============================================================================
# PYTHON ENVIRONMENT - UV
# =============================================================================

# Install/pin Python and create the repository-local uv environment.
setup-python:
    uv python install {{python_version}}
    uv python pin {{python_version}}
    uv venv --python {{python_version}}
    @if [ -f pyproject.toml ]; then echo "Installing pyproject dependencies"; uv sync; fi
    @if [ -f requirements.txt ]; then echo "Installing requirements.txt"; uv pip install -r requirements.txt; fi
    @if [ -f requirements-dev.txt ]; then echo "Installing requirements-dev.txt"; uv pip install -r requirements-dev.txt; fi
    @echo "Python environment ready"
    uv run python --version

# Remove only generated local Python environment files.
clean-python:
    rm -rf .venv .python-version
    @echo "Removed .venv and .python-version"

# =============================================================================
# VALIDATION AND TESTING
# =============================================================================

# Run Lab 04's supplied preflight test harness (unit tests, no Docker layer).
test-preflight:
    scripts/test-preflight.sh

# Run Lab 04's preflight test harness including Docker-based tests.
test-preflight-docker:
    scripts/test-preflight.sh --docker

# Display the active toolchain.
verify:
    @echo "Repository: {{repo_name}}"
    @echo "uv:"; uv --version
    @echo "Python:"; uv run python --version
    @echo "Docker:"; docker --version
    @echo "Docker Compose:"; docker compose version
    @echo "Git:"; git --version
