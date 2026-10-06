"""Kunugi et al. (2013) Appendix A causal-filter reference, for experiments only.

Source: Kunugi et al., Zisin 65(3), 223-230 (2013), Appendix A, equations
A1-A16; DOI: https://doi.org/10.4294/zisin.65.223. This is the 2012
six-biquad approximating filter, not a claim about the current NIED GIF feed.

The paper does not specify the hidden filter state before an arbitrary CSV
excerpt. The API therefore exposes two assumptions: all-zero state, and a
constant prehistory equal to the first input sample (SciPy ``sosfilt_zi``).
Neither recovers the true continuous instrument history. For a continuous
record split into chunks, pass each returned state to the next call.

Appendix A's printed A12 beta0/beta2 contain ``omega_a2`` in the J-STAGE text
rendering, while A3/A4 and the A12 parameter assignment give the same fa3 to
both first-order sections. The A12 coefficients below use omega_a3 for those
terms, derived by multiplying the A9 first-order coefficients for A3 and A4
using A10. Appendix A3 assigns fa2=fa3=f1, so the printed index difference
does not change numerical coefficients in this prescribed cascade.
"""

from __future__ import annotations

import math

import numpy as np
from scipy.signal import sosfilt, sosfilt_zi


PARAMETERS = {
    "f0_hz": 0.45,
    "f1_hz": 7.0,
    "f2_hz": 0.5,
    "f3_hz": 12.0,
    "f4_hz": 20.0,
    "f5_hz": 30.0,
    "h2a": 1.0,
    "h2b": 0.75,
    "h3": 0.9,
    "h4": 0.6,
    "h5": 0.6,
    "gain": 1.262,
}


def _sos_row(b: tuple[float, float, float],
             a: tuple[float, float, float]) -> tuple[float, ...]:
    """Normalize a paper-form [b0,b1,b2]/[a0,a1,a2] biquad for SciPy."""
    a0, a1, a2 = a
    return (b[0] / a0, b[1] / a0, b[2] / a0,
            1.0, a1 / a0, a2 / a0)


def _first_order(frequency_hz: float, numerator_a: float,
                 denominator_b: float, dt: float
                 ) -> tuple[tuple[float, float], tuple[float, float]]:
    """Appendix A9 coefficients (beta0,beta1), (alpha0,alpha1)."""
    omega = 2.0 * math.pi * frequency_hz
    return ((omega * numerator_a + 2.0 / dt,
             omega * numerator_a - 2.0 / dt),
            (omega + 2.0 * denominator_b / dt,
             omega - 2.0 * denominator_b / dt))


def _cascade_first_order(
        first: tuple[tuple[float, float], tuple[float, float]],
        second: tuple[tuple[float, float], tuple[float, float]]
        ) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    """Appendix A10 convolution of two first-order numerator/denominator pairs."""
    (b00, b01), (a00, a01) = first
    (b10, b11), (a10, a11) = second
    return ((b00 * b10, b00 * b11 + b01 * b10, b01 * b11),
            (a00 * a10, a00 * a11 + a01 * a10, a01 * a11))


