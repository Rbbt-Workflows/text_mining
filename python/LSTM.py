#!/usr/bin/env python
# coding: utf-8

import os
import keras
import pickle
import numpy as np
from numpy import array
from bs4 import BeautifulSoup
import matplotlib.pyplot as plt
plt.switch_backend('agg')
os.environ['KERAS_BACKEND']='tensorflow'
from keras.models import Model
from keras import backend as K
from keras.engine.topology import Layer
from keras.optimizers import Adam, RMSprop
from keras.utils.vis_utils import plot_model
from keras.preprocessing.text import Tokenizer
from keras.preprocessing.sequence import pad_sequences
from keras.callbacks import EarlyStopping, ModelCheckpoint
from keras import initializers, regularizers, constraints
from sklearn.preprocessing import OneHotEncoder, LabelEncoder
from imblearn.over_sampling import ADASYN, SMOTE, RandomOverSampler
from sklearn.metrics import f1_score, precision_score, recall_score
from keras.layers import Dense, Input, Flatten, Embedding, Dropout, LSTM, Bidirectional

class Attention(Layer):

    ''' Attention layer '''

    def get_config(self):
        config = {
            'step_dim': self.step_dim,
            'W_regularizer': self.W_regularizer,
            'b_regularizer': self.b_regularizer,
            'W_constraint': self.W_constraint,
            'b_constraint': self.b_constraint,
            'bias': self.bias}

        return config

    def __init__(self, step_dim,
                 W_regularizer=None, b_regularizer=None,
                 W_constraint=None, b_constraint=None,
                 bias=True, **kwargs):
        self.supports_masking = True
        self.init = initializers.get('glorot_uniform')

        self.W_regularizer = regularizers.get(W_regularizer)
        self.b_regularizer = regularizers.get(b_regularizer)

        self.W_constraint = constraints.get(W_constraint)
        self.b_constraint = constraints.get(b_constraint)

        self.bias = bias
        self.step_dim = step_dim
        self.features_dim = 0
        super(Attention, self).__init__(**kwargs)

    def build(self, input_shape):
        assert len(input_shape) == 3

        self.W = self.add_weight((input_shape[-1],),
                                 initializer=self.init,
                                 name='{}_W'.format(self.name),
                                 regularizer=self.W_regularizer,
                                 constraint=self.W_constraint)
        self.features_dim = input_shape[-1]

        if self.bias:
            self.b = self.add_weight((input_shape[1],),
                                     initializer='zero',
                                     name='{}_b'.format(self.name),
                                     regularizer=self.b_regularizer,
                                     constraint=self.b_constraint)
        else:
            self.b = None

        self.built = True

    def compute_mask(self, input, input_mask=None):
        return None

    def call(self, x, mask=None):
        features_dim = self.features_dim
        step_dim = self.step_dim

        eij = K.reshape(K.dot(K.reshape(x, (-1, features_dim)),
                              K.reshape(self.W, (features_dim, 1))), (-1, step_dim))

        if self.bias:
            eij += self.b

        eij = K.tanh(eij)

        a = K.exp(eij)

        if mask is not None:
            a *= K.cast(mask, K.floatx())

        a /= K.cast(K.sum(a, axis=1, keepdims=True) + K.epsilon(), K.floatx())

        a = K.expand_dims(a)
        weighted_input = x * a
        return K.sum(weighted_input, axis=1)

    def compute_output_shape(self, input_shape):
        return input_shape[0], self.features_dim

def RNN_prepare_X(X):
    MAX_NB_WORDS = 500
    MAX_SEQUENCE_LENGTH = 100

    texts = []

    for idx in X:
        text = BeautifulSoup(idx, 'html.parser')
        texts.append(str(text.get_text().encode()))

    tokenizer = Tokenizer(num_words=MAX_NB_WORDS)
    tokenizer.fit_on_texts(texts)
    sequences = tokenizer.texts_to_sequences(texts)
    data = pad_sequences(sequences, maxlen=MAX_SEQUENCE_LENGTH)

    return data, tokenizer

