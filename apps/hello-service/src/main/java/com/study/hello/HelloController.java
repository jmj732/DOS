package com.study.hello;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.Map;

/**
 * GitOps 파이프라인이 실제로 무엇을 배포하는지 눈으로 확인하기 위한 최소 엔드포인트.
 * env 값은 Helm values.env로 주입되며, dev/prod에서 다른 값이 나오는 것으로
 * "같은 이미지 + 다른 설정"이 배포됐음을 확인할 수 있다.
 */
@RestController
public class HelloController {

    @Value("${app.env:local}")
    private String env;

    @Value("${app.version:0.1.0}")
    private String version;

    @GetMapping("/api/hello")
    public Map<String, Object> hello() {
        return Map.of(
                "message", "Hello from hello-service",
                "env", env,
                "version", version,
                "timestamp", Instant.now().toString()
        );
    }
}
