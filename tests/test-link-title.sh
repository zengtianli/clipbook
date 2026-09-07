#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source /Users/tianli/Dev/tools/dev/lib/tools/macapp/xcode_env.sh
xcode_env_use macosx
xcrun swiftc -parse-as-library Sources/Native/Settings.swift Sources/Native/LinkTitle.swift tests/LinkTitleTest.swift -o build/link-title-test
python3 - <<'PY'
import http.server,threading,time,subprocess
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Length','10485760')
        self.end_headers()
        try:
            body=b'<title>bounded response</title>'
            self.wfile.write(body+b'x'*(262144-len(body)));self.wfile.flush()
            time.sleep(3)
            self.wfile.write(b'x'*(10485760-262144))
        except (BrokenPipeError,ConnectionResetError): pass
    def log_message(self,*args): pass
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
try: subprocess.run(['build/link-title-test',f'http://127.0.0.1:{server.server_port}/'],check=True)
finally: server.shutdown()
PY
