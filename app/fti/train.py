"""Training pipeline: cechy -> model + metryki ("rejestr modeli" = katalog).

Wyjście: <out>/model.joblib i <out>/metrics.json.
Indexed Job (HPO): przy SWEEP=1 parametry wybiera JOB_COMPLETION_INDEX.
Bramka jakości: MIN_ACCURACY -> exit 1, jeśli model jest za słaby (Job = Failed).
"""

import argparse
import json
import os
import sys
from datetime import UTC, datetime
from pathlib import Path

import joblib
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score
from sklearn.model_selection import train_test_split

from fti import features

SWEEP_GRID = [  # indeks = JOB_COMPLETION_INDEX; celowo od bardzo słabych do mocnych
    {"n_estimators": 1, "max_depth": 1},
    {"n_estimators": 3, "max_depth": 2},
    {"n_estimators": 10, "max_depth": 3},
    {"n_estimators": 50, "max_depth": None},
    {"n_estimators": 200, "max_depth": None},
]


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--features", default=os.getenv("FEATURES_PATH", "/data/features/latest.csv"))
    p.add_argument("--out", default=os.getenv("MODEL_DIR", "/models/" + os.getenv("MODEL_VERSION", "dev")))
    p.add_argument("--version", default=os.getenv("MODEL_VERSION", "dev"))
    a = p.parse_args()

    params = {
        "n_estimators": int(os.getenv("N_ESTIMATORS", "100")),
        "max_depth": int(os.environ["MAX_DEPTH"]) if os.getenv("MAX_DEPTH") else None,
    }
    out = Path(a.out)
    if os.getenv("SWEEP") == "1":
        idx = int(os.environ["JOB_COMPLETION_INDEX"])
        params = SWEEP_GRID[idx % len(SWEEP_GRID)]
        out = out / f"trial-{idx}"
        print(f"[train] sweep trial {idx}: {params}")

    if Path(a.features).exists():
        df = pd.read_csv(a.features)
        src = a.features
    else:
        df = features.build()
        src = "in-memory (brak pliku cech)"
    X = df.drop(columns=["entity_id", "target"])
    y = df["target"]
    X_tr, X_te, y_tr, y_te = train_test_split(X, y, test_size=0.3, random_state=42, stratify=y)

    # .to_numpy(): serwer dostaje surowe listy liczb (bez nazw kolumn)
    model = RandomForestClassifier(random_state=42, **params).fit(X_tr.to_numpy(), y_tr)
    acc = accuracy_score(y_te, model.predict(X_te.to_numpy()))

    out.mkdir(parents=True, exist_ok=True)
    joblib.dump(model, out / "model.joblib")
    metrics = {
        "model_version": a.version,
        "accuracy": round(float(acc), 4),
        "params": params,
        "features": list(X.columns),
        "trained_on": src,
        "trained_at": datetime.now(UTC).isoformat(),
    }
    (out / "metrics.json").write_text(json.dumps(metrics, indent=2))
    print(f"[train] {a.version}: accuracy={acc:.4f} -> {out}/model.joblib")

    min_acc = float(os.getenv("MIN_ACCURACY", "0"))
    if acc < min_acc:
        print(f"[train] BRAMKA: accuracy {acc:.4f} < MIN_ACCURACY {min_acc} -> odrzucam model", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
