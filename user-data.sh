#!/bin/bash
set -e

###########################################
# Update OS
###########################################
apt-get update -y

###########################################
# Install Python
###########################################
apt-get install -y python3

###########################################
# Create application directory
###########################################
mkdir -p /opt/bashar-demo

###########################################
# Create Python Application
###########################################
cat << 'EOF' > /opt/bashar-demo/server.py
#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import socket
import datetime
import uuid

HOSTNAME = socket.gethostname()
REQUEST_COUNTER = 0

class DemoHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        global REQUEST_COUNTER
        REQUEST_COUNTER += 1
        current_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        request_id = str(uuid.uuid4())

        body = f"""
==========================================================
 AWS Load Balancer Demo Application
==========================================================
Hostname       : {HOSTNAME}
Port           : 8002
Current Time   : {current_time}
Request Number : {REQUEST_COUNTER}
Request ID     : {request_id}
Client IP      : {self.client_address[0]}
Requested Path : {self.path}
Message        : Hello from EC2!
==========================================================
Refresh the page and notice:
Time changes
Request Number increases
Request ID changes
Hostname changes if another EC2 answers
==========================================================
"""
        body = body.strip() + "\n"
        body_bytes = body.encode("utf-8")

        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body_bytes)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body_bytes)
        self.wfile.flush()

    def log_message(self, format, *args):
        print(
            f"[{datetime.datetime.now()}] {self.client_address[0]} -> {format % args}",
            flush=True
        )

if __name__ == "__main__":
    print("Starting Bashar Demo HTTP Server on port 8002...", flush=True)
    server = ThreadingHTTPServer(("0.0.0.0", 8002), DemoHandler)
    server.serve_forever()
EOF

chmod +x /opt/bashar-demo/server.py

###########################################
# Create systemd Service
###########################################
cat << 'EOF' > /etc/systemd/system/bashar-srv.service
[Unit]
Description=Bashar Demo HTTP Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/bashar-demo
Environment=PYTHONUNBUFFERED=1
ExecStart=/usr/bin/python3 -u /opt/bashar-demo/server.py
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

###########################################
# Enable Service
###########################################
systemctl daemon-reload
systemctl enable bashar-srv.service
systemctl start bashar-srv.service

###########################################
# Wait a little
###########################################
sleep 2
systemctl status bashar-srv.service --no-pager
