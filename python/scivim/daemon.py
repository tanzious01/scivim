# /home/tanzious/scivim/python/scivim/daemon.py
# /home/tanzious/scivim/python/scivim/daemon.py
# /home/tanzious/scivim/python/scivim/daemon.py
# /home/tanzious/scivim/python/scivim/daemon.py
import sys
import json
import os
import pandas as pd
import io
import contextlib
import platform

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

# NOTE: Matplotlib/Seaborn are imported lazily to speed up startup.

# -----------------------------------------------------------------------------
# GLOBAL STATE (The Cache)
# -----------------------------------------------------------------------------
CACHE = {}

# Optimization: Cache relationship graph to avoid O(N^2) IO operations
REL_GRAPH_CACHE = {
    "hash": None,
    "data": []
}

def load_or_get_cached_df(file_path, lib, is_lazy):
    """
    Smart loader: reads .feather or .pkl based on extension and caches result.
    Uses mtime + size for cache invalidation.
    """
    global CACHE

    # 1. Check file existence
    if not os.path.exists(file_path):
        if file_path in CACHE:
            del CACHE[file_path]
        raise FileNotFoundError(f"Snapshot not found: {file_path}")

    current_stat = os.stat(file_path)
    # Robust check: mtime AND size
    current_key = (current_stat.st_mtime, current_stat.st_size)
    
    # 2. Check Cache
    if file_path in CACHE:
        cached = CACHE[file_path]
        if cached['key'] == current_key:
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
        'key': current_key
    }
    
    return df_final

def execute_request(data):
    """
    Process a single JSON request and return a JSON dictionary response.
    """
    request_type = data.get("type", "transform")
    
    try:
        if request_type == "transform":
            return _handle_transform(data)
        elif request_type == "preview":
            return _handle_preview(data)
        elif request_type == "metadata_all":
            return _handle_metadata_all(data)
        elif request_type == "analyze_relationships":
            return _handle_relationships(data)
        elif request_type == "shape":
            return _handle_shape(data)
        
        return {"error": f"Unknown request type: {request_type}"}
    except Exception as e:
        return {"error": f"Server Exception: {str(e)}"}

# -----------------------------------------------------------------------------
# HANDLERS
# -----------------------------------------------------------------------------

def _handle_shape(data):
    file_path = data.get("file_path", "")
    lib = data.get("lib", "pandas")
    try:
        # For shape, we don't need lazy evaluation usually
        df = load_or_get_cached_df(file_path, lib, False)
        return {"shape": df.shape}
    except Exception as e:
        return {"error": str(e)}

def _handle_preview(data):
    """
    Generates a plot image from code and returns the path.
    Uses LAZY IMPORTS for plotting libs.
    """
    # 1. Lazy Import
    try:
        import matplotlib
        import matplotlib.pyplot as plt
        import seaborn as sns
        # Force non-interactive backend to prevent window popping
        matplotlib.use('Agg') 
    except ImportError:
        return {"error": "Matplotlib/Seaborn not installed in daemon environment"}

    code = data.get("code", "")
    tmp_path = data.get("out_path", "")
    cache_dir = data.get("cache_dir", "")
    
    # 2. Construct context
    local_env = {}
    local_env['pd'] = pd
    local_env['plt'] = plt
    local_env['sns'] = sns
    if HAS_POLARS: local_env['pl'] = pl
    
    # 3. Inject DataFrames from cache dir (Smart Load)
    if os.path.exists(cache_dir):
        try:
            with os.scandir(cache_dir) as it:
                for entry in it:
                    if entry.is_file() and (entry.name.endswith(".feather") or entry.name.endswith(".pkl")):
                        name = entry.name.replace(".feather", "").replace(".pkl", "")
                        try:
                            df = load_or_get_cached_df(entry.path, "pandas", False)
                            local_env[name] = df
                        except: pass
        except FileNotFoundError: pass

    try:
        plt.clf()
        plt.close('all')
        
        # Check for Plotly + Kaleido issue
        if "plotly" in code and "write_image" in code:
            try:
                import kaleido
            except ImportError:
                return {"error": "Plotly export requires the 'kaleido' package. Please install it with pip."}

        # Strip blocking show() calls
        clean_code = code.replace("plt.show()", "")
        
        exec(clean_code, {}, local_env)
        
        if os.path.exists(tmp_path): os.remove(tmp_path)
        plt.savefig(tmp_path, dpi=100, bbox_inches='tight')
        
        return {"status": "ok", "path": tmp_path}
    except Exception as e:
        return {"error": f"Preview Generation Error: {str(e)}"}

