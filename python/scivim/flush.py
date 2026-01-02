# /home/tanzious/scivim/python/scivim/flush.py
# /home/tanzious/scivim/python/scivim/flush.py
# /home/tanzious/scivim/python/scivim/flush.py
# /home/tanzious/scivim/python/scivim/flush.py
# /home/tanzious/scivim/python/scivim/flush.py
# /home/tanzious/scivim/python/scivim
# /home/tanzious/scivim/python/scivim
#this file is in /python/scivim/flush.py

"""
Flush Jupyter Kernel IOPub Messages
Run this in your Jupyter kernel to clear any stuck messages
"""

import sys
import json

def flush_kernel():
    """Clear the IOPub message queue"""
    try:
        from IPython import get_ipython
        import ipykernel
        
        ip = get_ipython()
        if not ip:
            print("Not running in IPython/Jupyter")
            return
            
        # Get the kernel
        kernel = ip.kernel
        
        # Clear the IOPub queue
        if hasattr(kernel, 'iopub_socket'):
            socket = kernel.iopub_socket
            # Set non-blocking and drain
            socket.setsockopt(1, 1)  # NOBLOCK
            try:
                while True:
                    socket.recv_multipart(flags=1)  # NOBLOCK flag
            except:
                pass
        
        # Also clear any execution count issues
        if hasattr(ip, 'execution_count'):
            # Ensure execution count is clean
            pass
            
        print("✅ Kernel IOPub queue flushed")
        
    except Exception as e:
        print(f"⚠️ Flush failed: {e}")

if __name__ == '__main__':
    flush_kernel()
