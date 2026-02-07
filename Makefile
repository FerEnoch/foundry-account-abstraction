.PHONY: all build build-evm build-zksync test test-evm test-zksync clean install help

# Suppress common zkSync warnings
SUPPRESS_WARNINGS := --suppress-warnings txorigin,assemblycreate

# Default target
all: build

# ============== Build Commands ==============

## Build all (EVM + zkSync)
build: build-evm build-zksync

## Build EVM contracts only
build-evm:
	@echo "Building EVM contracts..."
	forge build $(SUPPRESS_WARNINGS)

## Build zkSync contracts only
build-zksync:
	@echo "Building zkSync contracts..."
	FOUNDRY_PROFILE=zksync forge build --zksync $(SUPPRESS_WARNINGS) --system-mode=true

# ============== Test Commands ==============

## Run all tests (EVM + zkSync)
test: test-evm test-zksync

## Run EVM tests only
test-evm:
	@echo "Running EVM tests..."
	forge test $(SUPPRESS_WARNINGS)

## Run zkSync tests only (requires both EVM and zkSync artifacts)
test-zksync:
	@echo "Running zkSync tests..." 
	FOUNDRY_PROFILE=zksync forge test --zksync $(SUPPRESS_WARNINGS) --system-mode=true

## Run zkSync tests with verbose output
test-zksync-v:
	@echo "Running zkSync tests (verbose)..."
	FOUNDRY_PROFILE=zksync forge test --zksync $(SUPPRESS_WARNINGS) -vvvv --system-mode=true

## Run a specific zkSync test
test-zksync-match:
	@if [ -z "$(MATCH)" ]; then \
		echo "Error: MATCH variable is required. Usage: make test-zksync-match MATCH=<pattern>"; \
		exit 1; \
	fi
	@echo "Running zkSync test matching: $(MATCH)"
	FOUNDRY_PROFILE=zksync forge test --zksync $(SUPPRESS_WARNINGS) --match-test $(MATCH) -vvvv --system-mode=true

# ============== Utility Commands ==============

## Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	forge clean
	rm -rf zkout cache

## Install dependencies
install:
	@echo "Installing dependencies..."
	forge install

## Update dependencies
update:
	@echo "Updating dependencies..."
	forge update

## Format code
fmt:
	@echo "Formatting code..."
	forge fmt

## Check formatting
fmt-check:
	@echo "Checking formatting..."
	forge fmt --check

## Run gas snapshots for zkSync
snapshot-zksync: build
	@echo "Creating gas snapshot for zkSync..."
	FOUNDRY_PROFILE=zksync forge snapshot --zksync $(SUPPRESS_WARNINGS)

# ============== Help ==============

## Show this help message
help:
	@echo "Foundry Account Abstraction - Makefile Commands"
	@echo ""
	@echo "Build Commands:"
	@echo "  make build          - Build all contracts (EVM + zkSync)"
	@echo "  make build-evm      - Build EVM contracts only"
	@echo "  make build-zksync   - Build zkSync contracts only"
	@echo ""
	@echo "Test Commands:"
	@echo "  make test           - Run all tests (EVM + zkSync)"
	@echo "  make test-evm       - Run EVM tests only"
	@echo "  make test-zksync    - Run zkSync tests"
	@echo "  make test-zksync-v  - Run zkSync tests (verbose)"
	@echo "  make test-zksync-match MATCH=<pattern> - Run specific zkSync test"
	@echo ""
	@echo "Utility Commands:"
	@echo "  make clean          - Clean build artifacts"
	@echo "  make install        - Install dependencies"
	@echo "  make update         - Update dependencies"
	@echo "  make fmt            - Format code"
	@echo "  make fmt-check      - Check code formatting"
	@echo "  make snapshot-zksync - Create gas snapshot for zkSync"
	@echo ""
	@echo "Examples:"
	@echo "  make test-zksync-match MATCH=testZK__OwnerCanExecuteCommands"
