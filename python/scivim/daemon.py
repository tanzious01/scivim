import sys
import json
import os
import pandas as pd
import numpy as np
import io
import contextlib
import platform

# --- Optional Feature Detection ---
try:
    import polars as pl
    HAS_POLARS = True
except ImportError:
    HAS_POLARS = False

try:
    import duckdb
    HAS_DUCKDB = True
except ImportError:
    HAS_DUCKDB = False

# -----------------------------------------------------------------------------
# GLOBAL STATE & CACHING
# -----------------------------------------------------------------------------
CACHE = {}
REL_GRAPH_CACHE = {"hash": None, "data": []}

def load_or_get_cached_df(file_path, lib, is_lazy):
    """
    Optimized loader: reads snapshots and caches results using mtime + size.
    Prevents reading stale data if the kernel updates a file rapidly.
    """
    global CACHE

    if not os.path.exists(file_path):
        if file_path in CACHE:
            del CACHE[file_path]
        raise FileNotFoundError(f"Snapshot not found: {file_path}")

    # Use both mtime and size for robust cache invalidation
    stat = os.stat(file_path)
    current_key = (stat.st_mtime, stat.st_size)
    
    if file_path in CACHE:
        cached = CACHE[file_path]
        if cached['key'] == current_key:
            return cached['df']

    # Load from disk (MISS)
    try:
        df_base = pd.read_feather(file_path) if file_path.endswith(".feather") else pd.read_pickle(file_path)
    except Exception as e:
        raise IOError(f"Failed to read snapshot ({os.path.basename(file_path)}): {str(e)}")

    if lib == "polars" and HAS_POLARS:
        df_final = pl.from_pandas(df_base).lazy() if is_lazy else pl.from_pandas(df_base)
    else:
        df_final = df_base

    CACHE[file_path] = {'df': df_final, 'key': current_key}
    return df_final

# -----------------------------------------------------------------------------
# VECTORIZED METADATA EXTRACTION
# -----------------------------------------------------------------------------

def _extract_meta_generic(df):
    """
    Calculates metadata in bulk using vectorized operations.
    Significantly faster than per-column loops for wide DataFrames.
    """
    meta = {}
    cols = df.columns.tolist()

    # Vectorized bulk counts
    null_counts = df.isna().sum().to_dict()
    unique_counts = df.nunique().to_dict()
    
    # Calculate all numeric statistics in a single pass
    numeric_df = df.select_dtypes(include=[np.number])
    stats_df = numeric_df.describe().to_dict() if not numeric_df.empty else {}

    for col in cols:
        col_meta = {
            "dtype": str(df[col].dtype),
            "null_count": int(null_counts.get(col, 0)),
            "unique_count": int(unique_counts.get(col, 0)),
            "sample_values": df[col].dropna().head(10).astype(str).tolist()
        }
        
        # Inject vectorized numeric metrics
        if col in stats_df:
            s = stats_df[col]
            col_meta.update({
                "min_val": float(s['min']), "max_val": float(s['max']),
                "mean_val": float(s['mean']), "std_val": float(s['std']),
                "median_val": float(s['50%']), "q1": float(s['25%']), "q3": float(s['75%'])
            })
        meta[col] = col_meta
        
    return cols, meta

# -----------------------------------------------------------------------------
# REQUEST HANDLERS
# -----------------------------------------------------------------------------
def _handle_relationships(data):
    """Analyze potential join relationships between DataFrames in the cache."""
    cache_dir = data.get("cache_dir", "")
    if not os.path.exists(cache_dir): return {"error": "Cache directory not found"}
    
    # Logic to find common columns (IDs) across all snapshots
    relationships = []
    df_map = {}
    with os.scandir(cache_dir) as it:
        for entry in it:
            if entry.name.endswith(('.feather', '.pkl')):
                name = entry.name.split('.')[0]
                try:
                    df = load_or_get_cached_df(entry.path, "pandas", False)
                    df_map[name] = set(df.columns)
                except: continue

    names = list(df_map.keys())
    for i, name1 in enumerate(names):
        for name2 in names[i+1:]:
            common = df_map[name1] & df_map[name2]
            for col in common:
                if 'id' in col.lower():
                    relationships.append({
                        "from_df": name1, "to_df": name2,
                        "from_col": col, "to_col": col, "type": "exact_match"
                    })
    return {"relationships": relationships}