def _handle_metadata_all(data):
    """Get metadata for all DataFrames in the cache directory."""
    cache_dir = data.get("cache_dir", "")
    filter_names = set(data.get("names", []))
    
    if not os.path.exists(cache_dir):
        return {"error": f"Cache directory not found: {cache_dir}"}
        
    results = {}
    
    # Use scandir for iteration efficiency
    try:
        with os.scandir(cache_dir) as it:
            for entry in it:
                if not entry.is_file(): continue
                
                filename = entry.name
                if not (filename.endswith('.feather') or filename.endswith('.pkl')):
                    continue
                    
                df_name = filename.replace('.feather', '').replace('.pkl', '')
                
                if filter_names and df_name not in filter_names:
                    continue

                try:
                    # Leverage cache loader
                    df = load_or_get_cached_df(entry.path, "pandas", False)
                    
                    try:
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
    except Exception as e:
        return {"error": str(e)}
            
    return {"dataframes": results}

def _handle_relationships(data):
    """
    Analyze potential join relationships using MEMORY CACHE.
    Optimized with os.scandir to avoid O(N) syscalls on checks.
    """
    cache_dir = data.get("cache_dir", "")
    
    if not os.path.exists(cache_dir):
        return {"error": f"Cache directory not found"}

    # 1. Check if we need to recompute (Directory Hash)
    current_files = []
    try:
        with os.scandir(cache_dir) as it:
            for entry in it:
                if entry.is_file() and (entry.name.endswith('.feather') or entry.name.endswith('.pkl')):
                    # Use cached stat info from scandir
                    mtime = entry.stat().st_mtime
                    current_files.append(f"{entry.name}_{mtime}")
    except FileNotFoundError:
        pass
    
    # Hash of sorted file states
    dir_hash = hash(tuple(sorted(current_files)))
    
    # HIT: Return cached graph if directory hash matches
    if REL_GRAPH_CACHE["hash"] == dir_hash and REL_GRAPH_CACHE["data"]:
        return {"relationships": REL_GRAPH_CACHE["data"]}

    # MISS: Compute
    df_map = {} # name -> columns (list)
    
    try:
        with os.scandir(cache_dir) as it:
            for entry in it:
                if entry.is_file() and (entry.name.endswith('.feather') or entry.name.endswith('.pkl')):
                    name = entry.name.replace('.feather', '').replace('.pkl', '')
                    try:
                        # OPTIMIZATION: Use the memory cache loader!
                        df = load_or_get_cached_df(entry.path, "pandas", False)
                        df_map[name] = list(df.columns)
                    except: continue
    except FileNotFoundError: pass

    relationships = []
    names = list(df_map.keys())
    
    for i, name1 in enumerate(names):
        for name2 in names[i+1:]:
            cols1 = df_map[name1]
            cols2 = df_map[name2]
            
            # 1. Exact Name Matches (e.g. 'customer_id' == 'customer_id')
            common = set(cols1) & set(cols2)
            for c in common:
                if 'id' in c.lower():
                    relationships.append({
                        "from_df": name1, "to_df": name2,
                        "from_col": c, "to_col": c, "type": "exact_match"
                    })

            # 2. FK Patterns (e.g. 'user_id' -> 'id')
            if 'id' in cols2:
                for c1 in cols1:
                    if c1 == f"{name2}_id" or (name2.endswith('s') and c1 == f"{name2[:-1]}_id"):
                         relationships.append({
                            "from_df": name1, "to_df": name2,
                            "from_col": c1, "to_col": "id", "type": "foreign_key"
                        })
            # Reverse check
            if 'id' in cols1:
                for c2 in cols2:
                     if c2 == f"{name1}_id" or (name1.endswith('s') and c2 == f"{name1[:-1]}_id"):
                         relationships.append({
                            "from_df": name2, "to_df": name1,
                            "from_col": c2, "to_col": "id", "type": "foreign_key"
                        })

    # Update Cache
    REL_GRAPH_CACHE["hash"] = dir_hash
    REL_GRAPH_CACHE["data"] = relationships
    
    return {"relationships": relationships}

