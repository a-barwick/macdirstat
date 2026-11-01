#!/bin/sh
# Serves the docs site locally. Stop with Ctrl-C. Usage: docs/serve.sh [port]
# The default port comes from the repo path, and the script takes the next free port if that one is busy.
cd "$(dirname "$0")/site" || exit 1
port=${1:-$(( 3200 + $(pwd | cksum | cut -d' ' -f1) % 700 ))}
while ! python3 -c "import socket,sys; s=socket.socket(); s.settimeout(.2); sys.exit(s.connect_ex(('127.0.0.1',$port)) == 0)"; do port=$((port + 1)); done
url=http://127.0.0.1:$port
echo "Docs: $url"
if [ -t 1 ] && command -v open >/dev/null; then (sleep 1; open "$url") & fi
exec python3 -m http.server "$port" --bind 127.0.0.1
