#!/bin/sh
set -e

PUID=${PUID:-1000}
PGID=${PGID:-1000}
BACKEND_PORT=${BACKEND_PORT:-7331}
export BACKEND_PORT

# Timezone
if [ -n "$TZ" ]; then
    ln -snf /usr/share/zoneinfo/"$TZ" /etc/localtime
    echo "$TZ" > /etc/timezone
fi

# Fix ownership so the scrob user can write to the data directory
chown -R "$PUID:$PGID" /app/backend/data

# Allow the unprivileged user to write to Docker's stdout/stderr
chmod o+w /dev/stdout /dev/stderr

echo "Running database migrations..."
cd /app/backend
su-exec "$PUID:$PGID" .venv/bin/python -m alembic upgrade head

echo "Starting Scrob (frontend :7330, backend 127.0.0.1:${BACKEND_PORT})..."
exec su-exec "$PUID:$PGID" /usr/local/bin/supervisord -n -c /etc/supervisor/supervisord.conf
