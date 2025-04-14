.PHONY: all test clean deploy build install update help deploy-sepolia deploy-mainnet upgrade-sepolia upgrade-mainnet

all: clean install update build test

# Clean the build artifacts
clean:
	forge clean

# Install dependencies
install:
	forge install

# Update dependencies
update:
	forge update

# Build the project
build:
	forge build

# Run tests
test:
	forge test -vv

# Run tests with gas report
test-gas:
	forge test --gas-report

# Run coverage report
coverage:
	forge coverage

# Format code
format:
	forge fmt

# Run slither analysis
slither:
	slither .

# Deploy to Base Sepolia
deploy-sepolia:
	@echo "Deploying to Base Sepolia..."
	forge script script/DeployPoolFactory.s.sol:DeployPoolFactory \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		-vvvv

# Deploy to Base Mainnet
deploy-mainnet:
	@echo "Deploying to Base Mainnet..."
	@echo "Are you sure you want to deploy to mainnet? [y/N]" && read ans && [ $${ans:-N} = y ]
	forge script script/DeployPoolFactory.s.sol:DeployPoolFactory \
		--rpc-url $(MAINNET_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		-vvvv

# Upgrade on Base Sepolia
upgrade-sepolia:
	@echo "Upgrading on Base Sepolia..."
	forge script script/UpgradePoolFactory.s.sol:UpgradePoolFactory \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvvv

# Upgrade on Base Mainnet
upgrade-mainnet:
	@echo "Upgrading on Base Mainnet..."
	@echo "Are you sure you want to upgrade on mainnet? [y/N]" && read ans && [ $${ans:-N} = y ]
	forge script script/UpgradePoolFactory.s.sol:UpgradePoolFactory \
		--rpc-url $(MAINNET_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		-vvvv

# Help command to display available commands
help:
	@echo "Available commands:"
	@echo "  make all              - Clean, install dependencies, update, build, and test"
	@echo "  make clean            - Remove build artifacts"
	@echo "  make install          - Install dependencies"
	@echo "  make update           - Update dependencies"
	@echo "  make build            - Build the project"
	@echo "  make test             - Run tests"
	@echo "  make test-gas         - Run tests with gas reporting"
	@echo "  make coverage         - Generate coverage report"
	@echo "  make format           - Format code"
	@echo "  make slither          - Run slither analysis"
	@echo "  make deploy-sepolia   - Deploy contracts to Base Sepolia"
	@echo "  make deploy-mainnet   - Deploy contracts to Base Mainnet"
	@echo "  make upgrade-sepolia  - Upgrade contracts on Base Sepolia"
	@echo "  make upgrade-mainnet  - Upgrade contracts on Base Mainnet" 
	