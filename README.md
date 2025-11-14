# aws-shell-scripts

Various AWS CLI based helper scripts for managing AWS resources and authentication.

## Installation

Use the provided `setup.sh` script to create symlinks for all scripts in a directory of your choice (e.g., `~/bin` or `/usr/local/bin`):

```bash
# Interactive mode (default) - will prompt for conflicts
./setup.sh --target ~/bin

# Silent mode - only shows info and warnings, skips prompts
./setup.sh --target /usr/local/bin --silent

# Dry-run mode - see what would be done without making changes
./setup.sh --target ~/bin --dry-run

# Combine options
./setup.sh --target ~/bin --silent --dry-run
```

The setup script will:
- Check for required dependencies and provide installation instructions if missing
- Create symlinks for all scripts in the target directory
- Set executable permissions on the symlinks
- Handle existing files/symlinks intelligently (warns if conflicts exist)
- Support multiple operating systems (macOS, Debian/Ubuntu, Alpine, RPM-based)

## Scripts

### `aws-cw`
Interactive CloudWatch log viewer that allows you to browse and view logs from CloudWatch log groups and streams. Features include:
- Interactive selection of log groups and streams using `fzf`
- Pagination support for large log lists
- Request ID filtering and preview
- Option to save logs to a file
- Supports profile and region selection

**Usage:** `aws-cw [log-group] [log-stream] [-o|--outfile file] [-p|--profile AWS Profile] [-r|--region AWS Region]`

**Examples:**
```bash
# Interactive mode (requires fzf)
aws-cw

# Interactive stream selection for a specific log group
aws-cw /aws/lambda/my-function

# View specific log stream
aws-cw /aws/lambda/my-function stream-1

# With profile and region
aws-cw /aws/lambda/my-function stream-1 --profile prod --region us-east-1

# Save logs to file
aws-cw /aws/lambda/my-function stream-1 --outfile logs.txt
```

### `aws-ecr-login`
Authenticates Docker with AWS Elastic Container Registry (ECR). Retrieves ECR credentials and logs Docker into the ECR registry endpoint, enabling you to pull and push container images.

**Usage:** `aws-ecr-login [-p|--profile AWS Profile] [-r|--region AWS Region]`

**Examples:**
```bash
# Interactive mode (requires fzf)
aws-ecr-login

# With specific profile and region
aws-ecr-login --profile prod --region us-east-1

# With profile only (uses default region)
aws-ecr-login --profile dev
```

### `aws-eks-update`
Updates your Kubernetes configuration to connect to an AWS EKS cluster. Interactively selects an EKS cluster (if multiple exist) and updates `kubeconfig` with the cluster connection details. Includes an alias based on profile and cluster name.

**Usage:** `aws-eks-update [-p|--profile AWS Profile] [-r|--region AWS Region] [-s|--session AWS SSO Session]`

**Examples:**
```bash
# Interactive mode (requires fzf)
aws-eks-update

# With specific profile and region
aws-eks-update --profile prod --region us-east-1

# With SSO session
aws-eks-update --profile dev --region eu-west-1 --session my-sso-session
```

### `aws-functions.sh`
Shared library containing common functions used by other scripts. This file should be sourced by other scripts and not executed directly. Includes:
- Logging functions (`log_info`, `log_ok`, `log_warn`, `log_error`, `log_fatal`)
- Interactive selection functions for profiles, regions, and SSO sessions
- AWS authentication and token validation functions
- EKS cluster selection helpers
- FZF integration utilities

### `aws-imagebuilder`
Manages AWS Image Builder pipelines. Supports three actions:
- **start**: Initiates a new image build pipeline execution
- **status**: Displays the status and history of image builds for a pipeline
- **stop**: Cancels a running image build

Features interactive selection of pipelines, actions, and running builds using `fzf`.

**Usage:** `aws-imagebuilder [pipeline-name] [action] [-p|--profile AWS Profile] [-r|--region AWS Region]`

**Examples:**
```bash
# Interactive mode (requires fzf)
aws-imagebuilder

# Start a pipeline build
aws-imagebuilder my-pipeline start

# Check pipeline status
aws-imagebuilder my-pipeline status --profile prod

# Stop a running build
aws-imagebuilder my-pipeline stop --profile prod --region us-east-1

# Using environment variables
AWS_PROFILE=prod aws-imagebuilder my-pipeline start
```

### `aws-profiles`
Lists all AWS profiles defined in `~/.aws/config`. Extracts profile names from the configuration file. Can be overridden with `AWS_CONFIG_FILE` environment variable.

**Usage:** `aws-profiles [-h|--help] [-d|--debug]`

**Examples:**
```bash
# List all profiles
aws-profiles

# Filter profiles
aws-profiles | grep prod

# Use different config file
AWS_CONFIG_FILE=~/.aws/config2 aws-profiles
```

### `aws-sessions`
Lists all AWS SSO sessions defined in `~/.aws/config`. Extracts SSO session names from the configuration file. Can be overridden with `AWS_CONFIG_FILE` environment variable.

**Usage:** `aws-sessions`

**Examples:**
```bash
# List all SSO sessions
aws-sessions

# Use different config file
AWS_CONFIG_FILE=~/.aws/config2 aws-sessions
```

### `aws-sso-login`
Performs AWS SSO login and validates the session. Checks if the current SSO token is valid, and if not, initiates an interactive SSO login process. Exits gracefully if run in a non-interactive environment (e.g., cron jobs).

**Usage:** `aws-sso-login [-p|--profile AWS Profile] [-r|--region AWS Region]`

**Examples:**
```bash
# Interactive mode (requires fzf)
aws-sso-login

# With specific profile and region
aws-sso-login --profile prod --region us-east-1

# With profile only
aws-sso-login --profile dev
```

## Dependencies

- AWS CLI (`aws`)
- `fzf` (optional, for interactive selection)
- `jq` (for JSON parsing in some scripts)
- `perl` (for parsing AWS config files)

The `setup.sh` script will check for these dependencies and provide installation instructions for:
- macOS (Homebrew)
- Debian/Ubuntu (apt-get)
- Alpine (apk)
- RPM-based distributions (Fedora, RHEL, CentOS, Rocky, AlmaLinux - dnf)

## Common Features

Most scripts support:
- Interactive profile and region selection via `fzf` when available
- Command-line arguments for profile (`-p|--profile`) and region (`-r|--region`)
- Colored output with icons for better readability
- Timestamped log messages
- Help messages via `-h|--help`
