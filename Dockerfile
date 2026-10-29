FROM python:3.11-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

COPY --chown=10001:10001 vision_api/ /app/vision_api/
COPY --chown=10001:10001 inference_worker/ /app/inference_worker/
COPY --chown=10001:10001 models/ /app/models/

RUN mkdir -p /app/models/.trt_cache \
    && chown -R 10001:10001 /app

USER 10001:10001

EXPOSE 8000 9000

CMD ["python", "vision_api/app.py"]
