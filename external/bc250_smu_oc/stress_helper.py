import subprocess
import atexit

_process = None

def stress_start():
    global _process
    if _process is None:
        _process = subprocess.Popen(["stress", "--cpu", "12"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def stress_stop():
    global _process
    if _process:
        _process.terminate()
        _process.wait(timeout=1)
        _process = None

atexit.register(stress_stop)
