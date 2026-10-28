# 1. 베이스 이미지: Python이 들어 있는 공식 이미지
# slim: 불필요한 패키지를 뺀 경량 Debian 기반 Python 3.13
FROM python:3.13-slim

# 2. 환경 변수
# APP_HOME: 앱을 둘 경로 / PYTHONUNBUFFERED: print 출력을 버퍼 없이 바로 로그로 내보낸다
# PIP_NO_CACHE_DIR: pip 다운로드 캐시를 남기지 않아 이미지 크기를 줄인다
ENV APP_HOME=/app \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# 3. 작업 디렉토리
# 위에서 정한 /app 을 작업 디렉터리로 쓴다(없으면 만든다)
WORKDIR $APP_HOME

# 4. 의존성 파일 먼저 (레이어 캐시)
# requirements.txt 만 먼저 복사한다. 소스만 바뀌면 아래 pip install 레이어는 캐시를 재사용한다
COPY requirements.txt .
# 목록에 적힌 패키지(Flask 등)를 설치한다
RUN pip install -r requirements.txt

# 5. 소스 복사
# 빌드 컨텍스트의 나머지 파일을 /app 으로 복사한다
COPY . $APP_HOME

# 6. 포트 선언
# 앱이 8080 포트에서 요청을 받는다고 문서화한다
EXPOSE 8080

# 7. 시작 명령
# 컨테이너가 시작될 때 app.py 를 실행한다
CMD ["python", "app.py"]
