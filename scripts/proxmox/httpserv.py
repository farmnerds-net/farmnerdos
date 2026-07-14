#!/usr/bin/env python3
"""Tiny HTTP server for the automated FarmNerdOS build pipeline.

GET  — serves files from the staging dir (kernel, initrd, repo tarball, payload)
PUT  — accepts uploads into <dir>/incoming/ (the finished ISO, build log)

Usage: httpserv.py <port> <directory>
"""
import http.server
import os
import sys


class Handler(http.server.SimpleHTTPRequestHandler):
    def do_PUT(self):
        name = os.path.basename(self.path)  # no traversal
        if not name:
            self.send_error(400, "missing filename")
            return
        length = int(self.headers.get("Content-Length", 0))
        dest_dir = os.path.join(os.getcwd(), "incoming")
        os.makedirs(dest_dir, exist_ok=True)
        dest = os.path.join(dest_dir, name)
        remaining = length
        with open(dest + ".part", "wb") as f:
            while remaining > 0:
                chunk = self.rfile.read(min(1 << 20, remaining))
                if not chunk:
                    break
                f.write(chunk)
                remaining -= len(chunk)
        if remaining:
            os.unlink(dest + ".part")
            self.send_error(400, "truncated upload")
            return
        os.replace(dest + ".part", dest)  # atomic: orchestrator never sees partials
        self.send_response(201)
        self.end_headers()

    def log_message(self, fmt, *args):  # quiet
        pass


if __name__ == "__main__":
    port, directory = int(sys.argv[1]), sys.argv[2]
    os.chdir(directory)
    http.server.ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
