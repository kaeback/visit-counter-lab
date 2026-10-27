# 1. 베이스 이미지: Python이 들어 있는 공식 이미지
FROM python:3.13-slim

# 2. 환경 변수
ENV APP_HOME=/app \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# 3. 작업 디렉토리
WORKDIR $APP_HOME

# 4. 의존성 파일 먼저 (레이어 캐시)
COPY requirements.txt .
RUN pip install -r requirements.txt

# 5. 소스 복사
COPY . $APP_HOME

# 6. 포트 선언
EXPOSE 8080

# 7. 시작 명령
CMD ["python", "app.py"]
