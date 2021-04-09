import os
import sys
import keras
import coremltools as ct
import tensorflow as tf

from Logger import Logger

# Variables

tmp_folder = 'docs'
if not os.path.isdir(tmp_folder): os.mkdir(tmp_folder)

batch_size = 16
image_size = 299

current_it = 0
while os.path.isdir(f"{tmp_folder}/v{current_it}"): current_it += 1

current_tmp = f"{tmp_folder}/v{current_it}"
os.mkdir(current_tmp)

sys.stdout = Logger(current_tmp + "/log.txt")

# Generators

data_gen = keras.preprocessing.image.ImageDataGenerator(
    rescale=1./255,
    rotation_range=180,
    shear_range=0.2,
    zoom_range=0.2,
    width_shift_range=0.2,
    height_shift_range=0.2,
    horizontal_flip=True,
    validation_split=0.2
)

train_gen = data_gen.flow_from_directory(
    'Images',
    target_size=(image_size, image_size),
    batch_size=batch_size,
    class_mode='binary',
    subset='training'
)

val_gen = data_gen.flow_from_directory(
    'Images',
    target_size=(image_size, image_size),
    batch_size=batch_size,
    class_mode='binary',
    subset='validation'
)

# Create Model

base = keras.applications.Xception(input_shape=(image_size, image_size, 3), weights='imagenet', include_top=False)
base.summary()

pool_layer = keras.layers.GlobalAveragePooling2D()
predict_layer = keras.layers.Dense(train_gen.num_classes, activation='softmax')

model = keras.Sequential([base, pool_layer, predict_layer])
model.summary()

# Compile Model

optimizer = keras.optimizers.Nadam(lr=2e-5)
loss = keras.losses.sparse_categorical_crossentropy

model.compile(optimizer=optimizer, loss=loss, metrics=['accuracy'])

# Train Model

model.fit_generator(
    train_gen,
    epochs=20,
    steps_per_epoch=train_gen.n // batch_size,
    validation_data=val_gen,
    validation_steps=val_gen.n // batch_size
)

model.save(current_tmp + '/CoinClassifier.h5')

# CoreML

labels = list((k) for k,v in train_gen.class_indices.items())
labels.sort()

coreml_model = ct.converters.keras.convert(model,
    input_names=['image'],
    output_names=['output'],
    image_input_names="image",
    class_labels=labels,
    image_scale=1/255.0,
    is_bgr=False
)

coreml_model.save(current_tmp + 'CoinClassifier.mlmodel')

# TensorFlow Lite

converter = tf.lite.TFLiteConverter.from_keras_model_file('drive/My Drive/Coins/CoinClassifier.h5')
tflite = converter.convert()

with open(current_tmp + 'CoinClassifier.tflite', 'wb') as f:
    f.write(tflite)