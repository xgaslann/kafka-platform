### 1- Tool Installation
> Before running the kafka-platform project, ensure you have the following tools installed on your system:

> I will be using MacOS for this project. So this guide will be for MacOS users.

> Tools that will be used:

- Brew for installing the required tools
- Terraform for provisioning the infrastructure
- Ansible for deploying the applications and configuring them
- AWS CLI for interacting with AWS services
- Docker for running the applications
- Go for developing the applications
- jq for parsing JSON responses
- yq for parsing YAML responses
- tree for viewing directory structure

> #### Step 1: Install Homebrew
```bash 
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile; 
eval "$(/opt/homebrew/bin/brew shellenv)"
```

```bash
brew --version;
brew doctor
```