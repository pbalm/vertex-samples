from tensorflow.keras.models import Model
from tensorflow.keras.callbacks import ReduceLROnPlateau
from tensorflow.keras import layers, losses, optimizers

from tensorflow.python.framework import dtypes
import tensorflow as tf

from tensorflow_io.bigquery import BigQueryClient


def features_and_labels(features):
    target = features.pop('s1')
    #enodeb = features.pop('enodeb')
    return features, target


def read_bigquery():
    batch_size=512
    tensorflow_io_bigquery_client = BigQueryClient()
    read_session = tensorflow_io_bigquery_client.read_session(
          "projects/" + PROJECT_ID,
           PROJECT_ID, TABLE_ID, DATASET_ID, COL_NAMES, COL_TYPES,
          requested_streams=2)

    dataset = read_session.parallel_read_rows()
    transformed_ds = dataset.map(features_and_labels).shuffle(batch_size*10).batch(batch_size)
    return transformed_ds

n_t_cols = 4

COL_NAMES = [f't_{i}' for i in range(1, n_t_cols + 1)] + ['s1', 'enodeb']
COL_TYPES = [dtypes.float64] * n_t_cols + [dtypes.float64, dtypes.string]

print(f'COL_NAMES {COL_NAMES}')
print(f'COL_TYPES {COL_TYPES}')

PROJECT_ID='pbalm-orange'
DATASET_ID='test' # test dataset
TABLE_ID  = 'kpi_s1_lags'

window_size = 4
batch_size = 16

training_ds = read_bigquery()

str_lookup_layer = layers.StringLookup(name='string_lookup')
str_lookup_layer.adapt(['1'])

def get_model(str_layer):
    # generate one input layer per feature column
    inputs = {f't_{i}': layers.Input(name=f't_{i}', shape=(1,), dtype='float64') for i in range(1, window_size + 1)}
    inputs['enodeb'] = layers.Input(shape=[], dtype=tf.string, name='enodeb')

    sorted_keys = list(inputs.keys())
    sorted_keys.sort()
    input_list = [inputs[k] for k in sorted_keys]

    d = layers.concatenate([inputs[k] for k in inputs if k.startswith('t')], name='concat')
    x = layers.Dense(4, activation="relu", name='autoenc_1')(d)
    x = layers.Dense(2, activation="relu", name='autoenc_2')(x)
    x = layers.Dense(4, activation="relu", name='autoenc_3')(x)

    xx = str_layer(inputs['enodeb'])
    xx = layers.Embedding(str_layer.vocabulary_size(), 10, name='embedding')(xx)
    xx = layers.Flatten(name='flatten')(xx)

    x = layers.Concatenate(name='concat_w_embed')([x, xx])
    x = layers.Dense(window_size + 1, activation="relu", name='output')(x)

    model = Model(input_list, x)
    return model


autoencoder = get_model(str_lookup_layer)
optimizer = optimizers.Adam(learning_rate=1e-3)
autoencoder.compile(
    loss="mse",
              optimizer=optimizer,
              metrics=["mae"])

print(f'Training dataset: {training_ds}')

history = autoencoder.fit(training_ds,
                        epochs=3,
                        batch_size=batch_size)
