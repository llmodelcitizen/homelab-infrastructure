# NVIDIA GPU

Installs NVIDIA drivers with DKMS and configures the Docker NVIDIA runtime. DKMS automatically rebuilds the kernel module on kernel upgrades so the GPU stays available after unattended updates.

**What it does:**
- Installs `nvidia-driver`, `nvidia-kernel-dkms`, and `linux-headers-amd64`
- Ensures the NVIDIA kernel module is loaded
- Adds the NVIDIA Container Toolkit repo and installs `nvidia-container-toolkit`
- Configures the Docker NVIDIA runtime and restarts Docker

## Run

```bash
ansible-playbook nvidia/nvidia.yml
```

Local:

```bash
ansible-playbook nvidia/nvidia.yml -c local
```

## Verify

```bash
# Check driver on host
nvidia-smi

# Check Docker runtime
docker info | grep -i nvidia

# Test GPU in a container
docker run --rm --runtime=nvidia --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi
```

## Troubleshooting

**Verify the installation:**

```bash
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
```

**`nvidia-smi` fails after kernel upgrade:**
```bash
# Check if DKMS built the module for the running kernel
dkms status

# Rebuild manually if needed
sudo dkms autoinstall
sudo modprobe nvidia
```

**Docker can't see the GPU:**
```bash
# Re-run the runtime config
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

### Enroll MOK key (Secure Boot only)

If Secure Boot is enabled, you must enroll the MOK key before the modules can load.

```bash
sudo mokutil --import /var/lib/dkms/mok.pub
```

Enter a one-time password when prompted (e.g., `12345678`). You'll need this password during the next boot.

#### Step 5: Reboot and complete MOK enrollment

```bash
sudo reboot
```

If you enrolled a MOK key, a blue **MOK Management** screen appears during boot:

1. Select **Enroll MOK**
2. Select **Continue**
3. Select **Yes**
4. Enter the password you created in Step 4
5. Select **Reboot**
