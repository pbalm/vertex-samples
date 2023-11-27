import pandas as pd

def get_day_of_week_feature(df: pd.DataFrame):
   return df.start_time.dt.dayofweek.apply(str)
