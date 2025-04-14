## FOF Contracts

Install foundry

```bash
curl -L https://foundry.paradigm.xyz | bash
```

Install dependencies

```bash
forge install
```

### Commands

```bash
# List all commands
make all
```

```bash
# Test
make test
```

```bash
# Deploy base sepolia
export PRIVATE_KEY=0x...
export RPC_URL=https://sepolia.base.org

make deploy-sepolia
```
