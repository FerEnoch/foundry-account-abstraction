# Foundry Account Abstraction

This is an educational project based on the Cyfrin Updraft curriculum.

## Original Course

This project follows the course materials from the official Cyfrin Updraft repository: [github.com/cyfrin](https://github.com/cyfrin)

## About

This repository contains the implementation and exercises for learning account abstraction concepts using Foundry.

## Documentation

For more information about Foundry, visit: https://book.getfoundry.sh/

## Usage

This project includes a Makefile for convenient command execution. You can use either `make` commands or direct `forge` commands.

### Makefile Commands

#### Build Commands

```shell
make build          # Build all contracts (EVM + zkSync)
make build-evm      # Build EVM contracts only
make build-zksync   # Build zkSync contracts only
```

#### Test Commands

```shell
make test           # Run all tests (EVM + zkSync)
make test-evm       # Run EVM tests only
make test-zksync    # Run zkSync tests
make test-zksync-v  # Run zkSync tests with verbose output
make test-zksync-match MATCH=<pattern>  # Run specific zkSync test
```

Example:
```shell
make test-zksync-match MATCH=testZK__OwnerCanExecuteCommands
```

#### Utility Commands

```shell
make clean          # Clean build artifacts
make install        # Install dependencies
make update         # Update dependencies
make fmt            # Format code
make fmt-check      # Check code formatting
make snapshot-zksync # Create gas snapshot for zkSync
make help           # Show all available commands
```

### Direct Forge Commands

```shell
forge build
forge test
forge fmt
forge snapshot
anvil
```

### Help

```shell
forge --help
anvil --help
cast --help
make help
```
