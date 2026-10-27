import socket

from flask import Flask

app = Flask(__name__)


@app.get("/")
def hello():
    # 컨테이너 안에서는 컨테이너 ID 앞 12자리가 호스트 이름이다
    host = socket.gethostname()
    return f"Hello from Python! host={host}\n"


if __name__ == "__main__":
    # 0.0.0.0: 컨테이너 밖(-p 로 연결한 포트)에서 들어온 요청도 받는다
    app.run(host="0.0.0.0", port=8080)
