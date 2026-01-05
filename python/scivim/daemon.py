# /home/tanzious/scivim/python/scivim/daemon.py
import sys
import json
import os
import pandas as pd
import numpy as np
import io
import contextlib
import sqlglot

try:
    import polars as pl
    HAS_POLARS = True
    # FORCE BACKEND TO RENDER ALL COLUMNS
    pl.Config.set_tbl_cols(-1)
    pl.Config.set_tbl_width_chars(5000) # Increased for massive displays
    pl.Config.set_fmt_str_lengths(15) 
except ImportError:
    HAS_POLARS = False

# Pandas Global Formatting for high-fidelity UI
pd.set_option('display.max_columns', None)
pd.set_option('display.width', 5000)
pd.set_option('display.max_colwidth', 15)

CACHE = {}

def load_or_get_cached_df(file_path, lib, is_lazy):
    global CACHE
    if not os.path.exists(file_path):
        if file_path in CACHE: del CACHE[file_path]
        return None
    stat = os.stat(file_path)
    current_key = (stat.st_mtime, stat.st_size)
    if file_path in CACHE and CACHE[file_path]['key'] == current_key:
        return CACHE[file_path]['df']
    try:
        df_base = pd.read_feather(file_path) if file_path.endswith(".feather") else pd.read_pickle(file_path)
    except Exception as e: raise IOError(f"Read Error: {str(e)}")
    if lib == "polars" and HAS_POLARS:
        df_final = pl.from_pandas(df_base).lazy() if is_lazy else pl.from_pandas(df_base)
    else: df_final = df_base
    CACHE[file_path] = {'df': df_final, 'key': current_key}
    return df_final

def _handle_transform(data):
    cache_dir, lib, code, is_lazy = data.get("cache_dir", ""), data.get("lib", "pandas"), data.get("code", "").strip(), data.get("is_lazy", False)
    local_env = {'pd': pd, 'np': np}
    if HAS_POLARS: local_env.update({'pl': pl, 'col': pl.col, 'lit': pl.lit, 'when': pl.when})
    if os.path.exists(cache_dir):
        for entry in os.scandir(cache_dir):
            if entry.name.endswith(('.feather', '.pkl')):
                name = entry.name.split('.')[0]
                try:
                    df_obj = load_or_get_cached_df(entry.path, lib, is_lazy)
                    if df_obj is not None: local_env[name] = df_obj
                except: pass
    is_sql = any(code.upper().startswith(kw) for kw in ["SELECT", "WITH", "DESCRIBE", "SHOW"])
    semantic_code = None
    try:
        if is_sql and HAS_POLARS:
            try: semantic_code = sqlglot.transpile(code, read=None, write="polars")[0]
            except: semantic_code = "# Semantic transpilation unavailable"
            sql_ctx = pl.SQLContext()
            for var_name, obj in local_env.items():
                if isinstance(obj, (pl.DataFrame, pl.LazyFrame, pd.DataFrame)):
                    ldf = obj.lazy() if hasattr(obj, 'lazy') else pl.from_pandas(obj).lazy()
                    sql_ctx.register(var_name, ldf)
            result_obj = sql_ctx.execute(code).collect()
        else:
            try: result_obj = eval(code, {}, local_env)
            except SyntaxError:
                exec(code, {}, local_env)
                result_obj = local_env.get('df')
    except Exception as e: return {"error": f"Execution Error: {str(e)}"}
    output_text = ""
    if result_obj is not None:
        try:
            # Aesthetic Fitting Algorithm: Scale cell width to column count
            col_count = len(result_obj.columns) if hasattr(result_obj, "columns") else 1
            dynamic_str_len = max(8, min(30, 120 // max(1, col_count)))
            if HAS_POLARS:
                pl.Config.set_fmt_str_lengths(dynamic_str_len)
                output_text = str(result_obj.head(50))
            elif isinstance(result_obj, (pd.DataFrame, pd.Series)):
                # Aesthetic optimization: Use Polars styler for Pandas
                output_text = str(pl.from_pandas(pd.DataFrame(result_obj)).head(50))
            else: output_text = str(result_obj)
        except: output_text = str(result_obj)[:10000]
    return {"text_table": output_text, "semantic_code": semantic_code}

def _handle_metadata_all(data):
    cache_dir, filter_names = data.get("cache_dir", ""), set(data.get("names", []))
    if not os.path.exists(cache_dir): return {"error": "Cache missing"}
    results = {}
    for filename in os.listdir(cache_dir):
        if not (filename.endswith('.feather') or filename.endswith('.pkl')): continue
        df_name = filename.split('.')[0]
        if filter_names and df_name not in filter_names: continue
        try:
            df = load_or_get_cached_df(os.path.join(cache_dir, filename), "pandas", False)
            if df is not None:
                results[df_name] = {"name": df_name, "shape": list(df.shape), "columns": df.columns.tolist(), "head": str(df.head(5))}
        except: continue
    return {"dataframes": results}

def _handle_preview(data):
    try:
        import matplotlib.pyplot as plt
        import seaborn as sns
        plt.switch_backend('Agg')
    except ImportError: return {"error": "Plotting libs missing"}
    code, out_path = data.get("code", ""), data.get("out_path", "")
    try:
        plt.close('all')
        exec(code.replace("plt.show()", ""), {}, {'plt': plt, 'sns': sns, 'pd': pd, 'np': np})
        plt.savefig(out_path, dpi=100, bbox_inches='tight')
        return {"status": "ok"}
    except Exception as e: return {"error": str(e)}

def main():
    for line in sys.stdin:
        if not line.strip(): continue
        try:
            req = json.loads(line)
            rtype = req.get("type", "transform")
            if rtype == "metadata_all": resp = _handle_metadata_all(req)
            elif rtype == "transform": resp = _handle_transform(req)
            elif rtype == "preview": resp = _handle_preview(req)
            else: resp = {"error": f"Unknown: {rtype}"}
        except Exception as e: resp = {"error": str(e)}
        sys.stdout.write(json.dumps(resp) + "\n")
        sys.stdout.flush()

if __name__ == "__main__":
    main()
