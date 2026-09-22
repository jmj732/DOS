# 설계 근거

이 저장소는 실제 온프레미스 GitOps 파이프라인 사례를 분석하고, 거기서 나온 문제들을
반면교사로 삼아 "처음부터 만든다면"을 실제로 구현한 것이다. 코드가 아니라 설계
결정을 기록하는 것이 이 문서의 목적이다.

## 진실의 원천을 셋으로 명확히 나눈다

| 계층 | 진실의 원천 | 이 저장소에서 |
| --- | --- | --- |
| 이미지 | 커밋 SHA | `ci-dev.yaml`이 `sha-<12자>` 태그로 GHCR에 push |
| 배포 상태 | Git (`gitops/values/{env}/`) | ArgoCD가 이 값을 클러스터 상태와 계속 비교 |
| 비밀 값 | (이 저장소에는 없음) | 데모 범위 밖(Vault 등은 미구현). 다만 실수로 커밋되는 것 자체는 gitleaks + push protection이 막는다 |

## 분석했던 실제 사례와 무엇이 다른가

| 결정 | 실제 사례에서 본 방식 | 이 저장소 | 이유 |
| --- | --- | --- | --- |
| 이미지 태그 | 브랜치명(`dev-0.2.9`), 재사용 가능 | 커밋 SHA(`sha-abcdef123456`), 불변 | 같은 태그를 다시 push해서 이미지가 몰래 바뀌는 일을 원천 차단 |
| dev 배포 | 브랜치 push → 바로 반영 | 동일. `main`에 push되면 CI가 바로 dev values를 갱신 | dev는 빠른 반복이 목적이므로 그대로 유지 |
| prod 배포 | `prod-*` 브랜치를 사람이 만들면 즉시 반영, 리뷰 없음 | `promote-to-prod.yaml`이 **항상 PR을 염** | prod로 가는 유일한 경로를 "리뷰 가능한 변경"으로 강제 |
| prod 롤백 | 워크플로 자체가 없음 | 사실상 자동으로 해결됨 | 롤백 = 이전 태그로 다시 promote PR을 한 번 더 여는 것. 별도 workflow 불필요 |
| 테스트·스캔 | 없음 | `test` job이 먼저 통과해야 이미지 빌드, Trivy 스캔은 리포트만(§ 한계 참고) | 빌드는 되지만 동작하지 않는 이미지를 막음 |
| 권한 분리 | 모든 Application이 `project: default` | `AppProject dev` / `prod`로 destination을 네임스페이스 단위로 제한 | dev 쪽 실수가 prod 네임스페이스에 닿지 못하게 |
| 시크릿 | 일부 평문으로 Git에 존재 | 이 저장소에는 시크릿 자체가 없음(범위 밖) | 데모에서 재현하지 않는 것으로 원천 차단 |

## 시크릿 하드코딩 방지: 서버 없이, 두 겹으로

분석했던 실제 사례에서 DB 비밀번호가 values 파일에 평문으로 커밋된 적이 있었다.
이걸 막는 데는 SonarQube 같은 정적 분석 서버가 필요 없다. 서버 없이 두 겹으로 막는다.

| 계층 | 도구 | 언제 작동하나 | 잡는 범위 |
| --- | --- | --- | --- |
| push 시점 | GitHub 네이티브 secret scanning + push protection | `git push` 하는 순간, 저장소에 닿기도 전에 | GitHub이 아는 특정 제공자 패턴(AWS, Stripe 등 실제 키 형식) |
| CI 시점 | `secret-scan.yaml` (gitleaks) | main에 push되거나 PR이 열릴 때마다, 저장소 전체 대상 | 제공자 패턴 + 일반 패턴(`password=`, `api_key=` 같은 고엔트로피 값) |

두 층이 필요한 이유는 실제로 검증했다. 무작위로 생성한 가짜 AWS 키를 커밋해 보니
push protection은 통과시켰지만(자기가 아는 정확한 제공자 포맷이 아니었던 것으로 보임),
gitleaks는 `aws-access-token`과 `generic-api-key` 두 규칙으로 잡아내 CI를 실패시켰다.
Trivy와 달리 이 job은 통과가 아니라 **실패가 기본값**이다(exit-code를 손대지 않았다) —
시크릿 유출은 오탐이 적고 결과가 명확해서, 발견되면 그냥 막는 게 맞다고 판단했다.

