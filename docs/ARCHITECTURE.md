# 설계 근거

이 저장소는 실제 온프레미스 GitOps 파이프라인 사례를 분석하고, 거기서 나온 문제들을
반면교사로 삼아 "처음부터 만든다면"을 실제로 구현한 것이다. 코드가 아니라 설계
결정을 기록하는 것이 이 문서의 목적이다.

## 진실의 원천을 셋으로 명확히 나눈다

| 계층 | 진실의 원천 | 이 저장소에서 |
| --- | --- | --- |
| 이미지 | 커밋 SHA | `ci-dev.yaml`이 `sha-<12자>` 태그로 GHCR에 push |
| 배포 상태 | Git (`gitops/values/{env}/`) | ArgoCD가 이 값을 클러스터 상태와 계속 비교 |
| 비밀 값 | (이 저장소에는 없음) | 데모 범위 밖. 실무라면 Vault/External Secrets |

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