def sos_coefficients(sampling_hz: float) -> np.ndarray:
    """Return six causal SOS rows in Appendix A3's prescribed cascade order.

    Coefficient provenance by row:
      0: A11, combining A1 and A2 (fa1=f0, fa2=f1).
      1: A12, combining A3 and A4 (both fa3=f1), derived with A9/A10.
      2: A13 (A5), f2 with numerator damping h2a and denominator h2b.
      3-5: A14 (A6-A8), (f3,h3), (f4,h4), (f5,h5).
    A15 defines the causal recurrence; A16 applies the final gain.
    """
    fs = float(sampling_hz)
    if not math.isfinite(fs) or fs <= 0:
        raise ValueError("sampling_hz must be finite and positive")
    dt = 1.0 / fs
    inv_dt = 1.0 / dt
    inv_dt2 = inv_dt * inv_dt
    w0 = 2.0 * math.pi * PARAMETERS["f0_hz"]
    w1 = 2.0 * math.pi * PARAMETERS["f1_hz"]

    # A11: equations A1+A2 combined through A9+A10.
    a0 = 8.0 * inv_dt2 + (4.0 * w0 + 2.0 * w1) * inv_dt + w0 * w1
    a1 = 2.0 * w0 * w1 - 16.0 * inv_dt2
    a2 = 8.0 * inv_dt2 - (4.0 * w0 + 2.0 * w1) * inv_dt + w0 * w1
    b0 = 4.0 * inv_dt2 + 2.0 * w1 * inv_dt
    b1 = -8.0 * inv_dt2
    b2 = 4.0 * inv_dt2 - 2.0 * w1 * inv_dt
    sections = [_sos_row((b0, b1, b2), (a0, a1, a2))]

    # A12: combine A3=(a=4,b=8) and A4=(a=0.25,b=0.5), both fa3=f1.
    # A9+A10 keep their common frequency explicit; fa2=fa3=f1 in Appendix A3.
    a3 = _first_order(PARAMETERS["f1_hz"], 4.0, 8.0, dt)
    a4 = _first_order(PARAMETERS["f1_hz"], 0.25, 0.5, dt)
    b, a = _cascade_first_order(a3, a4)
    sections.append(_sos_row(b, a))

    # A13: A5 compensation biquad, h2a in numerator and h2b in denominator.
    w = 2.0 * math.pi * PARAMETERS["f2_hz"]
    h_num, h_den = PARAMETERS["h2a"], PARAMETERS["h2b"]
    a0 = 12.0 * inv_dt2 + 12.0 * h_den * w * inv_dt + w * w
    a1 = 10.0 * w * w - 24.0 * inv_dt2
    a2 = 12.0 * inv_dt2 - 12.0 * h_den * w * inv_dt + w * w
    b0 = 12.0 * inv_dt2 + 12.0 * h_num * w * inv_dt + w * w
    b1 = 10.0 * w * w - 24.0 * inv_dt2
    b2 = 12.0 * inv_dt2 - 12.0 * h_num * w * inv_dt + w * w
    sections.append(_sos_row((b0, b1, b2), (a0, a1, a2)))

    # A14: three second-order low-pass sections A6-A8.
    for frequency, damping in (
        (PARAMETERS["f3_hz"], PARAMETERS["h3"]),
        (PARAMETERS["f4_hz"], PARAMETERS["h4"]),
        (PARAMETERS["f5_hz"], PARAMETERS["h5"]),
    ):
        w = 2.0 * math.pi * frequency
        a0 = 12.0 * inv_dt2 + 12.0 * damping * w * inv_dt + w * w
        a1 = 10.0 * w * w - 24.0 * inv_dt2
        a2 = 12.0 * inv_dt2 - 12.0 * damping * w * inv_dt + w * w
        sections.append(_sos_row((w * w, 10.0 * w * w, w * w),
                                 (a0, a1, a2)))

    sos = np.asarray(sections, dtype=np.float64)
    if sos.shape != (6, 6) or not np.isfinite(sos).all():
        raise ArithmeticError("invalid Appendix A SOS coefficients")
    return sos


