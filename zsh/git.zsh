# Git-specific configuration

# Additional git aliases beyond oh-my-zsh git plugin
# The git plugin provides 177+ aliases like ga, gco, gcb, gpsup, etc.

# Custom git aliases
alias glog='git log --oneline --decorate --graph --all'
alias gclean='git clean -fd'
alias gunstage='git restore --staged'
alias gundo='git reset --soft HEAD~1'

# Git status with branch info
alias gst='git status -sb'

# Show current branch
alias gb='git branch --show-current'

# Quick commit with message - use plugin alias 'gcmsg'
# gcm is already defined by oh-my-zsh git plugin as 'git commit -m'

# Create and checkout new branch
gnewb() {
    git checkout -b "$1"
}
