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
