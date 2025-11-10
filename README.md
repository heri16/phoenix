# Phoenix

This repository contains core smart contracts of Cork Phoenix.

# Build

Install toolchain manager (mise)

```bash
curl --proto '=https' --tlsv1.2 https://mise.run | sh
bash
eval "$(mise activate bash)"
```

Install toolchains (forge)

```bash
mise install -y
```

Install library dependencies (lib)

```bash
forge install
```

To build & compile all contracts for testing purposes run :

```bash
forge build
```

### Deployment Build
For production you need to use the optimized build with IR compilation turned on by setting the `FOUNDRY_PROFILE` environment variable to `optimized`:
```bash
FOUNDRY_PROFILE=optimized forge build
```

# Tests

To run test, use this command :

```bash
forge test
```