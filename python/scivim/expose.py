# /home/tanzious/scivim/python/scivim/expose.py
import os
import json
import pandas as pd
import numpy as np
from IPython import get_ipython

# --- Feature Detection ---
try:
    import polars as pl
    HAS_POLARS = True
except ImportError:
    HAS_POLARS = False

# -----------------------------------------------------------------------------
# METADATA ENGINE (Strict alignment with context.lua)
# -----------------------------------------------------------------------------
def _extract_column_metadata(df, lib_type="pandas"):
    """
    Extracts vectorized stats required by VizInspect.
    Fixes the 'list has no attribute tolist' bug by using native accessors.
    """
    meta = {}
    # Fix: Get column names safely for both libs
    cols = df.columns if lib_type == "polars" else df.columns.tolist()
    
    for col in cols:
        series = df[col]
        
        # 1. Base Metadata
        col_meta = {
            "dtype": str(series.dtype),
            "null_count": int(series.null_count()) if lib_type == "polars" else int(series.isna().sum()),
            "unique_count": int(series.n_unique()) if lib_type == "polars" else int(series.nunique()),
            "sample_values": (series.head(10).cast(pl.Utf8).to_list() if lib_type == "polars" 
                             else series.dropna().head(10).astype(str).tolist())
        }

        # 2. Key Metrics for the Inspector Panel
        is_num = series.dtype.is_numeric() if lib_type == "polars" else pd.api.types.is_numeric_dtype(series)

        if is_num:
            try:
                # Vectorized stats calculation
                s_pd = series.to_pandas() if lib_type == "polars" else series
                s_clean = s_pd.dropna()
                
                if not s_clean.empty:
                    desc = s_clean.describe()
                    q1, q3 = float(desc.get('25%', 0)), float(desc.get('75%', 0))
                    iqr = q3 - q1
                    
                    # Align keys with context.lua:create_column_entry
                    col_meta.update({
                        "min_val": float(desc.get('min', 0)),
                        "max_val": float(desc.get('max', 0)),
                        "mean_val": float(desc.get('mean', 0)),
                        "median_val": float(s_clean.median()),
                        "std_val": float(desc.get('std', 0)),
                        "q1": q1,
                        "q3": q3,
                        "outlier_count": int(((s_clean < (q1 - 1.5 * iqr)) | (s_clean > (q3 + 1.5 * iqr))).sum())
                    })
                    
                    # Sparkline data for UI histograms
                    counts, _ = np.histogram(s_clean, bins=10)
                    col_meta["hist_counts"] = counts.tolist()
            except Exception:
                pass
        
        meta[col] = col_meta
    return meta

# -----------------------------------------------------------------------------
# CORE EXPOSURE LOGIC
# -----------------------------------------------------------------------------
def vim_expose():
    ip = get_ipython()
    if not ip: return
    
    export_data = {}
    found_count = 0
    cache_dir = os.path.expanduser("~/.cache/nvim/scivim_data")
    if not os.path.exists(cache_dir):
        os.makedirs(cache_dir, exist_ok=True)

    for var_name, obj in list(ip.user_ns.items()):
        if var_name.startswith('_'): continue
        
        lib = None
        if isinstance(obj, pd.DataFrame): lib = "pandas"
        elif HAS_POLARS and isinstance(obj, (pl.DataFrame, pl.LazyFrame)): lib = "polars"
        
        if lib:
            try:
                # 1. Prepare Data Snapshot (Handle LazyFrames)
                working_df = obj
                if lib == "polars" and isinstance(obj, pl.LazyFrame):
                    working_df = obj.head(10000).collect()
                else:
                    working_df = obj.head(10000)

                # 2. Vectorized I/O (Feather/IPC)
                file_path = os.path.join(cache_dir, f"{var_name}.feather")
                if lib == "polars":
                    working_df.write_ipc(file_path)
                else:
                    working_df.reset_index(drop=True).to_feather(file_path)

                # 3. Comprehensive Metadata Extraction
                # Fix: Align with context.lua expectations
                export_data[var_name] = {
                    "name": var_name,
                    "lib": lib,
                    "columns": working_df.columns if lib == "polars" else working_df.columns.tolist(),
                    "shape": list(obj.shape) if hasattr(obj, "shape") else [None, len(working_df.columns)],
                    "metadata": _extract_column_metadata(working_df, lib)
                }
                found_count += 1
            except Exception as e:
                print(f"⚠️ SciVim error on {var_name}: {e}")

    # Write the context file for the Neovim client
    try:
        with open(".vim_context.json", "w") as f:
            json.dump(export_data, f)
        if found_count > 0:
            print(f"✅ SciVim: {found_count} DataFrames Exposed")
    except Exception:
        pass

# -----------------------------------------------------------------------------
# AUTO-REGISTRATION
# -----------------------------------------------------------------------------
def register_scivim():
    ip = get_ipython()
    if ip:
        ip.user_ns['vim_expose'] = vim_expose
        # Check to avoid duplicate registration
        if 'auto_run_scivim' not in [f.__name__ for f in ip.events.callbacks['post_run_cell']]:
            ip.events.register('post_run_cell', lambda result=None: vim_expose())
        print("🚀 SciVim Auto-Sync Enabled")

if __name__ == "__main__":
    register_scivim()
