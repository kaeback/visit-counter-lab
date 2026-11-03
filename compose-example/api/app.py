import os
from flask import Flask

app = Flask(__name__)
COUNT_FILE = "/data/count.txt"          # 볼륨에 저장 → 컨테이너를 지워도 남는다


@app.get("/")
def index():
    n = int(open(COUNT_FILE).read()) + 1 if os.path.exists(COUNT_FILE) else 1
    with open(COUNT_FILE, "w") as f:
        f.write(str(n))
    greeting = os.environ.get("GREETING", "Hello")               # environment: 로 받은 값
    has_key = os.path.exists("/run/secrets/api_key")              # secrets: 로 받은 파일
    return f"{greeting}! count={n} secret={'yes' if has_key else 'no'}\n"


@app.get("/health")
def health():                       # healthcheck 가 부르는 주소
    return "ok\n"


@app.get("/crash")
def crash():                        # restart 정책 확인용: 프로세스를 강제로 끝낸다
    os._exit(1)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
