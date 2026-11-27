#!/usr/bin/env python3
"""Relays one TCP port across the sandbox boundary through a Unix socket.

The game client proves ownership by talking to the Steam client on 127.0.0.1:57343. The
sandbox has no network, so the host side of this relay listens on a Unix socket that is
bound into the sandbox and forwards to Steam, and the sandbox side listens on the same TCP
port on the sandbox's own loopback and forwards to that socket. Nothing else gets out.

    portproxy.py host <unix-socket> <tcp-port>      # outside the sandbox
    portproxy.py sandbox <unix-socket> <tcp-port>   # inside the sandbox
"""
import os
import socket
import sys
import threading


def pump(source, sink):
    try:
        while True:
            data = source.recv(65536)
            if not data:
                break
            sink.sendall(data)
    except OSError:
        pass
    finally:
        for sock in (source, sink):
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            sock.close()


def serve(listener, connect):
    while True:
        client, _ = listener.accept()
        try:
            upstream = connect()
        except OSError:
            client.close()
            continue
        threading.Thread(target=pump, args=(client, upstream), daemon=True).start()
        threading.Thread(target=pump, args=(upstream, client), daemon=True).start()


def main():
    side, path, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
    if side == "host":
        if os.path.exists(path):
            os.unlink(path)
        listener = socket.socket(socket.AF_UNIX)
        listener.bind(path)
        connect = lambda: socket.create_connection(("127.0.0.1", port))
    else:
        listener = socket.socket(socket.AF_INET)
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(("127.0.0.1", port))

        def connect():
            upstream = socket.socket(socket.AF_UNIX)
            upstream.connect(path)
            return upstream
    listener.listen(16)
    serve(listener, connect)


if __name__ == "__main__":
    main()
