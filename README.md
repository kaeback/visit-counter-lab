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
| `multistage-example/` | 멀티 스테이지 직접 해 보기 | 같은 Java 프로그램을 일반 빌드·멀티 스테이지로 빌드해 크기 비교 |
| `node-example/` | Node.js 멀티 스테이지 직접 해 보기 | Node로 빌드한 HTML을 Nginx로 서빙, 레이어 캐시 확인 |
| `compose-example/` | Compose 문법 직접 해 보기 | nginx + Flask 두 서비스로 ports·.env·secrets·volumes·healthcheck·restart와 compose 명령 확인 |
| `dockerfile-ref/` | Part 2 Dockerfile 레퍼런스 직접 해 보기 | shell/exec form, ENV·ARG, WORKDIR·COPY·ADD, USER·LABEL·HEALTHCHECK |
| `1-image/` | 1-6 ~ 1-9 | 파일에 숫자를 저장하는 앱, 멀티 스테이지 `Dockerfile`, `.dockerignore` |
| `2-compose/` | 1-10 ~ 1-12 | MySQL 연동 앱 + Nginx + MySQL `docker-compose.yml` |
| `3-bluegreen/` | 3-1 ~ 3-3 | 내 PC(Docker Desktop)에서 Blue/Green 무중단 배포. `deploy.sh` 는 deployer 컨테이너가 실행 |
| `4-aws/app/` | 4-4 ~ 4-13 | PostgreSQL(Supabase) 판 앱 + 테스트 — **내 저장소 루트로 복사** |
| `4-aws/workflows/` | 4-7 · 4-8 · 4-10 | GitHub Actions 워크플로를 단계별로: `1-test.yml` → `2-build-push.yml` → `3-deploy.yml` |
| `4-aws/server/` | 4-6 ~ 4-12 | EC2 에 둘 파일: `app.env`, `deploy.sh`, `deploy-bluegreen.sh`, `deploy-gate`, Nginx 설정 |

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

## multistage-example (일반 빌드 vs 멀티 스테이지)

```powershell
cd multistage-example
docker build -f Dockerfile.single -t hello:single .
docker build -f Dockerfile.multi -t hello:multi .
docker image ls hello                     # single 724MB · multi 457MB
docker run --rm hello:multi               # Hello from Java 21.x
docker run --rm hello:multi javac -version   # javac: not found (실행 이미지엔 컴파일러가 없다)
docker rmi hello:single hello:multi
```

## node-example (Node.js 빌드 → Nginx 서빙)

```powershell
cd node-example
docker build -t node-web:1.0 .
docker run -d --name node-web -p 8082:80 node-web:1.0
curl.exe http://localhost:8082      # <h1>Hello from Node build!</h1>
# src\index.md 를 고치고 다시 빌드하면 npm ci 까지 CACHED
docker build -t node-web:1.1 .
docker rm -f node-web; docker rmi node-web:1.0 node-web:1.1
```

## compose-example (Compose 문법 직접 해 보기)

```powershell
cd compose-example
Copy-Item .env.example .env                              # macOS: cp
Copy-Item secrets\api_key.txt.example secrets\api_key.txt
docker compose up -d --build
curl.exe http://localhost:8083/api/       # Hello Compose! count=1 secret=yes
curl.exe http://localhost:8080/           # 실패: api 는 ports 가 없다
docker compose config                     # .env 치환 결과
docker compose exec api cat /run/secrets/api_key
curl.exe http://localhost:8083/api/crash  # restart: unless-stopped 로 다시 뜬다
docker compose down -v --rmi local
```

## dockerfile-ref (Part 2 레퍼런스 직접 해 보기)

```powershell
cd dockerfile-ref
# shell form vs exec form: docker top 의 PID 1, docker stop 후 Exited (137) vs (0)
docker build -f Dockerfile.shell -t sig:shell .; docker build -f Dockerfile.exec -t sig:exec .
# ENV·ARG
docker build -f Dockerfile.envarg --build-arg APP_VERSION=2.0 -t envarg:2.0 .; docker run --rm envarg:2.0
# WORKDIR·RUN cd·COPY·ADD
docker build -f Dockerfile.workdir -t workdir:1.0 .; docker run --rm workdir:1.0
# USER·LABEL / HEALTHCHECK
docker build -f Dockerfile.user -t user:1.0 .; docker run --rm user:1.0
docker build -f Dockerfile.health -t health:1.0 .; docker run -d --name web-health -p 8084:80 health:1.0
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

## 3-bluegreen (실습 3-1 ~ 3-3)

Docker Desktop 만 있으면 내 PC 에서 합니다(Ubuntu·WSL 배포판 설치 불필요). 명령은 PowerShell 기준입니다.
`deploy.sh` 는 bash 스크립트라서 **deployer 컨테이너**(docker CLI + bash, `deployer/Dockerfile`) 안에서 실행합니다. 이 컨테이너가 Docker 소켓으로 내 PC 의 Docker 를 조작합니다.

```powershell
# 3-1. 준비 — JAR 빌드 (2-compose 의 앱을 쓴다)
cd C:\lab\visit-counter-lab\2-compose\app
docker run --rm -v "${PWD}:/build" -w /build gradle:8.14-jdk21 gradle bootJar --no-daemon
Copy-Item build\libs\visit-counter-1.0.0.jar ..\..\3-bluegreen\build\

