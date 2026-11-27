"""Feature pipeline: surowe dane -> cechy.

Offline: CSV w FEATURES_DIR (features-<ts>.csv + latest.csv) -> wejście treningu.
Online:  jeśli ustawiony REDIS_HOST, każda encja ląduje w Redisie jako
         klucz features:<entity_id> (JSON) -> wejście inference /predict/entity/<id>.
"""

import argparse
import json
import os
import time
from datetime import UTC, datetime
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.datasets import load_wine

FEATURE_COLUMNS = None  # ustawiane w build()


def build(seed: int = 0, noise: float = 0.05) -> pd.DataFrame:
    """Zbiór wine + szum = "nowe dane z dnia". Bez pobierania z sieci."""
    global FEATURE_COLUMNS
    X, y = load_wine(return_X_y=True, as_frame=True)
    rng = np.random.default_rng(seed)
    X = X + rng.normal(0, noise, X.shape) * X.std().values
    X.columns = [c.replace("/", "_") for c in X.columns]
    FEATURE_COLUMNS = list(X.columns)
    df = X.copy()
    df.insert(0, "entity_id", range(len(df)))
    df["target"] = y
    return df


def push_online(df: pd.DataFrame, host: str, port: int) -> None:
    import redis

    r = redis.Redis(host=host, port=port, socket_connect_timeout=5)
    pipe = r.pipeline()
    for row in df.itertuples(index=False):
        d = row._asdict()
        eid = d.pop("entity_id")
        d.pop("target")
        pipe.set(f"features:{eid}", json.dumps(d))
    pipe.set("features:updated_at", datetime.now(UTC).isoformat())
    pipe.execute()
    print(f"[features] online store: {len(df)} encji -> redis://{host}:{port}")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--out", default=os.getenv("FEATURES_DIR", "/data/features"))
    p.add_argument("--seed", type=int, default=int(os.getenv("SEED", time.time() // 60)))
    p.add_argument("--noise", type=float, default=float(os.getenv("NOISE", "0.3")))
    a = p.parse_args()

    df = build(a.seed, a.noise)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(UTC).strftime("%Y%m%dT%H%M%S")
    df.to_csv(out / f"features-{ts}.csv", index=False)
    df.to_csv(out / "latest.csv", index=False)
    print(f"[features] offline store: {len(df)} wierszy -> {out}/features-{ts}.csv (+ latest.csv)")

    if os.getenv("REDIS_HOST"):
        push_online(df, os.environ["REDIS_HOST"], int(os.getenv("REDIS_PORT", "6379")))


if __name__ == "__main__":
    main()
