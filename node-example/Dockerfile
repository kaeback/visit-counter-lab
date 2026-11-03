# 1단계: Node로 빌드 (dist/ 생성)
FROM node:22 AS builder
WORKDIR /app
# 의존성 목록만 먼저 → 소스만 바뀌면 npm ci 는 CACHED
COPY package*.json .
RUN npm ci
COPY . .
RUN npm run build

# 2단계: 빌드 결과(dist)만 Nginx로 서빙
FROM nginx:1.30
COPY --from=builder /app/dist /usr/share/nginx/html
