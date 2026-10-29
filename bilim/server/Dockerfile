FROM python:3.12-slim
WORKDIR /srv/server
COPY server/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY server/ .
COPY content/ /srv/content/
ENV BILIM_CONTENT=/srv/content BILIM_DB=/data/bilim.db
VOLUME /data
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
