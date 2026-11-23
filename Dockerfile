FROM python:3.13-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 TRAINER_DATA_DIR=/data
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY trainer ./trainer
VOLUME ["/data"]
EXPOSE 8080
CMD ["python", "-m", "trainer.app"]
