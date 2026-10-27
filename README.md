# visit-counter-lab

「Docker & AWS」 수업 실습 파일입니다. 방문할 때마다 숫자가 1씩 오르는 Spring Boot 앱(`visit-counter`)을 단계마다 키워 갑니다.

받는 방법은 둘 중 하나입니다.

* **ZIP**: 이 페이지의 **Code → Download ZIP** → 압축을 풀어 `C:\lab\visit-counter-lab` 처럼 경로에 한글·공백이 없는 곳에 둡니다.
* **git**: `git clone https://github.com/kaeback/visit-counter-lab.git`

앱 폴더(`1-image/`, `2-compose/app/`, `4-aws/app/`)는 모두 [start.spring.io](https://start.spring.io)에서 아래 설정으로 생성한 프로젝트에 실습 파일을 더한 것입니다. IntelliJ 에서 **File → Open** 으로 앱 폴더를 바로 열 수 있습니다.

| 항목 | 값 |
| --- | --- |
| Project · Language | Gradle - Groovy · Java |
| Spring Boot | 4.1.2 |
| Group · Artifact · Package name | `com.example` · `visit-counter` · `com.example` |
| Packaging · Java | Jar · 21 |
| Dependencies | Spring Web |

생성 후 더하거나 바꾼 것: `build.gradle` 의 `version = '1.0.0'`(JAR 이름을 고정), `VisitCounterApplication.java`, `Dockerfile`, `.dockerignore`, 그리고 단계별 의존성·설정·엔티티·테스트·워크플로입니다.

비밀번호가 들어가는 파일은 `*.example` 로만 들어 있습니다. 복사해서 비밀번호만 채우면 됩니다. 실제 비밀번호 파일(`.env`, `secrets/*.txt`, `service.env`, `app.env`)은 Git 에 올리지 않습니다.

| 폴더 | 실습 | 내용 |
| --- | --- | --- |
| `python-example/` | Dockerfile 작성 예시 | 강의의 Python(Flask) Dockerfile 예시를 실제로 빌드·실행 |
| `1-image/` | 1-6 ~ 1-9 | 파일에 숫자를 저장하는 앱, 멀티 스테이지 `Dockerfile`, `.dockerignore` |
| `2-compose/` | 1-10 ~ 1-12 | MySQL 연동 앱 + Nginx + MySQL `docker-compose.yml` |
| `3-bluegreen/` | 3-1 ~ 3-3 | 리눅스 서버 한 대에서 Blue/Green 배포 (`/service/docker` 에 복사) |
| `4-aws/app/` | 4-4 ~ 4-12 | PostgreSQL(Supabase) 판 앱 + 테스트 + GitHub Actions 워크플로 — **내 저장소 루트로 복사** |
| `4-aws/server/` | 4-6 ~ 4-11 | EC2 에 둘 파일: `app.env`, `deploy.sh`, `deploy-bluegreen.sh`, `deploy-gate`, Nginx 설정 |

호스트에 JDK·Gradle 을 설치하지 않아도 됩니다. 빌드는 모두 `gradle:8.14-jdk21` 컨테이너가 합니다.

---

## python-example (Dockerfile 작성 예시)

```powershell
cd python-example
docker build -t pyapp:1.0 .
docker run -d --name pyapp -p 8000:8080 pyapp:1.0
curl.exe http://localhost:8000      # Hello from Python! host=<컨테이너 ID>
docker rm -f pyapp
```

## 1-image (실습 1-6 ~ 1-9)

```powershell
cd 1-image
docker build -t visit-counter:1.0 .
docker run -d --name vc -p 8080:8080 visit-counter:1.0
curl.exe http://localhost:8080      # 방문 횟수: 1
```

## 2-compose (실습 1-10 ~ 1-12)

```powershell
cd 2-compose
Copy-Item .env.example .env
New-Item -ItemType Directory -Force secrets | Out-Null
Set-Content -Path secrets/mysql_root_password.txt -Value 'RootPassword!123' -NoNewline -Encoding ascii
Set-Content -Path secrets/mysql_user_password.txt -Value 'UserPassword!456' -NoNewline -Encoding ascii
docker compose up -d --build
docker compose ps                   # db, app 이 (healthy) 가 된 뒤 nginx 가 뜬다
curl.exe http://localhost           # 방문 횟수: 1
docker compose down                 # down -v 는 DB 데이터까지 지운다
```

macOS 는 `cp .env.example .env`, 비밀번호는 `echo 'RootPassword!123' > secrets/mysql_root_password.txt` 로 만듭니다.

## 3-bluegreen (실습 3-1 ~ 3-3, 리눅스 서버)

메모리 2 GiB 이상(EC2 `t3.small` 등), Docker Engine 과 Compose 플러그인이 있는 서버에서 합니다.

```bash
sudo dnf install -y git            # Ubuntu 는 sudo apt-get install -y git
git clone https://github.com/kaeback/visit-counter-lab.git ~/visit-counter-lab

docker network create dsa_service_network
sudo mkdir -p /service/docker
sudo chown -R "$USER":"$USER" /service
cp -r ~/visit-counter-lab/3-bluegreen/. /service/docker/
mkdir -p /service/docker/volumes/mysql

# 비밀번호만 바꾼다. service.env 의 비밀번호는 .env 의 MYSQL_PASSWORD 와 같아야 한다.
cd /service/docker
cp .env.example .env && cp service.env.example service.env
vi .env service.env
chmod 600 .env service.env
chmod +x deploy.sh

# JAR 빌드 (2-compose 의 앱을 쓴다)
cd ~/visit-counter-lab/2-compose/app
docker run --rm -v "$PWD":/build -w /build gradle:8.14-jdk21 gradle bootJar --no-daemon
cp build/libs/visit-counter-1.0.0.jar /service/docker/build/

cd /service/docker
docker compose up -d                # dsa-mysql (healthy) 확인
./deploy.sh                         # 배포 완료: blue-service
curl http://localhost/              # 방문 횟수: 1
```

## 4-aws (실습 4-4 ~ 4-12)

### 내 저장소 만들기 (실습 4-6)

GitHub 에 `visit-counter` 저장소를 새로 만들고, **`4-aws/app/` 안의 파일이 저장소 루트에 오도록** 올립니다. 숨김 폴더 `.github` 까지 복사됩니다.

```powershell
Copy-Item -Recurse visit-counter-lab\4-aws\app visit-counter
cd visit-counter
git init; git add .; git commit -m "feat: 방문자 카운터"
git branch -M main
git remote add origin https://github.com/<GitHub사용자명>/visit-counter.git
git push -u origin main
```

`.github/workflows/deploy.yml` 이 들어 있어 push 하면 워크플로가 돕니다. 4-7 의 Secrets 를 등록하기 전에는 배포 단계에서 실패하는 것이 정상입니다.

### EC2 에 둘 파일

```bash
git clone https://github.com/kaeback/visit-counter-lab.git ~/visit-counter-lab
cp ~/visit-counter-lab/4-aws/server/app.env.example ~/app.env
vi ~/app.env                        # Supabase Connect 화면의 값 3개, 따옴표 없이
chmod 600 ~/app.env

# 4-7: 단순 배포 스크립트 — GH_USER 한 줄만 내 GitHub 사용자명(소문자)으로 바꾼다
cp ~/visit-counter-lab/4-aws/server/deploy.sh ~/deploy.sh
vi ~/deploy.sh
chmod +x ~/deploy.sh

# 4-10: Nginx
sudo cp ~/visit-counter-lab/4-aws/server/nginx/service-url.inc /etc/nginx/conf.d/
sudo cp ~/visit-counter-lab/4-aws/server/nginx/app.conf /etc/nginx/default.d/

# 4-11: 무중단 배포 스크립트와 배포 키 관문
cp ~/visit-counter-lab/4-aws/server/deploy-bluegreen.sh ~/deploy.sh
vi ~/deploy.sh                      # GH_USER 다시 지정
chmod +x ~/deploy.sh
mkdir -p ~/bin && cp ~/visit-counter-lab/4-aws/server/deploy-gate ~/bin/ && chmod 755 ~/bin/deploy-gate
```
