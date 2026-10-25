import socket, sys, time

def cmd(c, timeout=3.0, port=6510):
    s = socket.create_connection(("127.0.0.1", port))
    s.settimeout(0.3)
    out = b""
    # drain banner
    t0 = time.time()
    try:
        while True:
            d = s.recv(65536)
            if not d: break
            out += d
    except socket.timeout:
        pass
    out = b""
    s.sendall((c + "\n").encode())
    t0 = time.time()
    while time.time() - t0 < timeout:
        try:
            d = s.recv(65536)
            if not d: break
            out += d
            t0 = time.time()
        except socket.timeout:
            if out:
                # wait a little more
                pass
    s.close()
    return out.decode("latin-1")

if __name__ == "__main__":
    for c in sys.argv[1:]:
        print(cmd(c))
