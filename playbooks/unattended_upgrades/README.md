# Unattended Upgrades

Configures automatic security updates with reboot scheduling.

**Prerequisites:** Run `email/email-setup.yml` first to configure email sending.

**What it does:**
- Installs base packages (`python3`, `python3-pip`, `python3-apt`, `git`, `vim`, `htop`)
- Installs and configures `unattended-upgrades` for automatic security updates
- Sets up email notifications for upgrade events (via previously configured email transport)
- Schedules automatic reboots at 03:00 AM when required

### Run for all hosts

```bash
ansible-playbook unattended_upgrades/unattended-upgrades.yml
```

### Run locally for localhost

```bash
ansible-playbook unattended_upgrades/unattended-upgrades.yml -e target=local
```

### Target a specific group

```bash
ansible-playbook unattended_upgrades/unattended-upgrades.yml -e target=boxes
```

### Target a specific host

```bash
ansible-playbook unattended_upgrades/unattended-upgrades.yml --limit box1
```