# 비밀번호 파일과 DB 폴더, 네트워크
cd ..\..\3-bluegreen
Copy-Item .env.example .env
Copy-Item service.env.example service.env      # 비밀번호는 .env 의 MYSQL_PASSWORD 와 같게
New-Item -ItemType Directory -Force volumes\mysql | Out-Null
docker network create dsa_service_network

# DB·Nginx 기동
docker compose up -d
docker compose ps                               # dsa-mysql (healthy) 확인

# 3-3. 배포 — deploy.sh 를 deployer 컨테이너에서 실행 (첫 실행 때 deployer 이미지를 빌드한다)
docker compose run --rm deployer                # 배포 완료: blue-service
curl.exe http://localhost/                      # 방문 횟수: 1
```

v2 배포: `VisitCounterApplication.java` 의 응답 문구를 바꾸고 → JAR 을 다시 빌드해 `build\` 에 복사 → `docker compose run --rm deployer`. 다른 터미널에서 요청을 반복해 두면 응답이 끊기지 않고 v2 로 바뀌는 것을 볼 수 있습니다.

```powershell
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # 한글 응답이 깨지지 않게
while ($true) { (curl.exe -s -w "%{http_code}" http://localhost/) -join "  "; Start-Sleep -Milliseconds 300 }
```

정리:

```powershell
docker rm -f blue-service green-service
docker compose down
docker network rm dsa_service_network
Remove-Item -Recurse -Force volumes
```

macOS 는 같은 흐름을 터미널에서 실행합니다(`Copy-Item` → `cp`, `New-Item …` → `mkdir -p volumes/mysql`, `curl.exe` → `curl`).
리눅스 서버(메모리 2 GiB 이상)라면 deployer 없이 `./deploy.sh` 를 바로 실행해도 됩니다. 이때 폴더는 `/service/docker` 로 복사합니다(`deploy.sh` 의 `BASE`).

## 4-aws (실습 4-4 ~ 4-13)

### 내 저장소 만들기 (실습 4-6)

GitHub 에 `visit-counter` 저장소를 새로 만들고, **`4-aws/app/` 안의 파일이 저장소 루트에 오도록** 올립니다.

```powershell
Copy-Item -Recurse visit-counter-lab\4-aws\app visit-counter
cd visit-counter
git init; git add .; git commit -m "feat: 방문자 카운터"
git branch -M main
git remote add origin https://github.com/<GitHub사용자명>/visit-counter.git
git push -u origin main
```

처음 올릴 때는 워크플로가 없습니다. 아래 순서로 한 단계씩 넣습니다.

### GitHub Actions 단계별로 붙이기 (실습 4-7 · 4-8 · 4-10)

워크플로 파일은 내 저장소의 `.github/workflows/deploy.yml` 하나이고, 단계마다 `4-aws/workflows/` 의 파일로 덮어씁니다.

| 실습 | 복사할 파일 | push 하면 |
|---|---|---|
| 4-7 테스트 자동화 (예제 1) | `1-test.yml` | `test` job 만 돈다 |
| 4-8 빌드·push 자동화 | `2-build-push.yml` | `test` → `build-and-push`, GHCR 에 커밋 해시 태그 |
| 4-10 자동 배포 (예제 2) | `3-deploy.yml` | `test` → `build-and-deploy`, EC2 의 `~/deploy.sh` 실행 (4-9 의 Secrets 3개 필요) |

```powershell
# C:\lab\visit-counter 에서 (4-7 처음 한 번만 폴더 생성)
New-Item -ItemType Directory -Force .github\workflows
Copy-Item ..\visit-counter-lab\4-aws\workflows\1-test.yml .github\workflows\deploy.yml
git add .; git commit -m "ci: push하면 테스트 자동 실행"; git push
```

### EC2 에 둘 파일

```bash
git clone https://github.com/kaeback/visit-counter-lab.git ~/visit-counter-lab
cp ~/visit-counter-lab/4-aws/server/app.env.example ~/app.env
vi ~/app.env                        # Supabase Connect 화면의 값 3개, 따옴표 없이
chmod 600 ~/app.env

# 4-9: 단순 배포 스크립트 — GH_USER 한 줄만 내 GitHub 사용자명(소문자)으로 바꾼다
cp ~/visit-counter-lab/4-aws/server/deploy.sh ~/deploy.sh
vi ~/deploy.sh
chmod +x ~/deploy.sh

# 4-11: Nginx
sudo cp ~/visit-counter-lab/4-aws/server/nginx/service-url.inc /etc/nginx/conf.d/
sudo cp ~/visit-counter-lab/4-aws/server/nginx/app.conf /etc/nginx/default.d/

# 4-12: 무중단 배포 스크립트와 배포 키 관문
cp ~/visit-counter-lab/4-aws/server/deploy-bluegreen.sh ~/deploy.sh
vi ~/deploy.sh                      # GH_USER 다시 지정
chmod +x ~/deploy.sh
mkdir -p ~/bin && cp ~/visit-counter-lab/4-aws/server/deploy-gate ~/bin/ && chmod 755 ~/bin/deploy-gate
```
