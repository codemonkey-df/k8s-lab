# Jeden obraz na całe FTI: ten sam kod = te same wersje bibliotek w treningu i inference
# (model zapisany joblibem musi być wczytany tą samą wersją scikit-learn).
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY fti/ fti/
# Model "wypalony" w obrazie -> inference działa od pierwszego laba, bez PVC.
RUN python -m fti.train --out /opt/model --version baked-0

# Nie-root z numerycznym UID -> przejdzie PSA "restricted" (runAsNonRoot).
RUN useradd -u 10001 -m app
USER 10001

ENV MODEL_PATH=/opt/model/model.joblib
EXPOSE 8080
CMD ["uvicorn", "fti.serve:app", "--host", "0.0.0.0", "--port", "8080"]