이 방식을 고른 것은 SonarQube를 의도적으로 빼고 나서다. 이유는 아래 참고.

## SonarQube를 넣지 않은 이유

일반적인 정적 분석(코드 스멜·복잡도·중복)은 이 저장소의 `hello-service`처럼 파일
몇 개짜리 데모 코드에서는 얻는 게 거의 없다. 반면 붙이는 비용은 크다: GitHub
Actions는 클라우드에서 도는데 kind 클러스터는 로컬에 있어서, SonarQube를 self-hosted
러너 없이는 CI에서 붙일 방법이 없다. 두 가지 현실적인 선택지가 있었다.

- **자체 호스팅 GitHub Actions 러너**: 이 컴퓨터에서 워크플로가 실제 권한으로
  돈다는 뜻이다. public 저장소에서 이 조합은 GitHub이 명시적으로 경고하는
  위험 조합이다(낯선 PR이 이 컴퓨터에서 코드를 실행할 수 있게 됨).
- **SonarQube Cloud**: 안전하지만 외부 SaaS 가입이 필요하다.

코드량 대비 비용이 맞지 않다고 판단해 채택하지 않았다. 대신 실제로 문제가 됐던
"시크릿 하드코딩"만 정확히 겨냥해서, 서버도 외부 계정도 필요 없는 gitleaks로
해결했다. 정적 분석을 직접 체험해 보고 싶다면 CI에 붙이지 않고 로컬에서
한 번 돌려 보는 것으로 충분하다:

```bash
docker run -d --name sonarqube -p 9000:9000 sonarqube:community
# http://localhost:9000 (admin/admin) 접속 후 프로젝트 토큰 발급
cd apps/hello-service
mvn sonar:sonar -Dsonar.host.url=http://localhost:9000 -Dsonar.token=<발급받은 토큰>
```

## 이 저장소가 일부러 단순화한 부분 (한계)

실무 그대로 재현하면 로컬 실습 범위를 넘어서므로, 아래는 의도적으로 생략하거나
축소했다. 실제 팀에서 쓸 때는 이 부분을 채워야 한다.

- **브랜치 보호 규칙을 실제로 걸지 않았다.** `promote-to-prod.yaml`이 PR만 여는 것으로
  "프로세스"는 만들어져 있지만, `main`에 브랜치 보호(필수 리뷰)를 걸지 않으면 누군가
  `gitops/values/prod/`를 직접 커밋해도 막히지 않는다. 실무에서는 `.github/CODEOWNERS`를
  활성화하고 브랜치 보호에 "코드 오너 리뷰 필수"를 건다.
- **Trivy 스캔이 파이프라인을 막지 않는다(`exit-code: '0'`).** base 이미지에 흔히
  존재하는 취약점 때문에 데모가 항상 실패하는 것을 피하려는 선택이다. 실무에서는
  `exit-code: '1'`로 바꾸고 예외 목록을 관리해야 한다.
- **시크릿 관리(Vault 등)가 없다.** hello-service가 시크릿을 쓰지 않으므로 필요가
  없었다. 실제 서비스를 올린다면 Vault agent injector를 붙이거나
  External Secrets Operator를 쓴다.
- **클러스터가 하나뿐이다.** dev/prod를 네임스페이스로만 나눴다. 실제 조직은
  네트워크·장애 격리를 위해 클러스터 자체를 분리하는 경우가 많다. 이 저장소는
  "환경 분리 로직"을 보여 주는 것이 목적이라 클러스터를 하나로 유지했다.
- **관측성(Prometheus/Grafana)이 없다.** 로컬 kind에 올리면 리소스 부담이 커서
  뺐다. `docs/`에서 개념만 참고.

## 파이프라인 흐름

```
1. apps/hello-service/** 변경을 main에 push
2. ci-dev.yaml: test → build & push(GHCR, sha 태그) → scan(Trivy) → gitops/values/dev 자동 커밋
3. ArgoCD root-dev가 감지 → hello-service-dev Application sync → hello-dev 네임스페이스에 반영
4. dev에서 확인 후, GitHub Actions에서 promote-to-prod.yaml을 수동 실행(dev 태그 입력)
5. PR이 열림 → 리뷰 후 병합
6. ArgoCD root-prod가 감지 → hello-service-prod Application sync → hello-prod 네임스페이스에 반영
```

3번과 6번 사이의 차이가 이 설계의 핵심이다: **dev는 자동, prod는 사람이 검토한 변경만.**
