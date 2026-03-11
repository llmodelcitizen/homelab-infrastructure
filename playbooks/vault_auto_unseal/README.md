# Vault Auto-Unseal
Automatically unseals Vault at boot before Docker starts.

The systemd service runs after `vault.service` and before `docker.service`, so all Docker services that query Vault via their ctl scripts will find it already unsealed.

**Behavior:**
- Waits up to 30 seconds for the Vault API to become reachable
- Skips unseal if Vault is already unsealed
- Sends an email alert via `/usr/local/bin/send-mail` on any failure

### Prerequisites

A running Vault instance must be installed and initialized on the server before any services can start. Vault installation is not managed by this repository.

1. Install Vault from the HashiCorp APT repository ([instructions](https://developer.hashicorp.com/vault/docs/install)):

   ```bash
   sudo apt update && sudo apt install vault
   ```

2. Configure Vault with local file storage. Write `/etc/vault.d/vault.hcl`. Vault must listen on `127.0.0.1`, not the Docker bridge IP (`172.17.0.1`), since Docker starts after Vault.

   ```hcl
   storage "file" {
     path = "/opt/vault/data"
   }

   listener "tcp" {
     address     = "127.0.0.1:8200"
     tls_disable = true
   }

   ui = false
   ```

3. Start Vault:

   ```bash
   sudo systemctl enable --now vault
   ```

4. Initialize with a single unseal key:

   ```bash
   export VAULT_ADDR="http://127.0.0.1:8200"
   vault operator init -key-shares=1 -key-threshold=1
   ```

   Save the **unseal key** and **root token** from the output.

5. Unseal and enable the KV secrets engine:

   ```bash
   vault operator unseal    # paste the unseal key
   vault login              # paste the root token
   vault secrets enable -path=secret kv-v2
   ```

6. Normally a vault installation would use an external facing provider like KMS. To remove cloud dependency, this installation instead stores an encrypted copy locally accessible only by root. Install age and generate an age identity:

   ```bash
   sudo apt install age
   sudo mkdir -p /root/.config/sops/age
   sudo age-keygen -o /root/.config/sops/age/keys.txt
   sudo chmod 600 /root/.config/sops/age/keys.txt
   ```

7. Encrypt the unseal key and root token with age for use by the `vault_auto_unseal` playbook, the `vault_mirror` playbook, and the service ctl scripts:

   ```bash
   echo -n 'YOUR_UNSEAL_KEY' | sudo age -e -r "$(sudo age-keygen -y /root/.config/sops/age/keys.txt)" -o /root/.vault-unseal-key.age
   echo -n 'YOUR_ROOT_TOKEN' | sudo age -e -r "$(sudo age-keygen -y /root/.config/sops/age/keys.txt)" -o /root/.vault-credentials.age

   sudo chmod 600 /root/.vault-unseal-key.age
   sudo chmod 600 /root/.vault-credentials.age
   ```

### Playbook authentication

Playbooks that need Vault access (e.g. [`vault_mirror`](../vault_mirror/)) authenticate automatically using the same age-encrypted root token. A `pre_tasks` block decrypts the token via `become: true` and passes it to subsequent vault commands through an environment variable. The token only exists in Ansible's in-memory variables for the duration of the run and is never written to disk. This means no manual `vault-login` step is required before running playbooks; just pass `--become` to the `ansible-playbook` command.

### Interactive CLI authentication

To authenticate with Vault interactively (once unsealed), decrypt the root token using the host's age key. The following helper can be put in your `~/.bashrc` for convenient vault CLI usage. This puts the vault token into your home directory. You do not need to do this.

```bash
export VAULT_ADDR="http://127.0.0.1:8200"
vault-login() {
    sudo VAULT_ADDR=http://127.0.0.1:8200 bash -c 'age -d -i /root/.config/sops/age/keys.txt /root/.vault-credentials.age | vault login -'
    sudo cp /root/.vault-token ~/.vault-token
    sudo chown "$USER":"$USER" ~/.vault-token
}
```

## Run

```bash
ansible-playbook vault_auto_unseal/vault-auto-unseal.yml
```

Local:

```bash
ansible-playbook vault_auto_unseal/vault-auto-unseal.yml -c local
```

## Verify

```bash
# Check service is enabled
systemctl is-enabled vault-auto-unseal.service

# Run manually
sudo /usr/local/bin/vault-auto-unseal

# Check logs
journalctl -u vault-auto-unseal.service

```

## Full reboot test

```bash
sudo reboot
# After reboot:
vault status                             # should show sealed=false
docker ps                                # services should be running
journalctl -u vault-auto-unseal.service  # should show "successfully unsealed"
```
