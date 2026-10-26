#!/usr/bin/env python3
"""Relay TCP sederhana untuk WSL2 -> Docker.

Kadang port yang dipublikasikan Docker (mis. 55321) tidak ikut diteruskan ke
Windows setelah container restart. Relay ini mendengarkan di port baru di WSL
(port baru selalu diteruskan) lalu meneruskan ke port Docker.

Pemakaian:
  python3 scripts/wsl-port-relay.py 56021 127.0.0.1 55321
"""

import socket
import sys
import threading


def pump(src: socket.socket, dst: socket.socket) -> None:
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        try:
            dst.shutdown(socket.SHUT_WR)
        except OSError:
            pass


def handle(client: socket.socket, host: str, port: int) -> None:
    try:
        upstream = socket.create_connection((host, port), timeout=10)
    except OSError:
        client.close()
        return

    threading.Thread(target=pump, args=(client, upstream), daemon=True).start()
    threading.Thread(target=pump, args=(upstream, client), daemon=True).start()


def main() -> None:
    if len(sys.argv) != 4:
        print("pemakaian: wsl-port-relay.py <listen_port> <target_host> <target_port>")
        raise SystemExit(2)

    listen_port = int(sys.argv[1])
    host = sys.argv[2]
    port = int(sys.argv[3])

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", listen_port))
    server.listen(128)
    print(f"relay {listen_port} -> {host}:{port}", flush=True)

    while True:
        client, _ = server.accept()
        handle(client, host, port)


if __name__ == "__main__":
    main()
