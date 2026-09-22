# --- Build stage -------------------------------------------------------
# Maven 이미지를 빌더로만 쓰고 최종 이미지에는 남기지 않는다 (멀티스테이지).
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /workspace

# 의존성 레이어를 먼저 캐시해서 소스만 바뀌었을 때 재다운로드하지 않게 한다.
COPY pom.xml .
RUN mvn -q -B dependency:go-offline

COPY src ./src
RUN mvn -q -B -DskipTests package

# --- Runtime stage -------------------------------------------------------
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app

# non-root 사용자로 실행 (M-ADP의 buildkitd/privileged 문제를 반면교사)
RUN addgroup -S app && adduser -S app -G app
COPY --from=build /workspace/target/hello-service.jar app.jar
USER app

EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-jar", "/app/app.jar"]
