#!/bin/bash
# 위 줄(shebang): 이 스크립트를 bash 로 실행한다
# -e: 명령이 실패하면 즉시 종료 / -u: 정의 안 된 변수를 쓰면 오류 / -o pipefail: 파이프 중간 실패도 실패로 본다
set -euo pipefail

# GitHub 사용자명 (소문자로)
GH_USER="CHANGE_ME"

# 첫 번째 인자를 이미지 태그로 쓴다. 인자가 없으면 메시지를 내고 종료한다
TAG="${1:?이미지 태그를 인자로 넘겨야 한다}"
# GitHub Container Registry 의 전체 이미지 주소
IMAGE="ghcr.io/${GH_USER}/visit-counter:${TAG}"

echo "==> 이미지 내려받기: ${IMAGE}"           # 진행 상황 출력
docker pull "${IMAGE}"                          # 레지스트리에서 새 이미지를 받는다

echo "==> 기존 컨테이너 정리"                   # 진행 상황 출력
docker rm -f visit-counter 2>/dev/null || true  # 기존 컨테이너를 강제 삭제한다. 없어도 실패로 치지 않는다

echo "==> 새 컨테이너 실행"                     # 진행 상황 출력
# -d: 백그라운드 실행 / --name: 컨테이너 이름 / -p: 호스트 8080 → 컨테이너 8080
# --env-file: 홈의 app.env 에서 환경 변수를 읽는다 / --restart: 직접 멈추지 않는 한 다시 띄운다
docker run -d \
  --name visit-counter \
  -p 8080:8080 \
  --env-file "${HOME}/app.env" \
  --restart unless-stopped \
  "${IMAGE}"

echo "==> 배포 완료"                            # 진행 상황 출력
docker ps --filter name=visit-counter           # 새 컨테이너가 떠 있는지 보여준다
