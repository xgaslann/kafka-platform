# Installation Guide

> MacOS setup. Other OS may vary.

## About

This guide covers the local development environment setup. You'll need these tools to provision infrastructure and deploy the Kafka cluster. The setup is tested on MacOS with Apple Silicon (M2).

## Required Tools

- Homebrew
- Terraform
- Ansible
- AWS CLI
- Docker
- Go
- jq / yq
- pyenv

## Step 1: Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

## Step 2: Core Tools

```bash
brew install terraform ansible awscli docker go jq yq tree pyenv
```

## Step 3: Python

> cp-ansible 8.1 requires Python 3.10-3.12

Add to ~/.zshrc:
```bash
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
```

```bash
source ~/.zshrc
pyenv install 3.12.7
```

## Step 4: AWS CLI

```bash
aws configure
aws sts get-caller-identity
```

## Step 5: SSH Key

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/kafka-platform-key -N ""
```

## Step 6: Project Setup

```bash
git clone <repo-url>
cd kafka-platform/2-configuration

pyenv local 3.12.7
python -m venv .venv
source .venv/bin/activate
pip install ansible==10.6.0
ansible-galaxy collection install confluent.platform:8.1.0
```

Verify:
```bash
which ansible  # should be .venv/bin/ansible
```

## Ready

---

**Next:** [Infrastructure](./docs/01-infrastructure.md)