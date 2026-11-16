"""Isolation Forest model over entity-hour behaviour samples.

Unsupervised on purpose: there are no labelled attacks to learn from, and the
question asked of the model is "how unusual is this hour of activity compared
with what this environment normally looks like", not "which known attack is
this" (the rule-based detectors already answer that).

The raw Isolation Forest score is not a risk score. It is calibrated against
the training data: a sample's percentile is the share of baseline samples that
were at least as anomalous. The percentile then maps onto the project's 1-10
risk scale in fixed, documented bands, so a score of 9 always means "rarer
than 99.5% of baseline behaviour".
"""
import bisect
from dataclasses import dataclass, field
from typing import Dict, List, Sequence

import numpy as np
from sklearn.ensemble import IsolationForest

from app.services.ml.features import EXPLAINABLE_FEATURES, FEATURE_NAMES

# (percentile upper bound, risk). First band whose bound exceeds the sample's
# percentile wins; anything less rare than the median scores 1.
RISK_BANDS = [
    (0.001, 10),
    (0.005, 9),
    (0.01, 8),
    (0.02, 7),
    (0.05, 6),
    (0.10, 5),
    (0.25, 4),
    (0.50, 3),
    (0.75, 2),
]

# Robust z-score above which a feature is reported as a deviation. Only
# increases are reported: "more failures / users / bytes than usual" is what an
# analyst acts on, while "fewer" mostly reflects event types that simply do not
# carry that field (e.g. a network flow has no user name) and read as noise.
DEVIATION_THRESHOLD = 3.0
MAX_DEVIATIONS = 3


def risk_from_percentile(percentile: float) -> int:
    for bound, risk in RISK_BANDS:
        if percentile < bound:
            return risk
    return 1


@dataclass
class Deviation:
    feature: str
    value: float
    baseline_median: float
    robust_z: float

    def describe(self) -> str:
        return (
            f"{self.feature}={self.value:g} is {self.robust_z:.1f} MADs above "
            f"the baseline median of {self.baseline_median:g}"
        )


@dataclass
class Score:
    anomaly_score: float          # IsolationForest.score_samples (lower = more anomalous)
    percentile: float             # share of baseline samples at least as anomalous
    risk_score: int               # 1-10
    deviations: List[Deviation] = field(default_factory=list)


class BehaviourModel:
    def __init__(self, n_estimators: int = 200, random_state: int = 42):
        # Fixed seed: the same baseline must always produce the same scores,
        # otherwise risk scores would change between identical scans.
        self._forest = IsolationForest(
            n_estimators=n_estimators,
            contamination="auto",
            random_state=random_state,
        )
        self._train_scores: List[float] = []
        self._median = np.zeros(len(FEATURE_NAMES))
        self._mad = np.ones(len(FEATURE_NAMES))
        self._raw_median: Dict[str, float] = {}
        self.n_samples = 0

    def fit(self, vectors: Sequence[Sequence[float]], raws: Sequence[Dict[str, float]]) -> "BehaviourModel":
        X = np.asarray(vectors, dtype=float)
        self._forest.fit(X)
        self._train_scores = sorted(self._forest.score_samples(X).tolist())
        self._median = np.median(X, axis=0)
        mad = np.median(np.abs(X - self._median), axis=0) * 1.4826  # ~std for normal data
        # A feature that never varied in the baseline (e.g. no privilege events
        # at all) has MAD 0; any change there is then maximally surprising,
        # which a small floor expresses without dividing by zero.
        self._mad = np.where(mad > 1e-9, mad, 0.1)
        self._raw_median = {
            name: float(np.median([r[name] for r in raws])) for name in FEATURE_NAMES
        }
        self.n_samples = len(X)
        return self

    def _percentile(self, score: float) -> float:
        # Share of baseline samples whose score is <= this one (more or equally anomalous).
        return bisect.bisect_right(self._train_scores, score) / len(self._train_scores)

    def score(self, vectors: Sequence[Sequence[float]], raws: Sequence[Dict[str, float]]) -> List[Score]:
        if not vectors:
            return []
        X = np.asarray(vectors, dtype=float)
        raw_scores = self._forest.score_samples(X)
        robust_z = (X - self._median) / self._mad

        out = []
        for i, s in enumerate(raw_scores):
            percentile = self._percentile(float(s))
            deviations = []
            for j, name in enumerate(FEATURE_NAMES):
                if name not in EXPLAINABLE_FEATURES:
                    continue
                z = float(robust_z[i, j])
                if z >= DEVIATION_THRESHOLD:
                    deviations.append(Deviation(name, raws[i][name], self._raw_median[name], round(z, 1)))
            deviations.sort(key=lambda d: d.robust_z, reverse=True)
            out.append(Score(
                anomaly_score=round(float(s), 4),
                percentile=round(percentile, 4),
                risk_score=risk_from_percentile(percentile),
                deviations=deviations[:MAX_DEVIATIONS],
            ))
        return out
