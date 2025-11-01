# Kubectl-specific configuration
# Note: kube-ps1 configuration is in dot_zshrc (must be set before plugins load)

# Additional kubectl aliases beyond oh-my-zsh kubectl plugin
# The kubectl plugin provides 100+ aliases with auto-completion

# Quick context and namespace switching
alias kctx='kubectl config current-context'
alias kns='kubectl config view --minify --output "jsonpath={..namespace}"'

# Pod operations
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods --all-namespaces'
alias kdp='kubectl describe pod'
alias kdelp='kubectl delete pod'

# Logs shortcuts
alias klf='kubectl logs -f'
alias kl='kubectl logs'

# Get all resources
alias kga='kubectl get all'
alias kgaa='kubectl get all --all-namespaces'

# Quick exec into pod
kexec() {
    kubectl exec -it "$1" -- /bin/bash
}

# Quick port forward
# kpf is already defined by oh-my-zsh kubectl plugin
kforward() {
    kubectl port-forward "$1" "$2"
}

# Watch pods
alias kwp='watch kubectl get pods'
