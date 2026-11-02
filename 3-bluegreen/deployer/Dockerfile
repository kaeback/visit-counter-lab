# deploy.sh 를 실행하는 도구 이미지 — docker CLI + bash
# 호스트에 bash 가 없어도(Windows PowerShell) Docker Desktop 만 있으면 배포 스크립트를 돌릴 수 있다.
# 이 컨테이너는 /var/run/docker.sock 으로 호스트의 Docker 를 조작한다(docker-compose.yml 의 deployer 서비스).
FROM docker:29-cli

# bash: deploy.sh 는 bash 문법을 쓴다(기본 이미지에는 sh 만 있다)
# tzdata: 배포 로그·이미지 태그의 시각을 한국 시간으로 남기기 위해
RUN apk add --no-cache bash tzdata

ENV TZ=Asia/Seoul
