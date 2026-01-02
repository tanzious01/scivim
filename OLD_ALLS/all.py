# /home/tanzious/scivim/OLD_ALLS/all.py
# /home/tanzious/scivim/OLD_ALLS/all.py
# /home/tanzious/scivim/OLD_ALLS/all.py
# /home/tanzious/scivim/OLD_ALLS/all.py
# /home/tanzious/scivim/OLD_ALLS/all.py
# /home/tanzious/scivim/OLD_ALLS/all.py
# /home/tanzious/scivim/OLD_ALLS
# /home/tanzious/scivim/OLD_ALLS
#daemon.py located in /python/scivim/daemon.py
import sys
import json
import os
import pandas as pd
import io
import contextlib

# Optional Polars support
try:
    import polars as pl
    HAS_POLARS = True
except ImportError:
    HAS_POLARS = False

# Optional DuckDB support
try:
    import duckdb
    HAS_DUCKDB = True
except ImportError:
    HAS_DUCKDB = False

# -----------------------------------------------------------------------------
# GLOBAL STATE (The Cache)
# -----------------------------------------------------------------------------
CACHE = {}

def load_or_get_cached_df(file_path, lib, is_lazy):
    """
    Smart loader: reads .feather or .pkl based on extension and caches result.
    """
    global CACHE

    # 1. Check file existence
    if not os.path.exists(file_path):
        if file_path in CACHE:
            del CACHE[file_path]
        raise FileNotFoundError(f"Snapshot not found: {file_path}")

    current_mtime = os.path.getmtime(file_path)
    
    # 2. Check Cache
    if file_path in CACHE:
        cached = CACHE[file_path]
        if cached['mtime'] == current_mtime:
            return cached['df']

    # 3. MISS: Load from disk
    try:
        if file_path.endswith(".feather"):
            df_base = pd.read_feather(file_path)
        else:
            df_base = pd.read_pickle(file_path)
    except Exception as e:
        raise IOError(f"Failed to read snapshot ({os.path.basename(file_path)}): {str(e)}")

    # Convert to Polars if required
    if lib == "polars" and HAS_POLARS:
        if is_lazy:
            df_final = pl.from_pandas(df_base).lazy()
        else:
            df_final = pl.from_pandas(df_base)
    else:
        df_final = df_base

    # Update Cache
    CACHE[file_path] = {
        'df': df_final,
        'mtime': current_mtime
    }
    
    return df_final

def execute_request(data):
    """
    Process a single JSON request and return a JSON dictionary response.
    """
    request_type = data.get("type", "transform")
    
    if request_type == "transform":
        return _handle_transform(data)
    elif request_type == "metadata_all":
        return _handle_metadata_all(data)
    elif request_type == "analyze_relationships":
        return _handle_relationships(data)
    elif request_type == "shape":
        return {"error": "Shape request not yet implemented"}
    
    return {"error": f"Unknown request type: {request_type}"}

def _handle_metadata_all(data):
    """Get metadata for all DataFrames in the cache directory."""
    cache_dir = data.get("cache_dir", "")
    # NEW: Filter by specific names if provided
    filter_names = set(data.get("names", []))
    
    if not os.path.exists(cache_dir):
        return {"error": f"Cache directory not found: {cache_dir}"}
        
    results = {}
    for filename in os.listdir(cache_dir):
        if not (filename.endswith('.feather') or filename.endswith('.pkl')):
            continue
            
        df_name = filename.replace('.feather', '').replace('.pkl', '')
        
        # [[ NEW: FILTERING LOGIC ]]
        # If the UI sent a list of names, skip anything NOT in that list.
        # This prevents showing stale files from old sessions.
        if filter_names and df_name not in filter_names:
            continue

        file_path = os.path.join(cache_dir, filename)
        
        try:
            # Load the dataframe
            if filename.endswith('.feather'):
                df = pd.read_feather(file_path)
            else:
                df = pd.read_pickle(file_path)
            
            # Extract metadata
            try:
                # Requires 'tabulate' for markdown
                head_str = df.head(5).to_markdown(index=False, tablefmt="github")
            except (ImportError, AttributeError):
                head_str = df.head(5).to_string()

            results[df_name] = {
                "name": df_name,
                "shape": list(df.shape),
                "columns": df.columns.tolist(),
                "dtypes": {str(col): str(dtype) for col, dtype in df.dtypes.items()},
                "head": head_str
            }
        except Exception as e:
            results[df_name] = {"error": str(e)}
            
    return {"dataframes": results}

