#!/usr/bin/env python3
"""Relays one TCP port across the sandbox boundary through a Unix socket.

The game client proves ownership by talking to the Steam client on 127.0.0.1:57343. The
sandbox has no network, so the host side of this relay listens on a Unix socket that is
bound into the sandbox and forwards to Steam, and the sandbox side listens on the same TCP
port on the sandbox's own loopback and forwards to that socket. Nothing else gets out.

A streamed session goes the other way: the stream server inside listens on a Unix socket in
the same bound directory, and `expose` listens on one port outside, on each of a
comma-separated list of addresses, and forwards each connection to it. WebRTC media takes the same port over UDP (`udp-expose` outside,
`udp-sandbox` inside, through two Unix datagram sockets in that directory). Nothing else
gets in.

    portproxy.py --session <pid> host <unix-socket> <tcp-port>       # outside the sandbox
    portproxy.py sandbox <unix-socket> <tcp-port>    # inside the sandbox
    portproxy.py --session <pid> expose <unix-socket> <address,...> <tcp-port>   # outside, inbound
    portproxy.py --session <pid> udp-expose <folder> <address> <port>        # outside, inbound
    portproxy.py udp-sandbox <folder> <port>         # inside, to 127.0.0.1:<port>
    portproxy.py check                               # exits 0 when its TCP sockets get TCP_NODELAY

Every TCP socket the relay uses has TCP_NODELAY: the game's Steam traffic is small
request/answer writes, and Nagle's algorithm held them back long enough to cut the game's
frame rate to a fraction.
"""
import os
import select
import selectors
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


def nodelay(sock):
    if sock.family in (socket.AF_INET, socket.AF_INET6):
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    return sock


def has_nodelay(sock):
    return sock.getsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY) != 0


def serve(listener, connect):
    while True:
        client = nodelay(listener.accept()[0])
        try:
            upstream = connect()
        except OSError:
            client.close()
            continue
        threading.Thread(target=pump, args=(client, upstream), daemon=True).start()
        threading.Thread(target=pump, args=(upstream, client), daemon=True).start()


def watch_session(pid):
    """A host relay must close its listeners and connections when its sandbox exits."""
    try:
        owner = os.pidfd_open(pid)
    except ProcessLookupError:
        sys.exit(0)

    def watch():
        select.select([owner], [], [])
        os._exit(0)  # the relay can be blocked in accept or a connection attempt

    threading.Thread(target=watch, daemon=True).start()


def udp_relay(side, folder, port, address="127.0.0.1"):
    """WebRTC media is UDP. Outside, `udp-expose` takes datagrams on one UDP address and
    passes each through a Unix datagram socket with its sender in front; inside,
    `udp-sandbox` sends it on from a UDP socket of that sender's own to 127.0.0.1:<port>,
    and passes the answers back the same way. The server inside sees each viewer as a
    loopback address, which ICE accepts as a peer-reflexive candidate."""
    os.chdir(folder)
    here, there = ("udp-host.sock", "udp-sandbox.sock") if side == "udp-expose" else ("udp-sandbox.sock", "udp-host.sock")
    if os.path.exists(here):
        os.unlink(here)
    unix = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    unix.bind(here)
    unix.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 << 20)
    chooser = selectors.DefaultSelector()
    chooser.register(unix, selectors.EVENT_READ)
    if side == "udp-expose":
        public = socket.socket(socket.AF_INET6 if ":" in address else socket.AF_INET, socket.SOCK_DGRAM)
        public.bind((address, port))
        public.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 << 20)
        chooser.register(public, selectors.EVENT_READ)
    peers, senders = {}, {}  # sandbox side: sender header -> its UDP socket, and back

    def forward(data):
        try:
            unix.sendto(data, there)
        except OSError:
            pass  # the other side is not up (yet); UDP may drop

    while True:
        for key, _ in chooser.select():
            sock = key.fileobj
            if sock is unix:
                data = unix.recv(65600)
                size = data[0]
                header, payload = data[1:1 + size], data[1 + size:]
                if side == "udp-expose":
                    host, _, peer_port = header.decode().rpartition(" ")
                    try:
                        public.sendto(payload, (host, int(peer_port)))
                    except OSError:
                        pass
                    continue
                upstream = peers.get(header)
                if upstream is None:
                    upstream = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                    upstream.connect(("127.0.0.1", port))
                    peers[header], senders[upstream] = upstream, header
                    chooser.register(upstream, selectors.EVENT_READ)
                try:
                    upstream.send(payload)
                except OSError:
                    pass
            elif side == "udp-expose":
                payload, sender = sock.recvfrom(65535)
                header = f"{sender[0]} {sender[1]}".encode()
                forward(bytes([len(header)]) + header + payload)
            else:
                try:
                    payload = sock.recv(65535)
                except OSError:
                    continue
                header = senders[sock]
                forward(bytes([len(header)]) + header + payload)


def check():
    """Relays one connection through `serve`, as `sandbox` and `host` do, and checks both TCP ends."""
    upstream_listener = socket.create_server(("127.0.0.1", 0))
    listener = socket.create_server(("127.0.0.1", 0))
    used = []

    class Recorded:  # hands `serve` the real listener and keeps what it accepted
        def accept(self):
            pair = listener.accept()
            used.append(pair[0])
            return pair

    def connect():
        used.append(nodelay(socket.create_connection(upstream_listener.getsockname())))
        return used[-1]

    threading.Thread(target=serve, args=(Recorded(), connect), daemon=True).start()
    caller = socket.create_connection(listener.getsockname())
    upstream_listener.settimeout(5)
    far, _ = upstream_listener.accept()
    caller.sendall(b"ping")
    far.settimeout(5)
    ok = far.recv(4) == b"ping" and len(used) == 2 and all(has_nodelay(sock) for sock in used)
    print("TCP_NODELAY is " + ("set" if ok else "NOT set") + " on the accepted and the upstream socket")
    sys.exit(0 if ok else 1)


def main():
    args = sys.argv[1:]
    if args == ["check"]:
        check()
    if args[0] == "--session":
        watch_session(int(args[1]))
        args = args[2:]
    side, path, port = args[0], args[1], int(args[-1])
    if side.startswith("udp-"):
        udp_relay(side, path, port, *args[2:-1])
        return
    if side == "host":
        if os.path.exists(path):
            os.unlink(path)
        listener = socket.socket(socket.AF_UNIX)
        listener.bind(path)
        connect = lambda: nodelay(socket.create_connection(("127.0.0.1", port)))
    else:
        listeners = []
        for address in (args[2] if side == "expose" else "127.0.0.1").split(","):
            listeners.append(socket.socket(socket.AF_INET6 if ":" in address else socket.AF_INET))
            listeners[-1].setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            listeners[-1].bind((address, port))
        # A Unix socket path is limited to 108 bytes and the cache folder can be deep, so
        # the socket is reached by its name from inside its folder.
        os.chdir(os.path.dirname(path) or ".")
        name = os.path.basename(path)

        def connect():
            upstream = socket.socket(socket.AF_UNIX)
            upstream.connect(name)
            return upstream
        for extra in listeners[1:]:
            extra.listen(16)
            threading.Thread(target=serve, args=(extra, connect), daemon=True).start()
        listener = listeners[0]
    listener.listen(16)
    serve(listener, connect)


if __name__ == "__main__":
    main()