def _handle_transform(data):
    """The core engine for Live Transform: handles Python and DuckDB SQL."""
    file_path = data.get("file_path", "")
    cache_dir = data.get("cache_dir", "")
    lib = data.get("lib", "pandas")
    code = data.get("code", "").strip()
    is_lazy = data.get("is_lazy", False)

    # 1. Setup Execution Environment
    local_env = {'pd': pd, 'np': np}
    if HAS_POLARS: local_env.update({'pl': pl, 'col': pl.col, 'lit': pl.lit})
        # 200 chars ensures even wide DFs don't wrap/truncate prematurely
    # 2. Workspace Loading: Inject ALL cached DataFrames into environment
    if os.path.exists(cache_dir):
        with os.scandir(cache_dir) as it:
            for entry in it:
                if entry.name.endswith(('.feather', '.pkl')):
                    name = entry.name.split('.')[0]
                    try:
                        local_env[name] = load_or_get_cached_df(entry.path, lib, is_lazy)
                    except: pass

    # 3. SQL vs Python Detection
    is_sql = any(code.upper().startswith(kw) for kw in ["SELECT", "WITH", "DESCRIBE"])

    try:
        if is_sql and HAS_DUCKDB:
            con = duckdb.connect()
            for k, v in local_env.items():
                if hasattr(v, 'columns') or hasattr(v, 'collect'):
                    try: con.register(k, v)
                    except: pass
            result_obj = con.sql(code).limit(50).df()
        else:
            # Execute Python (eval for expressions, exec for statements)
            try:
                result_obj = eval(code, {}, local_env)
            except SyntaxError:
                exec(code, {}, local_env)
                result_obj = local_env.get('df')
    except Exception as e:
        return {"error": str(e)}

    # 4. Serialize Table Output
    output_text = ""
    if result_obj is not None:
        try:
            # Check if it's already Polars
            if HAS_POLARS and isinstance(result_obj, (pl.DataFrame, pl.Series)):
                # Use Polars native formatting (aesthetic rounded boxes)
                output_text = str(result_obj.head(50))
            
            # If it's Pandas, wrap it in a Polars view for the aesthetic table
            elif isinstance(result_obj, (pd.DataFrame, pd.Series)):
                if HAS_POLARS:
                    # Convert to Polars JUST for formatting
                    # This gives you the Polars look without the overhead elsewhere
                    output_text = str(pl.from_pandas(pd.DataFrame(result_obj)).head(50))
                else:
                    # High-quality fallback for pure Pandas environments
                    output_text = result_obj.head(50).to_markdown(tablefmt="rounded_grid")
            else:
                output_text = str(result_obj)
        except Exception:
            output_text = str(result_obj)[:2000] # Safety fallback

    return {"text_table": output_text}

def _handle_preview(data):
    """Generates PNG plots for the Live Wizard."""
    try:
        import matplotlib
        matplotlib.use('Agg') # Headless
        import matplotlib.pyplot as plt
        import seaborn as sns
        plt.close('all')
    except ImportError: return {"error": "Plotting libs missing"}

    code = data.get("code", "")
    out_path = data.get("out_path", "")
    
    # Simple execution for preview (assumes context is handled or self-contained)
    try:
        exec(code.replace("plt.show()", ""), {}, {'plt': plt, 'sns': sns, 'pd': pd})
        plt.savefig(out_path, dpi=100, bbox_inches='tight')
        return {"status": "ok", "path": out_path}
    except Exception as e:
        return {"error": str(e)}
# -----------------------------------------------------------------------------
# CORE LOGIC & MAIN LOOP
# -----------------------------------------------------------------------------

def execute_request(data):
    rtype = data.get("type", "transform")
    try:
        if rtype == "metadata_all": return _handle_metadata_all(data)
        if rtype == "analyze_relationships": return _handle_relationships(data)
        if rtype == "transform": return _handle_transform(data)
        if rtype == "preview": return _handle_preview(data)
        if rtype == "shape": return _handle_shape(data)
        return {"error": f"Unknown request type: {rtype}"}
    except Exception as e:
        return {"error": f"Server Exception: {str(e)}"}

def main():
    for line in sys.stdin:
        if not line.strip(): continue
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