def _handle_transform(data):
    file_path = data.get("file_path", "")
    # NEW: Accept explicit cache_dir for Workspace Loading
    cache_dir = data.get("cache_dir", "")
    lib = data.get("lib", "pandas")
    code = data.get("code", "").strip()
    is_lazy = data.get("is_lazy", False)

    # 1. Prepare Environment
    local_env = {}
    local_env['pd'] = pd
    if 'numpy' in sys.modules:
        local_env['np'] = sys.modules['numpy']
        
    if HAS_POLARS:
        local_env['pl'] = pl
        local_env['col'] = pl.col
        local_env['lit'] = pl.lit
        local_env['when'] = pl.when
    
    # 2. Load Workspace (Multi-DataFrame Support)
    if not cache_dir:
        if file_path:
             cache_dir = os.path.dirname(file_path)
        else:
             if platform.system() == "Windows":
                 base = os.environ.get("LOCALAPPDATA", os.getcwd())
                 cache_dir = os.path.join(base, "nvim-data", "cache", "scivim_data")
             else:
                 base = os.path.expanduser("~/.cache/nvim")
                 cache_dir = os.path.join(base, "scivim_data")

    if os.path.exists(cache_dir):
        try:
            with os.scandir(cache_dir) as it:
                for entry in it:
                    if entry.is_file() and (entry.name.endswith(".feather") or entry.name.endswith(".pkl")):
                        name = entry.name.replace(".feather", "").replace(".pkl", "")
                        try:
                            # Load into env with variable name matching dataframe name
                            df_ws = load_or_get_cached_df(entry.path, lib, is_lazy)
                            local_env[name] = df_ws
                        except Exception: 
                            pass
        except Exception: 
            pass

    # 3. Load Target DataFrame (Alias to 'df')
    if file_path and os.path.exists(file_path):
        try:
            df = load_or_get_cached_df(file_path, lib, is_lazy)
            
            # [[ NEW: Smart Context Injection ]]
            # If df is Pandas but the code looks like Polars, transparently convert it.
            if HAS_POLARS and isinstance(df, pd.DataFrame):
                # Heuristic: .select( is distinctively Polars (Pandas has select_dtypes, not select)
                # .with_columns( is also distinctively Polars
                if ".select(" in code or ".with_columns(" in code:
                    df = pl.from_pandas(df)
            
            local_env['df'] = df
        except Exception as e:
            return {"error": f"Data Load Error: {str(e)}"}

    # 4. Check for SQL (DuckDB)
    is_sql = False
    if HAS_DUCKDB and len(code) > 0:
        start_token = code.split()[0].upper() if code.split() else ""
        if start_token in ["SELECT", "WITH", "PRAGMA", "DESCRIBE", "SHOW", "EXPLAIN"]:
            is_sql = True

    # 5. Execute Code
    stdout_capture = io.StringIO()
    result_obj = None
    
    try:
        with contextlib.redirect_stdout(stdout_capture):
            if is_sql:
                try:
                    con = duckdb.connect()
                    # Register everything in local_env that is a dataframe
                    for k, v in local_env.items():
                        if hasattr(v, 'columns') or hasattr(v, 'collect'): 
                            try:
                                con.register(k, v)
                            except: pass
                            
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

    # 6. Process Result
    if HAS_POLARS and isinstance(result_obj, pl.LazyFrame):
        try:
            result_obj = result_obj.collect()
        except Exception as e:
            return {"error": f"Lazy Collection Failed: {str(e)}"}
            
    if HAS_DUCKDB and isinstance(result_obj, duckdb.DuckDBPyRelation):
         result_obj = result_obj.limit(50).df()

    output_text = ""
    try:
        # [[ NEW: Display Proxy ]]
        # Always prefer Polars formatting if available, even for Pandas objects
        if HAS_POLARS and isinstance(result_obj, pd.DataFrame):
            try:
                pl_view = pl.from_pandas(result_obj)
                if pl_view.height > 50:
                    output_text = str(pl_view.head(50))
                else:
                    output_text = str(pl_view)
            except Exception:
                output_text = result_obj.head(50).to_string()
                
        elif HAS_POLARS and isinstance(result_obj, pl.DataFrame):
            if result_obj.height > 50:
                output_text = str(result_obj.head(50))
            else:
                output_text = str(result_obj)
                
        elif isinstance(result_obj, pd.DataFrame):
            try:
                output_text = result_obj.head(50).to_markdown(index=False, tablefmt="psql") 
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