def train_LTSM(X, labels, embeddings_index, model_dir):
    ''' Recurrent Neural Networks with Attention enabled '''

    # Hyper-parameters of the model

    MAX_SEQUENCE_LENGTH = 100
    #MAX_NB_WORDS = 500
    #LSTM_DIM = 100
    LSTM_DIM = 100

    # Categorize target labels !

    n_labels = len(set(labels))

    values = array(labels)
    label_encoder = LabelEncoder()
    integer_encoded = label_encoder.fit_transform(values)
    onehot_encoder = OneHotEncoder(sparse=False, categories='auto')
    integer_encoded = integer_encoded.reshape(len(integer_encoded), 1)
    labels = onehot_encoder.fit_transform(integer_encoded)

    data, tokenizer = RNN_prepare_X(X)
    word_index = tokenizer.word_index

    embedding_matrix = np.random.random((len(word_index) + 1, MAX_SEQUENCE_LENGTH))
    for word, i in word_index.items():
        embedding_vector = embeddings_index.get(word)
        if embedding_vector is not None:
            # words not found in embedding index will be all-zeros.
            embedding_matrix[i] = embedding_vector



    embedding_layer = Embedding(len(word_index) + 1,
                                MAX_SEQUENCE_LENGTH,
                                weights=[embedding_matrix],
                                input_length=MAX_SEQUENCE_LENGTH,
                                trainable=True)

    sequence_input = Input(shape=(MAX_SEQUENCE_LENGTH,), dtype='int32')
    embedded_sequences = embedding_layer(sequence_input)

    out = Bidirectional(LSTM(LSTM_DIM, return_sequences=True, dropout=0.30, recurrent_dropout=0.30))(embedded_sequences)
    out = Attention(MAX_SEQUENCE_LENGTH)(out)
    out = Dense(LSTM_DIM, activation="relu")(out)

    out = Dropout(0.30)(out)
    out = Dense(n_labels, activation="softmax")(out)
    model = Model(sequence_input, out)

    if not os.path.isfile(model_dir + '/model.png'):
        plot_model(model, to_file=model_dir +'/model.png', show_shapes=True, show_layer_names=True)

    x_train = data
    y_train = labels

    ada = RandomOverSampler(random_state=42, sampling_strategy='minority')
    x_train_resampled, y_train_resampled = ada.fit_sample(x_train, y_train)
    y_train_resampled = onehot_encoder.fit_transform(y_train_resampled)

    # Model optimizer and metrics

    opt = Adam(lr=0.001, beta_1=0.9, beta_2=0.999, epsilon=None, decay=0.0, amsgrad=False)

    model.compile(loss='categorical_crossentropy', optimizer=opt, metrics=['accuracy'])

    # Model parameters

    model_filepath_weights = model_dir + '/model.h5'
    model_filepath_json = model_dir + '/model.json'
    tokenizer_pickle = model_dir + '/tokenizer.pckl'
    pickle.dump(tokenizer, open(tokenizer_pickle, 'wb'))


    # serialize model to JSON
    model_json = model.to_json()
    with open(model_filepath_json, "w") as json_file:
        json_file.write(model_json)

    early_stopping = EarlyStopping(monitor = 'val_loss', patience = 5, verbose = 2, mode= 'min')

    checkpoint = ModelCheckpoint(model_filepath_weights, monitor='val_acc', verbose = 2, save_best_only=True, mode='max')
    callbacks_list = [early_stopping, checkpoint]

    #history = model.fit(x_train_resampled, y_train_resampled, validation_data=(x_train_resampled, y_train_resampled), epochs=100, callbacks=callbacks_list, verbose=2)
    history = model.fit(x_train_resampled, y_train_resampled, validation_split=0.2, epochs=100, callbacks=callbacks_list, verbose=2)

    # serialize weights to HDF5
    keras.models.save_model(model, model_filepath_weights)

def predict_LSTM(X, model_dir):
    MAX_SEQUENCE_LENGTH = 100

    model_filepath_weights = model_dir + '/model.h5'
    model_filepath_json = model_dir + '/model.json'
    tokenizer_pickle = model_dir + '/tokenizer.pckl'

    tokenizer = pickle.load(open(tokenizer_pickle, 'rb'))

    model = keras.models.model_from_json(open(model_filepath_json, 'rb').read(), custom_objects={'Attention': Attention(MAX_SEQUENCE_LENGTH)})
    # load weights into new model
    model.load_weights(model_filepath_weights)

    sequences = tokenizer.texts_to_sequences(X)
    data = pad_sequences(sequences, maxlen=MAX_SEQUENCE_LENGTH)

    predictions = model.predict(data)
    predictions = predictions.argmax(axis=-1)

    return predictions.tolist()
