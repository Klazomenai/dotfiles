# Tool Versions

Version-pinned external tools installed in `~/bin/` with symlink pattern.

| Tool | Version | Installed | Purpose |
|------|---------|-----------|---------|
| kubectx | v0.9.5 | 2025-10-29 | Fast kubernetes context switching |
| kubens | v0.9.5 | 2025-10-29 | Fast kubernetes namespace switching |
| stern | v1.33.0 | 2025-10-29 | Multi-pod log tailing with regex patterns |
| k9s | v0.50.16 | 2025-10-29 | Terminal UI for kubernetes cluster management |
| helm | v3.11.1 | 2025-10-29 | Kubernetes package manager, compatible with Autonity helm charts |
| istioctl | v1.27.3 | 2025-11-05 | Istio service mesh CLI for debugging and configuration |

## Installation Pattern

Most tools follow this pattern:
- Binary installed as `~/bin/{tool}-v{version}`
- Symlink created as `~/bin/{tool} -> {tool}-v{version}`
- Completions generated in `completions/_{tool}`

Exceptions:
- istioctl: Installed in `~/.istioctl/bin/` (official istioctl installation path)

## Version Compatibility

- Helm v3.11.1 is pinned to match Autonity helm chart requirements
- All other tools use latest stable versions as of installation date

## Verification

Check installed versions:

```bash
kubectx --version
kubens --version
stern --version
k9s version
helm version --short
istioctl version --remote=false
```