def _handle_relationships(data):
    """Analyze potential join relationships between DataFrames."""
    cache_dir = data.get("cache_dir", "")
    
    if not os.path.exists(cache_dir):
        return {"error": f"Cache directory not found: {cache_dir}"}
        
    # Load all dataframes
    dataframes = {}
    for filename in os.listdir(cache_dir):
        if not (filename.endswith('.feather') or filename.endswith('.pkl')):
            continue
            
        df_name = filename.replace('.feather', '').replace('.pkl', '')
        file_path = os.path.join(cache_dir, filename)
        
        try:
            if filename.endswith('.feather'):
                dataframes[df_name] = pd.read_feather(file_path)
            else:
                dataframes[df_name] = pd.read_pickle(file_path)
        except:
            continue
            
    # Find relationships
    relationships = []
    df_names = list(dataframes.keys())
    
    for i, name1 in enumerate(df_names):
        for name2 in df_names[i+1:]:
            df1, df2 = dataframes[name1], dataframes[name2]
            
            # Find common columns
            common = set(df1.columns) & set(df2.columns)
            
            for col in common:
                # Heuristic: Columns ending in 'id' or just 'id' are likely join keys
                if str(col).lower().endswith('id') or str(col).lower() == 'id':
                    relationships.append({
                        "from_df": name1,
                        "to_df": name2,
                        "from_col": str(col),
                        "to_col": str(col),
                        "type": "exact_match"
                    })
                    
            # Look for foreign key patterns (customer_id -> id)
            for col1 in df1.columns:
                c1_str = str(col1)
                if c1_str.endswith('_id'):
                    base = c1_str.replace('_id', '')
                    if 'id' in df2.columns:
                        relationships.append({
                            "from_df": name1,
                            "to_df": name2,
                            "from_col": c1_str,
                            "to_col": "id",
                            "type": "foreign_key"
                        })
    return {"relationships": relationships}

def _handle_transform(data):
    file_path = data.get("file_path", "")
    lib = data.get("lib", "pandas")
    code = data.get("code", "").strip()
    is_lazy = data.get("is_lazy", False)

    # 1. Prepare Environment
    local_env = {}
    
    try:
        df = load_or_get_cached_df(file_path, lib, is_lazy)
        
        local_env['df'] = df
        local_env['pd'] = pd
        if 'numpy' in sys.modules:
            local_env['np'] = sys.modules['numpy']
            
        if lib == "polars" and HAS_POLARS:
            local_env['pl'] = pl
            local_env['col'] = pl.col
            local_env['lit'] = pl.lit
            local_env['when'] = pl.when
            
    except Exception as e:
        return {"error": f"Data Load Error: {str(e)}"}

    # 2. Check for SQL (DuckDB)
    is_sql = False
    if HAS_DUCKDB and len(code) > 0:
        start_token = code.split()[0].upper() if code.split() else ""
        if start_token in ["SELECT", "WITH", "PRAGMA", "DESCRIBE", "SHOW", "EXPLAIN"]:
            is_sql = True

    # 3. Execute Code
    stdout_capture = io.StringIO()
    result_obj = None
    
    try:
        with contextlib.redirect_stdout(stdout_capture):
            if is_sql:
                try:
                    con = duckdb.connect()
                    if 'df' in local_env:
                        con.register('df', local_env['df'])
                    result_obj = con.sql(code).limit(50).df()
                except Exception as e:
                    return {"error": f"SQL Error: {str(e)}"}
            else:
                try:
                    result_obj = eval(code, {}, local_env)
                except SyntaxError:
                    exec(code, {}, local_env)
                    result_obj = local_env.get('df')
                except Exception as e:
                    return {"error": f"Execution Error: {str(e)}"}
                
    except Exception as e:
        return {"error": f"Runtime Error: {str(e)}"}

    # 4. Process Result
    if HAS_POLARS and isinstance(result_obj, pl.LazyFrame):
        try:
            result_obj = result_obj.collect()
        except Exception as e:
            return {"error": f"Lazy Collection Failed: {str(e)}"}
            
    if HAS_DUCKDB and isinstance(result_obj, duckdb.DuckDBPyRelation):
         result_obj = result_obj.limit(50).df()

    output_text = ""
    try:
        if HAS_POLARS and isinstance(result_obj, pl.DataFrame):
            output_text = str(result_obj.head(50))
        elif isinstance(result_obj, pd.DataFrame):
            try:
                output_text = result_obj.head(50).to_markdown(index=False, tablefmt="github")
            except (ImportError, AttributeError):
                output_text = result_obj.head(50).to_string()
        else:
            output_text = str(result_obj) if result_obj is not None else ""
            
    except Exception as e:
        return {"error": f"Serialization Error: {str(e)}"}

    return {"text_table": output_text}

def main():
    """
    Main Loop: Reads line-by-line JSON from Stdin.
    """
    for line in sys.stdin:
        if not line.strip():
            continue
            
        try:
            request_data = json.loads(line)
            response_data = execute_request(request_data)
        except json.JSONDecodeError:
            response_data = {"error": "Invalid JSON input"}
        except Exception as e:
            response_data = {"error": f"Critical Server Error: {str(e)}"}
            
        sys.stdout.write(json.dumps(response_data) + "\n")
        sys.stdout.flush()

if __name__ == "__main__":
    main()




#/home/tanzious/.ipython/profile_default/startup
#this file is in /python/scivim/expose.py
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
