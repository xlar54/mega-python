"""mon.py cmd1 ; cmd2 ; ...   (single arg, ';;' separated). Use ' for " inside."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import snap
cmds = [c.strip().replace("'", '"') for c in " ".join(sys.argv[1:]).split(";;")]
print(snap.session(cmds))
