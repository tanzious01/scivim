# /home/tanzious/scivim/python/scivim/utils.py
# /home/tanzious/scivim/python/scivim/utils.py
# /home/tanzious/scivim/python/scivim/utils.py
# /home/tanzious/scivim/python/scivim/utils.py
# /home/tanzious/scivim/python/scivim/utils.py
# /home/tanzious/scivim/python/scivim/utils.py
# /home/tanzious/scivim/python/scivim
# /home/tanzious/scivim/python/scivim
#this file is in /python/scivim/utils.py
import os
import pandas as pd
import platform

# Detect PyArrow for fast feather saves
try:
    import pyarrow
    HAS_ARROW = True
except ImportError:
    HAS_ARROW = False

def get_scivim_path():
    if platform.system() == "Windows":
        base = os.environ.get("LOCALAPPDATA", os.getcwd())
        path = os.path.join(base, "nvim-data", "cache", "scivim_data")
    else:
        base = os.path.expanduser("~/.cache/nvim")
        path = os.path.join(base, "scivim_data")
    
    os.makedirs(path, exist_ok=True)
    return path

def scivim_update(df, name):
    """
    Saves a snapshot of the dataframe for SciVim Live Transform.
    """
    try:
        path = get_scivim_path()
        
        # Prepare the dataframe (sample limit)
        LIMIT = 5000
        
        # Handle Polars -> Pandas conversion if necessary
        # (Feather works best with Pandas or direct Polars IPC, but let's standardize on Pandas for this helper)
        if "polars" in str(type(df)):
             save_df = df.head(LIMIT).to_pandas()
        else:
             save_df = df.head(LIMIT)

        if HAS_ARROW:
            # === SAVE AS FEATHER ===
            file_path = os.path.join(path, f"{name}.feather")
            # Reset index is often safer for feather
            save_df = save_df.reset_index(drop=True)
            save_df.to_feather(file_path)
            print(f"✅ Snapshot updated (Feather): '{name}'")
        else:
            # === SAVE AS PICKLE ===
            file_path = os.path.join(path, f"{name}.pkl")
            save_df.to_pickle(file_path)
            print(f"✅ Snapshot updated (Pickle): '{name}'")
            
    except Exception as e:
        print(f"❌ Failed to snapshot: {e}")
