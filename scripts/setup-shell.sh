#!/bin/bash
#
# Setup ZSH with Oh My Zsh and Kubernetes plugins
#
# This script:
#   - Installs zsh if not present
#   - Installs Oh My Zsh
#   - Adds kubectl plugin and aliases
#   - Changes user's default shell to zsh
#
# Usage:
#   ./setup-shell.sh
#

set -e

echo "============================================"
echo "  Shell Setup (ZSH + Oh My Zsh)"
echo "============================================"
echo ""

# Detect current user (handle sudo)
ACTUAL_USER="${SUDO_USER:-$USER}"
ACTUAL_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)

# Install zsh if not present
if ! command -v zsh &> /dev/null; then
    echo "Installing zsh..."
    if command -v apt &> /dev/null; then
        sudo apt update && sudo apt install -y zsh
    elif command -v yum &> /dev/null; then
        sudo yum install -y zsh
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm zsh
    else
        echo "ERROR: Could not detect package manager. Please install zsh manually."
        exit 1
    fi
fi

echo "ZSH version: $(zsh --version)"

# Install Oh My Zsh (as the actual user, not root)
if [ ! -d "${ACTUAL_HOME}/.oh-my-zsh" ]; then
    echo ""
    echo "Installing Oh My Zsh..."
    sudo -u "$ACTUAL_USER" sh -c 'RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
else
    echo "Oh My Zsh already installed"
fi

# Install zsh-autosuggestions plugin
ZSH_CUSTOM="${ACTUAL_HOME}/.oh-my-zsh/custom"
if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]; then
    echo "Installing zsh-autosuggestions..."
    sudo -u "$ACTUAL_USER" git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
fi

# Install zsh-syntax-highlighting plugin
if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]; then
    echo "Installing zsh-syntax-highlighting..."
    sudo -u "$ACTUAL_USER" git clone https://github.com/zsh-users/zsh-syntax-highlighting "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"
fi

# Configure .zshrc
ZSHRC="${ACTUAL_HOME}/.zshrc"
echo ""
echo "Configuring .zshrc..."

# Update plugins line to include kubectl and other useful plugins
if grep -q "^plugins=" "$ZSHRC"; then
    # Replace existing plugins line
    sed -i 's/^plugins=.*/plugins=(git kubectl zsh-autosuggestions zsh-syntax-highlighting)/' "$ZSHRC"
else
    echo 'plugins=(git kubectl zsh-autosuggestions zsh-syntax-highlighting)' >> "$ZSHRC"
fi

# Add kubectl alias and KUBECONFIG if not present
if ! grep -q "alias k=kubectl" "$ZSHRC"; then
    cat >> "$ZSHRC" << 'EOF'

# Kubernetes aliases
alias k=kubectl
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias kga='kubectl get all'
alias kaf='kubectl apply -f'
alias kdel='kubectl delete'
alias klog='kubectl logs'
alias kexec='kubectl exec -it'
alias kctx='kubectl config use-context'
alias kns='kubectl config set-context --current --namespace'

# KUBECONFIG
export KUBECONFIG="$HOME/.kube/config"

# Kubernetes completion
[[ $commands[kubectl] ]] && source <(kubectl completion zsh)
EOF
    echo "Added kubectl aliases and completion"
fi

# Fix ownership
chown "$ACTUAL_USER:$ACTUAL_USER" "$ZSHRC"

# Change default shell to zsh
CURRENT_SHELL=$(getent passwd "$ACTUAL_USER" | cut -d: -f7)
ZSH_PATH=$(which zsh)

if [ "$CURRENT_SHELL" != "$ZSH_PATH" ]; then
    echo ""
    echo "Changing default shell to zsh..."
    sudo chsh -s "$ZSH_PATH" "$ACTUAL_USER"
    echo "Shell changed to zsh"
else
    echo "Shell is already zsh"
fi

echo ""
echo "============================================"
echo "  Shell Setup Complete!"
echo "============================================"
echo ""
echo "Installed:"
echo "  - ZSH with Oh My Zsh"
echo "  - Plugins: git, kubectl, zsh-autosuggestions, zsh-syntax-highlighting"
echo ""
echo "Aliases added:"
echo "  k       = kubectl"
echo "  kgp     = kubectl get pods"
echo "  kgs     = kubectl get svc"
echo "  kgn     = kubectl get nodes"
echo "  kga     = kubectl get all"
echo "  kaf     = kubectl apply -f"
echo "  klog    = kubectl logs"
echo "  kexec   = kubectl exec -it"
echo ""
echo "Start a new shell or run: exec zsh"
echo ""
