import sys, os, socket, time
D = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/")
def session(cmds, port=6510):
    s = socket.create_connection(("127.0.0.1", port)); s.settimeout(0.5)
    out = b""
    def drain(t=0.5):
        nonlocal out
        s.settimeout(t)
        try:
            while True:
                d = s.recv(65536)
                if not d: break
                out += d
        except socket.timeout: pass
    s.sendall(b"r\n"); drain()
    for c in cmds:
        s.sendall((c + "\n").encode()); drain(1.0 if not c.startswith(("save","bsave","s ")) else 4.0)
    s.sendall(b"x\n"); drain(0.2)
    s.close()
    return out.decode("latin-1")
if __name__ == "__main__":
    name = sys.argv[1]
    extra = sys.argv[2:]
    print(session(extra + ['screenshot "%s/%s.png" 2' % (D, name)]))
