# pg_gpu Docker image

A container for [**pg_gpu**](https://github.com/kr-colab/pg_gpu) — GPU-accelerated
population genetics statistics built on CuPy — bundled with the scientific-Python
stack you typically need around it.

**Image:** [`connormfrench/pg_gpu`](https://hub.docker.com/r/connormfrench/pg_gpu)

```bash
docker pull connormfrench/pg_gpu:latest
```

## What's inside

| Layer | Packages |
|-------|----------|
| Base | `nvidia/cuda:12.6.2-runtime-ubuntu22.04`, Python 3.12 |
| pg_gpu | `pg_gpu` (from source), `cupy-cuda12x`, `kvikio-cu12`, `nvidia-nvcomp-cu12` |
| popgen / IO | `scikit-allel`, `msprime`, `bio2zarr[vcf]`, `zarr`, `h5py`, `htslib` (bgzip/tabix) |
| scientific stack | `numpy` (≥2.0), `scipy`, `pandas`, **`matplotlib`**, **`seaborn`** |

Everything is installed on the default `PATH` (`/opt/conda/bin`) — there is **no**
`conda activate` or `pixi shell` step, so tools resolve correctly in the
non-interactive shells that Nextflow (and most schedulers) use.

## Requirements

The image is **CUDA 12 / linux-amd64** and needs an **NVIDIA GPU** at runtime.
The host must have a recent NVIDIA driver and the
[NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
(for Docker) or a GPU-enabled Apptainer/Singularity (`--nv`).

## Quick start

```bash
# Confirm the GPU is visible inside the container
docker run --rm --gpus all connormfrench/pg_gpu:latest nvidia-smi

# Confirm cupy + pg_gpu import against the GPU
docker run --rm --gpus all connormfrench/pg_gpu:latest \
  python -c "import cupy, pg_gpu; print(cupy.cuda.runtime.getDeviceCount(), 'GPU(s)')"

# Run your own script, mounting the current directory
docker run --rm --gpus all -v "$PWD:/work" connormfrench/pg_gpu:latest \
  python my_analysis.py
```

---

## Using the image in Nextflow pipelines

Nextflow runs each process inside the container you point it at and executes the
process script in a **non-login, non-interactive shell**. Because this image puts
every tool on the default `PATH`, your process scripts can call `python`,
`bgzip`, `tabix`, etc. directly — no activation needed.

### 1. Point a process at the image

In a process definition:

```groovy
process popgen_stats {
    container 'connormfrench/pg_gpu:latest'
    accelerator 1, type: 'nvidia.com/gpu'   // request one GPU (Kubernetes/SLURM-aware)

    input:
    path zarr_store

    output:
    path 'stats.csv'

    script:
    """
    python - <<'PY'
    import pg_gpu, pandas as pd
    # ... compute statistics on the GPU ...
    PY
    """
}
```

Or set it globally in `nextflow.config`:

```groovy
process {
    container = 'connormfrench/pg_gpu:latest'
    withName: popgen_stats {
        accelerator = 1
    }
}
```

### 2a. Docker engine (`--gpus all`)

Docker does not expose GPUs to containers unless told to. Add the flag globally:

```groovy
// nextflow.config
docker {
    enabled    = true
    runOptions = '--gpus all'   // expose every GPU to each container
}
```

Run it:

```bash
nextflow run main.nf -with-docker connormfrench/pg_gpu:latest
```

To expose specific GPUs only, use `--gpus '"device=0,1"'` in `runOptions`.

### 2b. Apptainer / Singularity (`--nv`) — typical on HPC

Most Nextflow GPU work runs on HPC clusters where Docker is unavailable;
Apptainer/Singularity is the norm. They pull the same Docker Hub image and
convert it to a SIF automatically. The key is the `--nv` flag, which binds the
host NVIDIA driver/libraries into the container:

```groovy
// nextflow.config
apptainer {
    enabled    = true
    autoMounts = true
    runOptions = '--nv'   // bind host CUDA driver into the container
}
process {
    container = 'docker://connormfrench/pg_gpu:latest'
}
```

> Using older Nextflow / Singularity? Replace the `apptainer { ... }` block with
> an identical `singularity { ... }` block — the options are the same.

Run it:

```bash
nextflow run main.nf -with-apptainer docker://connormfrench/pg_gpu:latest
# or, older:  nextflow run main.nf -with-singularity docker://connormfrench/pg_gpu:latest
```

You can also pre-build the SIF once and reuse it:

```bash
apptainer pull pg_gpu.sif docker://connormfrench/pg_gpu:latest
# then reference  file:///abs/path/pg_gpu.sif  as the container
```

### 3. Requesting GPUs from the scheduler

The `accelerator` directive tells executors like SLURM, AWS Batch, Google Batch,
and Kubernetes to schedule the task onto a GPU node. Pair it with executor-specific
options where needed, e.g. for SLURM:

```groovy
process {
    withName: popgen_stats {
        accelerator   = 1
        clusterOptions = '--gres=gpu:1'   // SLURM GPU request
    }
}
```

On a local/standalone executor, the `accelerator` directive is advisory — GPU
access there is governed entirely by the Docker `--gpus` / Apptainer `--nv`
options above.

---

## How the image is built

The image is published from this repo by GitHub Actions
(`.github/workflows/docker-publish.yml`), which builds natively on an amd64
runner and pushes to Docker Hub on every push to `main` and on `v*` tags.

To enable publishing, add two repository secrets:

- `DOCKERHUB_USERNAME` → `connormfrench`
- `DOCKERHUB_TOKEN` → a Docker Hub access token

Tagging a release pushes a versioned tag:

```bash
git tag v0.1.0 && git push origin v0.1.0   # -> connormfrench/pg_gpu:0.1.0 + :latest
```

### Building locally

```bash
# On an amd64 host:
docker build -t connormfrench/pg_gpu:latest .

# On Apple Silicon / other arm64 (emulated; all deps are prebuilt wheels):
docker buildx build --platform linux/amd64 -t connormfrench/pg_gpu:latest --push .
```

> **Note:** the build runs a CPU-only import smoke test. The GPU code paths
> (`cupy`, `pg_gpu`) require an NVIDIA GPU and are only exercised at runtime on a
> GPU host — they are *not* validated during the build.
