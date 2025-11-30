#/home/tanzious/.ipython/profile_default/startup

import json
import pandas as pd
import numpy as np
import os
import platform
from IPython import get_ipython

# --- Feature Detection ---
try:
    import polars as pl
    HAS_POLARS = True
except ImportError:
    HAS_POLARS = False

try:
    import pyarrow
    HAS_ARROW = True
except ImportError:
    HAS_ARROW = False

try:
    import ipykernel
    CONNECTION_FILE = ipykernel.get_connection_file()
except Exception:
    CONNECTION_FILE = None

# --- Configuration ---
SNAPSHOT_LIMIT = 5000 
METADATA_LIMIT = 2000 

def _get_snapshot_dir():
    if platform.system() == "Windows":
        base = os.environ.get("LOCALAPPDATA", os.getcwd())
        path = os.path.join(base, "nvim-data", "cache", "scivim_data")
    else:
        base = os.path.expanduser("~/.cache/nvim")
        path = os.path.join(base, "scivim_data")
    os.makedirs(path, exist_ok=True)
    return path

def _save_snapshot(df, name, directory):
    try:
        # 1. Try Saving as Feather (Fastest + PyArrow)
        if HAS_ARROW:
            file_path = os.path.join(directory, f"{name}.feather")
            
            # Polars LazyFrame -> Collect -> Write IPC
            if HAS_POLARS and isinstance(df, pl.LazyFrame):
                df.head(SNAPSHOT_LIMIT).collect().write_ipc(file_path)
            
            # Polars DataFrame -> Write IPC
            elif HAS_POLARS and isinstance(df, pl.DataFrame):
                if df.height > SNAPSHOT_LIMIT: 
                    df.head(SNAPSHOT_LIMIT).write_ipc(file_path)
                else: 
                    df.write_ipc(file_path)
            
            # Pandas -> Feather
            elif isinstance(df, pd.DataFrame):
                save_df = df.head(SNAPSHOT_LIMIT) if len(df) > SNAPSHOT_LIMIT else df
                save_df = save_df.reset_index(drop=True)
                save_df.to_feather(file_path)
                
        # 2. Fallback to Pickle
        else:
            file_path = os.path.join(directory, f"{name}.pkl")
            
            # Polars -> Pandas -> Pickle
            if HAS_POLARS and isinstance(df, pl.LazyFrame):
                df.head(SNAPSHOT_LIMIT).collect().to_pandas().to_pickle(file_path)
            elif HAS_POLARS and isinstance(df, pl.DataFrame):
                if df.height > SNAPSHOT_LIMIT: 
                    df.head(SNAPSHOT_LIMIT).to_pandas().to_pickle(file_path)
                else: 
                    df.to_pandas().to_pickle(file_path)
            
            # Pandas -> Pickle
            elif isinstance(df, pd.DataFrame):
                if len(df) > SNAPSHOT_LIMIT: 
                    df.head(SNAPSHOT_LIMIT).to_pickle(file_path)
                else: 
                    df.to_pickle(file_path)
                    
    except Exception as e:
        # Print error so we know if snapshotting fails
        print(f"⚠️ SciVim Snapshot Failed for '{name}': {e}")

def _extract_meta_generic(df, lib_type):
    meta = {}
    
    def get_samples(series):
        try:
            if lib_type == "polars": return series.head(10).cast(pl.Utf8).to_list()
            else: return series.dropna().head(10).astype(str).tolist()
        except: return []

    cols = df.columns if lib_type != "pandas" else df.columns.tolist()
    
    for col in cols:
        try:
            series = df[col]
            dtype = str(series.dtype)
            
            if lib_type == "polars":
                nulls = series.null_count()
                uniques = series.n_unique()
                is_numeric = series.dtype in [pl.Int8, pl.Int16, pl.Int32, pl.Int64, pl.UInt8, pl.UInt16, pl.UInt32, pl.UInt64, pl.Float32, pl.Float64]
            else:
                nulls = int(series.isnull().sum())
                uniques = int(series.nunique())
                is_numeric = pd.api.types.is_numeric_dtype(series)

            col_meta = { "dtype": dtype, "null_count": nulls, "unique_count": uniques, "sample_values": get_samples(series) }

            if is_numeric and uniques > 0:
                try:
                    if lib_type == "polars": arr = series.drop_nulls().to_numpy()
                    else: arr = series.dropna().to_numpy()
                    
                    if len(arr) > 0:
                        col_meta["min_val"] = float(np.min(arr))
                        col_meta["max_val"] = float(np.max(arr))
                        col_meta["mean_val"] = float(np.mean(arr))
                        col_meta["std_val"] = float(np.std(arr))
                        col_meta["median_val"] = float(np.median(arr))
                        
                        q1 = float(np.percentile(arr, 25))
                        q3 = float(np.percentile(arr, 75))
                        col_meta["q1"] = q1
                        col_meta["q3"] = q3
                        
                        iqr = q3 - q1
                        lower_bound = q1 - (1.5 * iqr)
                        upper_bound = q3 + (1.5 * iqr)
                        col_meta["outlier_count"] = int(np.sum((arr < lower_bound) | (arr > upper_bound)))
                        
                        hist_counts, _ = np.histogram(arr, bins=10)
                        col_meta["hist_counts"] = hist_counts.tolist()
                except Exception: pass 
            meta[col] = col_meta
        except Exception: meta[col] = {"dtype": "unknown", "sample_values": []}
    return cols, meta