def filter_samples(samples: np.ndarray, sampling_hz: float,
                   zi: np.ndarray | None = None,
                   initialization: str = "zero") -> tuple[np.ndarray, np.ndarray]:
    """Causally filter Nx3 acceleration samples and return output plus state.

    No offset correction, resampling, padding, or future samples are used.
    With no ``zi``, ``initialization`` must be ``"zero"`` or
    ``"steady_first_sample"``. The latter uses ``sosfilt_zi(sos)`` scaled by
    the first original sample independently on each component; it does not
    inspect the rest of the record. To continue a stream/chunk, pass returned
    ``zi`` and leave initialization at its default. The final A16 gain is
    applied after the six-section cascade.
    """
    values = np.asarray(samples, dtype=np.float64)
    if values.ndim != 2 or values.shape[1] != 3 or values.shape[0] == 0:
        raise ValueError("samples must be a non-empty Nx3 array")
    if not np.isfinite(values).all():
        raise ValueError("samples must be finite")
    sos = sos_coefficients(sampling_hz)
    if zi is None:
        if initialization == "zero":
            initial = np.zeros((len(sos), 2, values.shape[1]), dtype=np.float64)
        elif initialization == "steady_first_sample":
            initial = (sosfilt_zi(sos)[:, :, None]
                       * values[0][None, None, :])
        else:
            raise ValueError("initialization must be 'zero' or 'steady_first_sample'")
    else:
        if initialization != "zero":
            raise ValueError("choose initialization only on the first chunk")
        initial = np.asarray(zi, dtype=np.float64)
        if initial.shape != (len(sos), 2, values.shape[1]):
            raise ValueError("zi must have shape (6, 2, 3)")
        if not np.isfinite(initial).all():
            raise ValueError("zi must be finite")
    filtered, final_state = sosfilt(sos, values, axis=0, zi=initial)
    filtered *= PARAMETERS["gain"]
    return filtered, final_state


def trailing_intensity_report(filtered_samples: np.ndarray, sampling_hz: float,
                              window_seconds: int = 60,
                              update_seconds: int = 1,
                              initialization: str = "unspecified") -> dict[str, object]:
    """Report full trailing-window 0.3-second intensity at fixed right edges.

    ``filtered_samples`` must be the causal three-component output of
    :func:`filter_samples`. At each whole ``update_seconds`` endpoint, combine
    the components by vector norm and select the ``ceil(0.3 * fs)``-th largest
    sample from the complete trailing ``window_seconds``. No shorter startup
    windows or synthetic history are used. The first endpoint with a complete
    window is exactly ``window_seconds`` after sample zero.

    Row ``endSampleExclusive`` identifies the exclusive right edge, suitable
    for mapping to ``sampleStart + endSampleExclusive / fs``. The returned
    ``continuousIntensity`` is ``2*log10(amplitudeGal)+0.94`` for positive
    amplitude. This is a retrospective threshold over causal-filter output,
    not by itself a certified JMA/NIED realtime implementation.
    """
    fs = float(sampling_hz)
    if not math.isfinite(fs) or fs <= 0:
        raise ValueError("sampling_hz must be finite and positive")
    if not isinstance(window_seconds, int) or window_seconds <= 0:
        raise ValueError("window_seconds must be a positive integer")
    if not isinstance(update_seconds, int) or update_seconds <= 0:
        raise ValueError("update_seconds must be a positive integer")
    if initialization not in ("zero", "steady_first_sample", "unspecified"):
        raise ValueError("invalid initialization label")
    values = np.asarray(filtered_samples, dtype=np.float64)
    if values.ndim != 2 or values.shape[1] != 3 or values.shape[0] == 0:
        raise ValueError("filtered_samples must be a non-empty Nx3 array")
    if not np.isfinite(values).all():
        raise ValueError("filtered_samples must be finite")

    window_exact = window_seconds * fs
    update_exact = update_seconds * fs
    window_n, update_n = round(window_exact), round(update_exact)
    if (abs(window_exact - window_n) > 1e-9 or
            abs(update_exact - update_n) > 1e-9):
        raise ValueError("window and update durations must contain whole samples")
    threshold_n = math.ceil(0.3 * fs)
    if window_n <= 0 or update_n <= 0 or threshold_n > window_n:
        raise ValueError("window must contain the 0.3-second threshold duration")
    vector = np.linalg.norm(values, axis=1)
    rows = []
    for end in range(update_n, len(vector) + 1, update_n):
        if end < window_n:
            rows.append({"endSampleExclusive": end, "hasFullHistory": False,
                         "amplitudeGal": None, "continuousIntensity": None})
            continue
        trailing = vector[end - window_n:end]
        amplitude = float(np.partition(trailing, window_n - threshold_n)[window_n - threshold_n])
        intensity = 2.0 * math.log10(amplitude) + 0.94 if amplitude > 0 else None
        rows.append({"endSampleExclusive": end, "hasFullHistory": True,
                     "amplitudeGal": amplitude, "continuousIntensity": intensity})
    return {
        "filterReference": "Kunugi et al. (2013), Appendix A causal SOS; initialization is an explicit assumption",
        "initialization": initialization,
        "windowSeconds": window_seconds,
        "updateSeconds": update_seconds,
        "samplingHz": fs,
        "windowSamples": window_n,
        "thresholdDurationSeconds": 0.3,
        "thresholdSamples": threshold_n,
        "historyPolicy": "Require full window; no padding or shortened startup window",
        "edgeLabel": "exclusive right endpoint",
        "rows": rows,
    }


