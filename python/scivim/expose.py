# /home/tanzious/scivim/python/scivim/expose.py
import os
import json
import pandas as pd
import numpy as np
import platform

# -----------------------------------------------------------------------------
# VECTORIZED METADATA ENGINE (Sync with Daemon)
# -----------------------------------------------------------------------------
def _extract_meta_vectorized(df):
    """
    High-speed metadata extraction. 
    Shifts workload from Python loops to C-level vectorized ops.
    """
    meta = {}
    cols = df.columns.tolist()
    
    # 1. Bulk stats (The 'Expensive' parts)
    null_counts = df.isna().sum().to_dict()
    unique_counts = df.nunique().to_dict()
    
    # 2. Bulk Numeric stats
    numeric_df = df.select_dtypes(include=[np.number])
    stats_df = numeric_df.describe().to_dict() if not numeric_df.empty else {}

    for col in cols:
        col_meta = {
            "dtype": str(df[col].dtype),
            "null_count": int(null_counts.get(col, 0)),
            "unique_count": int(unique_counts.get(col, 0)),
            "sample_values": df[col].dropna().head(5).astype(str).tolist()
        }
        if col in stats_df:
            s = stats_df[col]
            col_meta.update({
                "min": float(s['min']), "max": float(s['max']),
                "mean": float(s['mean']), "median": float(s['50%'])
            })
        meta[col] = col_meta
    return meta

# -----------------------------------------------------------------------------
# CORE EXPOSURE LOGIC
# -----------------------------------------------------------------------------
def scivim_expose(name, df, cache_dir):
    """
    Saves snapshot and metadata. 
    Optimized for kernel-to-daemon handoff.
    """
    try:
        # Ensure path exists
        if not os.path.exists(cache_dir):
            os.makedirs(cache_dir, exist_ok=True)

        # 1. Save Data (Standardize on Feather for speed)
        file_path = os.path.join(cache_dir, f"{name}.feather")
        
        # Snapshot limit to prevent IO bloat (keep it under 100k rows for UI responsiveness)
        LIMIT = 100000
        save_df = df.head(LIMIT).reset_index(drop=True)
        save_df.to_feather(file_path)

        # 2. Save Metadata (The JSON context used by LSP/UI)
        meta_path = os.path.join(cache_dir, f"{name}.json")
        context = {
            "name": name,
            "shape": list(df.shape),
            "columns": df.columns.tolist(),
            "metadata": _extract_meta_vectorized(save_df),
            "updated_at": os.path.getmtime(file_path)
        }

        with open(meta_path, 'w') as f:
            json.dump(context, f)

        return True
    except Exception as e:
        # We fail silently to avoid breaking the user's notebook execution
        return False