def get_df_info(df, name):
    entry = { "name": name, "connection_file": CONNECTION_FILE, "metadata": {}, "columns": [], "lib": "pandas", "is_lazy": False }
    if HAS_POLARS and isinstance(df, pl.LazyFrame):
        entry["lib"] = "polars"; entry["is_lazy"] = True
        try:
            preview = df.head(METADATA_LIMIT).collect()
            cols, meta = _extract_meta_generic(preview, "polars")
            entry["columns"] = cols; entry["metadata"] = meta
        except Exception: entry["columns"] = []
    elif HAS_POLARS and isinstance(df, pl.DataFrame):
        entry["lib"] = "polars"
        cols, meta = _extract_meta_generic(df, "polars")
        entry["columns"] = cols; entry["metadata"] = meta
    elif isinstance(df, pd.DataFrame):
        entry["lib"] = "pandas"
        cols, meta = _extract_meta_generic(df, "pandas")
        entry["columns"] = cols; entry["metadata"] = meta
    return entry

def commit_session_vars(session_id, session_env):
    """
    Saves all DataFrame variables present in the Live Transform session environment
    as new snapshots and triggers a context refresh.
    """
    snapshot_dir = _get_snapshot_dir()
    newly_exposed_count = 0
    
    for var_name, obj in session_env.items():
        if var_name in ['pd', 'np', 'pl', 'os', 'col', 'lit', 'when', 'df']:
            continue
            
        is_df = False
        if isinstance(obj, pd.DataFrame): is_df = True
        if HAS_POLARS and (isinstance(obj, pl.DataFrame) or isinstance(obj, pl.LazyFrame)): is_df = True
        
        if is_df:
            try:
                new_name = f"{session_id}__{var_name}"
                _save_snapshot(obj, new_name, snapshot_dir)
                newly_exposed_count += 1
            except Exception as e:
                print(f"⚠️ Failed to save {var_name} from session {session_id}: {e}")

    # Optional: print summary
    # print(f"✅ Saved {newly_exposed_count} new DataFrame(s) from session {session_id}.")


def vim_expose():
    ip = get_ipython()
    if not ip: return
    export_data = {}
    found_count = 0
    snapshot_dir = _get_snapshot_dir()
    all_vars = list(ip.user_ns.items())
    
    for var_name, obj in all_vars:
        if var_name.startswith('_'): continue
        is_df = False
        if isinstance(obj, pd.DataFrame): is_df = True
        if HAS_POLARS and (isinstance(obj, pl.DataFrame) or isinstance(obj, pl.LazyFrame)): is_df = True
        if is_df:
            try:
                export_data[var_name] = get_df_info(obj, var_name)
                # Snapshot creation is part of the expose process
                _save_snapshot(obj, var_name, snapshot_dir)
                found_count += 1
            except Exception: pass

    try:
        with open(".vim_context.json", "w") as f:
            json.dump(export_data, f, indent=2, allow_nan=False)
        print(f"✅ Exposing {found_count} DataFrames")
    except Exception: pass

def auto_run_scivim(result=None):
    if result and result.error_in_exec: return
    vim_expose()

def register_hooks():
    ip = get_ipython()
    if not ip: return
    vim_expose()
    ip.events.register('post_run_cell', auto_run_scivim)
    print("🚀 SciVim Auto-Sync Enabled")

if __name__ == "__main__":
    register_hooks()
