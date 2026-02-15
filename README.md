# dotfiles

Personal configuration files for shell and tools.

# Files

- `dot_vimrc`, vim editor configuration
- `dot_zshrc`, zsh shell configuration with tmux auto-start
- `dot_tmux.conf`, tmux terminal multiplexer configuration
- `zsh/aliases.zsh`, general shell aliases
- `zsh/git.zsh`, git shortcuts and functions
- `zsh/kubectl.zsh`, kubernetes kubectl shortcuts
- `completions/`, zsh completion scripts
- `claude/`, Claude Code configuration (CLAUDE.md, settings.json, hooks)

# ZSH Plugins

- `git`, 177+ git aliases (ga, gco, gcb, gpsup)
- `gitfast`, enhanced git completion
- `kubectl`, 100+ kubectl aliases with auto-completion
- `kube-ps1`, kubernetes context/namespace in prompt
- `zsh-autosuggestions`, command suggestions from history
- `zsh-syntax-highlighting`, real-time syntax highlighting

# Requirements

- `zsh`, 5.x or later
- `oh-my-zsh`, framework
- `tmux`, terminal multiplexer (auto-starts with zsh)
- `kubectl`, for kubernetes features
- `jq`, required by Claude Code hook scripts
- `gh`, GitHub CLI, required by Claude Code co-author policy hook

# External Tools

- `kubectx`, v0.9.5, fast kubernetes context switching
- `kubens`, v0.9.5, fast kubernetes namespace switching
- `stern`, v1.33.0, multi-pod log tailing with regex
- `k9s`, v0.50.16, terminal UI for kubernetes clusters
- `helm`, v3.11.1, kubernetes package manager

# Setup

- Install zsh and oh-my-zsh:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

- Install custom plugins:

```
git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
```

- Create config directory and symlink files:

```
mkdir -p ~/.config/zsh
ln -sf ~/path/to/dotfiles/dot_zshrc ~/.zshrc
ln -sf ~/path/to/dotfiles/dot_vimrc ~/.vimrc
ln -sf ~/path/to/dotfiles/dot_tmux.conf ~/.tmux.conf
ln -sf ~/path/to/dotfiles/zsh/aliases.zsh ~/.config/zsh/aliases.zsh
ln -sf ~/path/to/dotfiles/zsh/git.zsh ~/.config/zsh/git.zsh
ln -sf ~/path/to/dotfiles/zsh/kubectl.zsh ~/.config/zsh/kubectl.zsh
ln -sf ~/path/to/dotfiles/completions ~/.config/zsh/completions
```

- Claude Code configuration:

```
make install-claude
```

- Reload shell:

```
source ~/.zshrc
```

# Usage

Tmux:
- Auto-starts when opening a new terminal
- Mouse support enabled for clicking panes, scrolling
- `tmux attach`, attach to existing session
- `tmux detach` or `Ctrl+b d`, detach from session
- `Ctrl+b c`, create new window
- `Ctrl+b n/p`, next/previous window
- `Ctrl+b %`, split pane vertically
- `Ctrl+b "`, split pane horizontally
- Click to select panes or scroll through history

Kubernetes:
- `kubeon`, enable kubernetes prompt
- `kubeoff`, disable kubernetes prompt
- `kubectx`, list or switch kubernetes contexts
- `kubens`, list or switch kubernetes namespaces
- `kctx`, show current kubernetes context
- `kgp`, get pods in current namespace
- `stern <pattern>`, tail logs from multiple pods matching pattern
- `k9s`, interactive terminal UI for cluster management

Git:
- `glog`, pretty git log graph
- `gst`, git status with branch info
- `gnewb <name>`, create and checkout new branch
