#!/bin/bash
set -euo pipefail

# GitHub 사용자명 (소문자로)
GH_USER="CHANGE_ME"

TAG="${1:?이미지 태그를 인자로 넘겨야 한다}"
IMAGE="ghcr.io/${GH_USER}/visit-counter:${TAG}"

echo "==> 이미지 내려받기: ${IMAGE}"
docker pull "${IMAGE}"

echo "==> 기존 컨테이너 정리"
docker rm -f visit-counter 2>/dev/null || true

echo "==> 새 컨테이너 실행"
docker run -d \
  --name visit-counter \
  -p 8080:8080 \
  --env-file "${HOME}/app.env" \
  --restart unless-stopped \
  "${IMAGE}"

echo "==> 배포 완료"
docker ps --filter name=visit-counter
