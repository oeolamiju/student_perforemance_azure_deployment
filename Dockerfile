FROM python:3.10-slim-bookworm
WORKDIR /app

# libgomp1 is the OpenMP runtime xgboost needs to import
RUN apt-get update \
    && apt-get install -y --no-install-recommends libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Dependencies go in before the code so this layer is reused when only code changes
COPY requirements.txt setup.py ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . /app
CMD ["python3", "app.py"]
