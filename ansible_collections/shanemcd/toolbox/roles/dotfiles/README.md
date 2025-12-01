# Ansible Role: dotfiles

Manages chezmoi dotfiles installation and configuration.

## Description

This role automates the setup of chezmoi-managed dotfiles by:
- Fetching the age encryption key from 1Password
- Initializing chezmoi from a git repository
- Automatically initializing the external_secrets submodule
- Optionally applying the dotfiles configuration

## Requirements

- `chezmoi` must be installed on the target system
- `age` encryption tool must be installed
- Access to the dotfiles git repository
- 1Password CLI configured and authenticated (for fetching the age key)
- SSH key configured for git repository access

## Role Variables

Available variables are listed below, along with default values (see `defaults/main.yml`):

```yaml
# Git repository containing your dotfiles
dotfiles_repo: "git@github.com:shanemcd/dotfiles.git"

# Chezmoi source directory
dotfiles_source_dir: "{{ ansible_facts['env']['HOME'] }}/.local/share/chezmoi"

# Chezmoi configuration directory
dotfiles_chezmoi_config_dir: "{{ ansible_facts['env']['HOME'] }}/.config/chezmoi"

# Path to the age encryption key file
dotfiles_chezmoi_key_path: "{{ dotfiles_chezmoi_config_dir }}/key.txt"

# Name of the 1Password item containing the age key
dotfiles_onepassword_key_item: "Chezmoi Key"

# Whether to run 'chezmoi apply' after initialization
dotfiles_apply: true
```

## Dotfiles Repository Architecture

The dotfiles repository uses a refactored template approach:

### Configuration Template (`.chezmoi.toml.tmpl`)

The template now **selectively imports only secrets** from the encrypted file:

```go
{{- if and (stat $secretsEncrypted) (stat $ageKey) }}
{{- $secretsContent := output "age" "-d" "-i" $ageKey $secretsEncrypted | trim -}}
{{- $secretsData := $secretsContent | fromToml }}
{{ $secretsData.data.secrets | toToml | trim | printf "[data.secrets]\n%s" }}
{{- end }}
```

### Separation of Concerns

- **Public repo** (`.chezmoi.toml.tmpl`): Contains non-secret configuration
  - User contact info (name, email)
  - Editor preference
  - Git settings
  - Age configuration

- **Private submodule** (`external_secrets/chezmoi-secrets.toml.age`): Contains only secrets
  - API keys
  - Project IDs
  - Other sensitive values

### Benefits

- Better separation between secrets and non-secret configuration
- Public repo is more self-documenting
- Secrets file is minimal and focused
- Template logic extracts only what's needed from encrypted file

## Dependencies

- `community.general` collection (for `onepassword_doc` lookup)

## Example Playbook

```yaml
- hosts: localhost
  roles:
    - role: shanemcd.toolbox.dotfiles
      vars:
        dotfiles_apply: true
```

## How It Works

1. **Key Setup**: Fetches age encryption key from 1Password and saves to `~/.config/chezmoi/key.txt`
2. **Initialization**: Runs `chezmoi init --apply` with your dotfiles repository
3. **Submodule Init**: Chezmoi automatically initializes the `external_secrets` submodule
4. **Template Processing**: `.chezmoi.toml.tmpl` decrypts and extracts only the secrets section
5. **Application**: Optionally applies dotfiles to the system

## Post-Setup

After running this role, you can manage your dotfiles with:

```bash
# Edit a managed file
chezmoi edit ~/.zshrc

# Preview changes
chezmoi diff

# Apply changes
chezmoi apply -v

# Navigate to source directory
chezmoi cd
```

## License

MIT

## Author

Shane McDonald
