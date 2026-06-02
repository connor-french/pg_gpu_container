# pg_gpu container
# -----------------
# GPU-accelerated population genetics (https://github.com/kr-colab/pg_gpu)
# plus the scientific-Python stack requested for downstream analysis:
# matplotlib, cupy, numpy, pandas, seaborn.
#
# Base is the CUDA 12 *runtime* image (not -devel): the cupy-cuda12x /
# kvikio-cu12 / nvcomp-cu12 wheels ship prebuilt and use bundled NVRTC for
# JIT, so nvcc is not needed. Everything is installed onto the base conda
# environment and placed on PATH directly (no `conda activate` / `pixi shell`),
# because Nextflow runs process scripts in a non-login, non-interactive shell.
FROM nvidia/cuda:12.6.2-runtime-ubuntu22.04

LABEL org.opencontainers.image.title="pg_gpu" \
      org.opencontainers.image.description="GPU-accelerated population genetics (pg_gpu) with the matplotlib/cupy/numpy/pandas/seaborn stack" \
      org.opencontainers.image.source="https://github.com/kr-colab/pg_gpu" \
      org.opencontainers.image.documentation="https://pg-gpu.readthedocs.io/"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    MAMBA_ROOT_PREFIX=/opt/conda \
    PATH=/opt/conda/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1

# System bootstrap deps:
#   ca-certificates/curl  - fetch micromamba
#   bzip2                 - extract the micromamba tarball
#   git                   - lets pip install pg_gpu from source
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl bzip2 git \
    && rm -rf /var/lib/apt/lists/*

# Install micromamba (a fast, static conda client) into /usr/local/bin.
RUN curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest \
      | tar -xvj -C /usr/local/bin --strip-components=1 bin/micromamba

# Conda (conda-forge + bioconda) layer: Python 3.12 and the prebuilt binary
# scientific / popgen stack. pg_gpu pins python >=3.12,<3.13. matplotlib and
# seaborn are explicit additions on top of pg_gpu's own dependency set.
# htslib provides bgzip/tabix used by bio2zarr's VCF round-trips.
RUN micromamba install -y -p /opt/conda -c conda-forge -c bioconda \
        python=3.12 \
        pip \
        "numpy>=2.0" \
        "scipy>=1.12" \
        "pandas>=2.0" \
        "scikit-allel>=1.3" \
        "msprime>=1.0" \
        "h5py>=3.0" \
        "tqdm>=4.0" \
        "zarr>=2.16" \
        "htslib>=1.19" \
        matplotlib \
        seaborn \
    && micromamba clean -ay

# GPU + remaining PyPI layer. cupy / kvikio / nvcomp all target CUDA 12; the
# kvikio-cu12 and nvidia-nvcomp-cu12 wheels live on NVIDIA's PyPI index. Keeping
# cupy on the same cuda12 wheel family as kvikio/nvcomp avoids ABI mismatches.
RUN pip install --no-cache-dir \
        --extra-index-url https://pypi.nvidia.com \
        "cupy-cuda12x>=13.0" \
        "kvikio-cu12>=25.0" \
        "nvidia-nvcomp-cu12>=4.0" \
        "bio2zarr[vcf]>=0.1"

# pg_gpu itself. Its pyproject declares no runtime dependencies (they live in
# the upstream pixi.toml, installed above), so --no-deps keeps pip from pulling
# an unintended dependency tree.
RUN pip install --no-cache-dir --no-deps \
        "git+https://github.com/kr-colab/pg_gpu.git"

# Build-time smoke test for the CPU-importable stack. cupy and pg_gpu are NOT
# imported here: they touch the CUDA driver at import time and there is no GPU
# during the build. They are exercised at runtime on a GPU host.
RUN python -c "import numpy, scipy, pandas, allel, msprime, h5py, zarr, matplotlib, seaborn, bio2zarr; print('CPU stack import OK')"

WORKDIR /work
CMD ["/bin/bash"]
