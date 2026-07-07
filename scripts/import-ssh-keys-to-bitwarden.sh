#!/usr/bin/env bash
# import-ssh-keys-to-bitwarden.sh
# Imports SSH private keys from ~/.ssh into Bitwarden as Secure Notes.
#
# Creates a Bitwarden Secure Note for each private SSH key using the naming
# convention "SSH Key - <filename>", e.g. "SSH Key - id_ed25519".
# Public keys (.pub files) and non-key files (config, known_hosts) are skipped.
#
# Requires:
#   - Bitwarden CLI (bw) — install via: sudo snap install bw
#   - jq               — install via: sudo apt install jq
#   - BW_SESSION environment variable set
#
# Usage:
#   export BW_SESSION=$(bw unlock --raw)
#   ./import-ssh-keys-to-bitwarden.sh
#
# Dry-run (no changes):
#   ./import-ssh-keys-to-bitwarden.sh --dry-run

set -euo pipefail

SSH_DIR="${SSH_DIR:-$HOME/.ssh}"
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=true ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

# --- Preflight checks ---

if ! command -v bw &>/dev/null; then
    echo "Bitwarden CLI (bw) not found. Install it with: sudo snap install bw" >&2
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "jq not found. Install it with: sudo apt install jq" >&2
    exit 1
fi

if [ -z "${BW_SESSION:-}" ]; then
    echo "BW_SESSION is not set. Unlock your vault first:" >&2
    echo "  export BW_SESSION=\$(bw unlock --raw)" >&2
    exit 1
fi

vault_status=$(bw status 2>/dev/null | jq -r '.status')
if [ "$vault_status" != "unlocked" ]; then
    echo "Bitwarden vault is not unlocked. Run: export BW_SESSION=\$(bw unlock --raw)" >&2
    exit 1
fi

if [ ! -d "$SSH_DIR" ]; then
    echo "SSH directory not found: $SSH_DIR" >&2
    exit 1
fi

# --- Identify private keys ---

skip_names=("config" "known_hosts" "known_hosts.old" "authorized_keys" "authorized_keys2")

private_keys=()
while IFS= read -r -d '' file; do
    filename=$(basename "$file")
    ext="${filename##*.}"
    [[ "$ext" == "pub" ]] && continue

    skip=false
    for skip_name in "${skip_names[@]}"; do
        [[ "$filename" == "$skip_name" ]] && { skip=true; break; }
    done
    [[ "$skip" == false ]] && private_keys+=("$file")
done < <(find "$SSH_DIR" -maxdepth 1 -type f -print0)

if [ ${#private_keys[@]} -eq 0 ]; then
    echo "No private keys found in $SSH_DIR"
    exit 0
fi

echo "Found ${#private_keys[@]} private key(s) in $SSH_DIR"
echo ""

# --- Get existing Bitwarden items to avoid duplicates ---

echo "Fetching existing Bitwarden items..."
existing_names=$(bw list items 2>/dev/null | jq -r '.[].name' | sort -u)

# --- Import each key ---

imported=0
skipped=0
failed=0

for key_file in "${private_keys[@]}"; do
    key_name=$(basename "$key_file")
    item_name="SSH Key - $key_name"

    printf "  %s" "$key_name"

    if echo "$existing_names" | grep -Fxq "$item_name"; then
        echo " — already in Bitwarden, skipping"
        ((skipped++))
        continue
    fi

    if [ "$DRY_RUN" = true ]; then
        echo " — would import"
        ((imported++))
        continue
    fi

    item_json=$(jq -n \
        --rawfile notes "$key_file" \
        --arg name "$item_name" \
        '{
            organizationId: null,
            collectionIds: [],
            folderId: null,
            type: 2,
            name: $name,
            notes: $notes,
            favorite: false,
            secureNote: { type: 0 },
            reprompt: 0
        }')

    encoded=$(echo -n "$item_json" | base64 -w0)

    result=$(echo "$encoded" | bw create item 2>&1)
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo " — imported"
        ((imported++))
    else
        echo " — FAILED: $result"
        ((failed++))
    fi
done

echo ""
echo "Done: $imported imported, $skipped already existed, $failed failed"

if [ "$imported" -gt 0 ]; then
    echo ""
    echo "Syncing vault..."
    bw sync 2>/dev/null || true
    echo "Vault synced."
fi
