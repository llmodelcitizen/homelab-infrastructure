FROM alpine:3.21
RUN apk add --no-cache aws-cli bind-tools
COPY sync.py /sync.py
ENTRYPOINT ["python3", "/sync.py"]
