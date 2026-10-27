# 1단계: Gradle로 JAR 빌드
FROM gradle:8.14-jdk21 AS builder
WORKDIR /build
COPY settings.gradle build.gradle ./
RUN gradle dependencies --no-daemon > /dev/null
COPY src ./src
RUN gradle bootJar --no-daemon

# 2단계: JRE만 포함한 경량 실행 이미지
FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=builder /build/build/libs/visit-counter-1.0.0.jar app.jar
RUN mkdir /data
EXPOSE 8080
CMD ["java", "-jar", "app.jar"]
