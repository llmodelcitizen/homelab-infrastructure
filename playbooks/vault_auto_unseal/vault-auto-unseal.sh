#!/bin/bash
# Unseal Vault at boot using age-encrypted unseal key.
# Deployed to /usr/local/bin/vault-auto-unseal by Ansible.

set -euo pipefail

VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_ADDR

AGE_KEY="/root/.config/sops/age/keys.txt"
ENCRYPTED_UNSEAL_KEY="/root/.vault-unseal-key.age"

alert_and_exit() {
    /usr/local/bin/send-mail \
        "ALERT: Vault auto-unseal failed on $(hostname)" \
        "$1"
    exit 1
}

# Wait for Vault API to become reachable (exit code 2 = sealed but reachable)
echo "Waiting for Vault API..."
for i in $(seq 1 30); do
    rc=0
    vault status -address="$VAULT_ADDR" &>/dev/null || rc=$?
    # 0 = unsealed; 2 = sealed but reachable; both mean API is up
    if [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ]; then
        break
    fi
    if [ "$i" -eq 30 ]; then
        alert_and_exit "Vault API at $VAULT_ADDR not reachable after 30 seconds."
    fi
    sleep 1
done

# Check if already unsealed
if vault status -address="$VAULT_ADDR" -format=json 2>/dev/null | jq -e '.sealed == false' &>/dev/null; then
    echo "Vault is already unsealed."
    exit 0
fi

echo "Vault is sealed. Attempting unseal..."

# Decrypt unseal key
if [ ! -f "$ENCRYPTED_UNSEAL_KEY" ]; then
    alert_and_exit "Encrypted unseal key not found at $ENCRYPTED_UNSEAL_KEY"
fi
if [ ! -f "$AGE_KEY" ]; then
    alert_and_exit "age identity not found at $AGE_KEY"
fi

unseal_key=$(age -d -i "$AGE_KEY" "$ENCRYPTED_UNSEAL_KEY") || \
    alert_and_exit "Failed to decrypt unseal key."

# Unseal
vault operator unseal -address="$VAULT_ADDR" "$unseal_key" &>/dev/null || \
    alert_and_exit "vault operator unseal command failed."

# Verify
if vault status -address="$VAULT_ADDR" -format=json 2>/dev/null | jq -e '.sealed == false' &>/dev/null; then
    echo "Vault successfully unsealed."
else
    alert_and_exit "Vault is still sealed after unseal attempt."
fi
