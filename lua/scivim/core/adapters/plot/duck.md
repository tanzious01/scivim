



```{python}
import pandas as pd
import numpy as np

# Create a sample DataFrame
df_sales = pd.DataFrame({
    'city': ['New York', 'London', 'New York', 'London', 'Paris', 'Paris'],
    'item': ['Apple', 'Apple', 'Orange', 'Banana', 'Apple', 'Banana'],
    'price': [1.50, 1.20, 0.80, 0.50, 1.60, 0.55],
    'qty':   [10, 20, 15, 30, 12, 40]

})

print("Data Loaded")
```









```{python}
import duckdb
df_sales_sql = duckdb.sql("""SELECT * FROM df_sales WHERE qty >15""").df()
print(df_sales_sql)


```

