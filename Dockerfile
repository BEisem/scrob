# ── Stage 1: Build frontend ───────────────────────────────────────────────────
FROM --platform=$BUILDPLATFORM node:22-alpine AS frontend-builder
WORKDIR /app/frontend

COPY frontend/package*.json ./
RUN npm ci

COPY frontend/ .
RUN npm run build

# ── Stage 2: Runtime (Python + Node + supervisord) ────────────────────────────
FROM python:3.12-slim

ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}
ENV TZ=UTC

# Install gosu, curl (for the healthcheck) and tzdata
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    curl \
    gosu \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 is copied from the official image instead of installed from
# NodeSource: only the `node` binary is needed at runtime, and the NodeSource
# package brings npm (with its own bundled dependencies) and a whole system
# Python (3.13) along with it.
COPY --from=node:22-slim /usr/local/bin/node /usr/local/bin/node

# supervisor comes from PyPI rather than apt, which would also drag in that
# system Python. pip is dropped afterwards since nothing installs packages at
# runtime, and it vendors libraries of its own.
RUN pip install --no-cache-dir "supervisor>=4.3" \
    && pip uninstall -y pip

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# ── Backend ───────────────────────────────────────────────────────────────────
WORKDIR /app/backend

COPY backend/pyproject.toml backend/uv.lock ./
RUN uv sync --frozen --no-dev --no-cache

COPY backend/ .

# The entrypoint chowns this; it must exist even when no volume is mounted over it
RUN mkdir -p /app/backend/data

# ── Frontend ──────────────────────────────────────────────────────────────────
WORKDIR /app/frontend

COPY --from=frontend-builder /app/frontend/dist ./dist
COPY --from=frontend-builder /app/frontend/node_modules ./node_modules
COPY --from=frontend-builder /app/frontend/package.json ./

# ── Entrypoint & supervisor config ────────────────────────────────────────────
COPY entrypoint.sh /entrypoint.sh
COPY supervisord.conf /etc/supervisor/supervisord.conf
RUN chmod +x /entrypoint.sh

EXPOSE 7330

# Requires Docker Engine 25+ for --start-interval
HEALTHCHECK --interval=2m --timeout=2s --start-period=20s --start-interval=5s --retries=3 \
  CMD curl -fsS http://127.0.0.1:${BACKEND_PORT:-7331}/health || exit 1

ENTRYPOINT ["/entrypoint.sh"]
