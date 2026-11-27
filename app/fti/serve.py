"""Inference: FastAPI serwujący model z MODEL_PATH.

/healthz  liveness (proces żyje)
/ready    readiness (model załadowany)
/version  wersja i metryki modelu
/predict  POST {"instances": [[13 liczb], ...]}
/predict/entity/{id}  cechy z online store (Redis)
/burn?ms= sztuczne obciążenie CPU (lab HPA)
PREDICT_DELAY_MS  sztuczne opóźnienie każdej predykcji (lab A08)
/metrics  Prometheus
"""

import json
import logging
import os
import socket
import threading
import time
from pathlib import Path

import joblib
from fastapi import FastAPI, HTTPException, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from pydantic import BaseModel

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"), format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("fti")

MODEL_PATH = Path(os.getenv("MODEL_PATH", "/opt/model/model.joblib"))
STARTUP_DELAY = float(os.getenv("STARTUP_DELAY", "0"))  # symulacja ładowania dużego modelu
PREDICT_DELAY_MS = float(os.getenv("PREDICT_DELAY_MS", "0"))  # symulacja wolnego modelu (alert latencji, A08)
POD = socket.gethostname()

PREDICTIONS = Counter("fti_predictions_total", "Liczba predykcji", ["model_version"])
ERRORS = Counter("fti_prediction_errors_total", "Błędy predykcji", ["reason"])
LATENCY = Histogram(
    "fti_predict_latency_seconds", "Czas predykcji", buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5)
)

state = {"model": None, "meta": {}}
app = FastAPI(title="fti-inference")


def load_model() -> None:
    if STARTUP_DELAY:
        log.info("symuluję ładowanie dużego modelu: %ss", STARTUP_DELAY)
        time.sleep(STARTUP_DELAY)
    for k in ("LOG_LEVEL", "MODEL_PATH", "REDIS_HOST"):
        log.info("%s has value %s", k, os.getenv(k))
    if not MODEL_PATH.exists():
        log.error("brak modelu: %s (readiness zostanie 503)", MODEL_PATH)
        return
    state["model"] = joblib.load(MODEL_PATH)
    meta_file = MODEL_PATH.parent / "metrics.json"
    state["meta"] = json.loads(meta_file.read_text()) if meta_file.exists() else {}
    log.info("model załadowany: %s (wersja %s)", MODEL_PATH, version())


def version() -> str:
    return os.getenv("MODEL_VERSION") or state["meta"].get("model_version", "unknown")


@app.on_event("startup")
def _startup() -> None:
    threading.Thread(target=load_model, daemon=True).start()


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/ready")
def ready(response: Response):
    if state["model"] is None:
        response.status_code = 503
        return {"ready": False}
    return {"ready": True}


@app.get("/version")
def get_version():
    return {"model_version": version(), "pod": POD, "model_path": str(MODEL_PATH), "metrics": state["meta"]}


class Instances(BaseModel):
    instances: list[list[float]]


def _predict(rows):
    if state["model"] is None:
        ERRORS.labels("model_not_loaded").inc()
        raise HTTPException(503, "model not loaded")
    with LATENCY.time():
        if PREDICT_DELAY_MS:
            time.sleep(PREDICT_DELAY_MS / 1000)
        preds = state["model"].predict(rows).tolist()
    PREDICTIONS.labels(version()).inc(len(rows))
    return {"predictions": preds, "model_version": version(), "pod": POD}


@app.post("/predict")
def predict(body: Instances):
    try:
        return _predict(body.instances)
    except ValueError as e:
        ERRORS.labels("bad_input").inc()
        raise HTTPException(400, str(e)) from e


@app.get("/predict/entity/{entity_id}")
def predict_entity(entity_id: int):
    host = os.getenv("REDIS_HOST")
    if not host:
        raise HTTPException(501, "REDIS_HOST not set (brak online feature store)")
    import redis

    raw = redis.Redis(host=host, port=int(os.getenv("REDIS_PORT", "6379")), socket_connect_timeout=2).get(
        f"features:{entity_id}"
    )
    if raw is None:
        ERRORS.labels("entity_not_found").inc()
        raise HTTPException(404, f"brak cech dla encji {entity_id}")
    feats = json.loads(raw)
    res = _predict([list(feats.values())])
    res["entity_id"] = entity_id
    return res


@app.get("/burn")
def burn(ms: int = 200):
    end = time.perf_counter() + ms / 1000
    x = 0
    while time.perf_counter() < end:
        x += 1
    return {"burned_ms": ms, "pod": POD}
