# Frigate NVR

Docker Compose configuration for [Frigate](https://frigate.video/) NVR with NVIDIA GPU acceleration (TensorRT).

### 1. Create directories

```bash
sudo mkdir -p /opt/frigate/config /mnt/ssd3/frigate
```

### 2. Start services

```bash
./frigatectl up -d
```

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 443 | TCP | HTTPS via Traefik (main web UI) |
| 8971 | TCP | Main Frigate UI (direct) |
| 1984 | TCP | go2RTC web UI |
| 8554 | TCP | RTSP feeds |
| 8555 | TCP/UDP | WebRTC |

**Note:** Port 5000 (web UI) is routed through Traefik for HTTPS access. Direct access is available on port 8971.

## Volumes

| Host Path | Container Path | Description |
|-----------|----------------|-------------|
| `/opt/frigate/config` | `/config` | Frigate configuration |
| `/mnt/ssd3/frigate` | `/media/frigate` | Media storage (recordings, clips) |

### Verify NVIDIA Hardware Acceleration

**Check GPU is detected by Frigate:**

```bash
docker logs frigate 2>&1 | grep -i nvidia
```

Expected output:
```
frigate.util.services          INFO    : Automatically detected nvidia hwaccel for video decoding
```

**Check NVENC is being used for transcoding:**

```bash
docker exec frigate curl -s http://127.0.0.1:1984/api/streams | grep -o 'h264_nvenc'
```

Expected output: `h264_nvenc` (appears for each stream using hardware encoding)

**Check GPU utilization while streaming:**

```bash
nvidia-smi
```

Look for `frigate` or `ffmpeg` processes using the GPU, and non-zero GPU utilization.

### Verify Coral TPU

**Check TPU is detected:**

```bash
docker logs frigate 2>&1 | grep -i tpu
```

Expected output:
```
frigate.detectors.plugins.edgetpu_tfl INFO    : Attempting to load TPU as usb
frigate.detectors.plugins.edgetpu_tfl INFO    : TPU found
```

**Check TPU is processing detections:**

```bash
docker exec frigate curl -s http://127.0.0.1:5000/api/stats | python3 -m json.tool | grep -A5 '"coral"'
```

Look for `inference_speed` values (in ms) - typically 5-15ms for Coral USB.

## References

- [Frigate Documentation](https://docs.frigate.video/)
- [NVIDIA CUDA Installation Guide](https://docs.nvidia.com/cuda/cuda-installation-guide-linux/)
- [NVIDIA Container Toolkit Install Guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
