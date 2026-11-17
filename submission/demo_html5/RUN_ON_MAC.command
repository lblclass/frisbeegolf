#!/bin/zsh
set -e

cd -- "$(dirname "$0")"

PORT="${PORT:-8060}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 is required to run this HTML5 export locally."
  echo "Install Python 3, or upload the whole folder to a web host and open Disc_Golf.html from there."
  osascript -e 'display alert "Python 3 required" message "Install Python 3, or upload the whole folder to a web host and open Disc_Golf.html from there."' >/dev/null 2>&1 || true
  read "?Press Enter to close this window..."
  exit 1
fi

python3 - "$PORT" <<'PY'
import http.server
import sys
import webbrowser

port = int(sys.argv[1])


class GodotHandler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "text/javascript",
    }

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


url = f"http://127.0.0.1:{port}/Disc_Golf.html"

try:
    with http.server.ThreadingHTTPServer(("127.0.0.1", port), GodotHandler) as server:
        print(f"Local server: {url}")
        print("Keep this Terminal window open while playing.")
        print("Press Control-C here to stop the game server.")
        webbrowser.open(url)
        server.serve_forever()
except KeyboardInterrupt:
    print("\nServer stopped.")
except OSError as exc:
    print(f"Could not start local server on port {port}: {exc}", file=sys.stderr)
    print("Close other local servers, or run this from Terminal with: PORT=8061 ./RUN_ON_MAC.command", file=sys.stderr)
    raise SystemExit(1)
PY