def compare_initializations(samples: np.ndarray, sampling_hz: float,
                            window_seconds: int = 60,
                            update_seconds: int = 1) -> dict[str, object]:
    """Return both permitted starts and their full-window impact, without ranking.

    Intended for callers with unmodified ``parse_record(...)[1]`` samples.
    The impact rows compare steady-first-sample minus zero-state outputs at
    identical exclusive right endpoints; only pairs with complete windows are
    assigned numeric deltas.
    """
    values = np.asarray(samples, dtype=np.float64)
    zero_filtered, _ = filter_samples(values, sampling_hz, initialization="zero")
    steady_filtered, _ = filter_samples(
        values, sampling_hz, initialization="steady_first_sample")
    zero = trailing_intensity_report(zero_filtered, sampling_hz,
                                     window_seconds, update_seconds, "zero")
    steady = trailing_intensity_report(steady_filtered, sampling_hz,
                                       window_seconds, update_seconds,
                                       "steady_first_sample")
    impact_rows = []
    amplitude_deltas, intensity_deltas = [], []
    for zrow, srow in zip(zero["rows"], steady["rows"], strict=True):
        if zrow["hasFullHistory"] and srow["hasFullHistory"]:
            amplitude_delta = srow["amplitudeGal"] - zrow["amplitudeGal"]
            intensity_delta = (None if srow["continuousIntensity"] is None or
                               zrow["continuousIntensity"] is None else
                               srow["continuousIntensity"] - zrow["continuousIntensity"])
            amplitude_deltas.append(amplitude_delta)
            if intensity_delta is not None:
                intensity_deltas.append(intensity_delta)
        else:
            amplitude_delta = intensity_delta = None
        impact_rows.append({
            "endSampleExclusive": zrow["endSampleExclusive"],
            "hasFullHistory": zrow["hasFullHistory"],
            "steadyMinusZeroAmplitudeGal": amplitude_delta,
            "steadyMinusZeroContinuousIntensity": intensity_delta,
        })

    mean = lambda xs: float(np.mean(xs)) if xs else None
    return {
        "inputTreatment": "Use original samples verbatim; no declared-offset subtraction",
        "interpretationLimit": "Filter-initialization sensitivity only; no GIF pixel/station identity inference",
        "initializations": {"zero": zero, "steady_first_sample": steady},
        "impact": {
            "comparison": "steady_first_sample minus zero",
            "pairedFullHistoryUpdates": len(amplitude_deltas),
            "missingHistoryUpdates": sum(not row["hasFullHistory"] for row in impact_rows),
            "meanSignedAmplitudeDeltaGal": mean(amplitude_deltas),
            "maxAbsAmplitudeDeltaGal": (float(np.max(np.abs(amplitude_deltas)))
                                         if amplitude_deltas else None),
            "meanSignedIntensityDelta": mean(intensity_deltas),
            "maxAbsIntensityDelta": (float(np.max(np.abs(intensity_deltas)))
                                      if intensity_deltas else None),
            "rows": impact_rows,
        },
    }
