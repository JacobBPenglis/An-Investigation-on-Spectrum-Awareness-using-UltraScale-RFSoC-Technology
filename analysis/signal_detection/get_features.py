import numpy as np
import matplotlib.pyplot as plt
import scipy.stats as st


def get_td_features(iq):
    mag = np.abs(iq)
    peak = np.max(mag)
    rms = np.sqrt(np.mean(mag**2))

    crest_factor = peak/rms
    kurtosis = st.kurtosis(mag)
    skewness = st.skew(mag)

    return {
        "crest_factor": crest_factor,
        "kurtosis": kurtosis,
        "skewness": skewness
    }