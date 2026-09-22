# DevOps_study

실제 GitOps/CI-CD 파이프라인을 분석하고 나온 개선점을 반영해서,
"처음부터 설계한다면"을 실제로 로컬 kind 클러스터 위에 구현한 실습 저장소.

설계 근거와 비교는 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)를 참고.

## 구조

```
apps/hello-service/     # 샘플 Spring Boot 서비스 (배포 대상)
charts/common/          # 공용 Helm chart
gitops/
  apps/                 # App-of-Apps 차트 (ArgoCD Application을 생성)
  values/{dev,prod}/    # 환경별 실제 배포 설정 — 이게 "진실의 원천"
platform/argocd/        # AppProject, root Application 정의
infra/local/            # kind 클러스터 정의
.github/workflows/      # CI(dev 자동 배포) + 승격(prod PR) 워크플로
```

## 로컬에서 처음부터 띄우기

전제: Docker, kind, kubectl, helm이 설치돼 있어야 한다.

```bash
make up                 # kind 클러스터 + ArgoCD + AppProject + root Application까지 한 번에
make argocd-password    # ArgoCD admin 초기 비밀번호 확인
make argocd-forward     # https://localhost:8080 (admin / 위 비밀번호)
make status             # Application 동기화 상태 확인
```

dev 서비스가 뜨면:

```bash
make apps-forward-dev    # http://localhost:8081/api/hello
curl http://localhost:8081/api/hello
```

## 배포 흐름 실습

1. `apps/hello-service/`의 코드를 바꾸고 `main`에 push한다.
2. GitHub Actions `CI - test, build, scan, deploy to dev`가 자동으로:
   테스트 → 이미지 빌드(GHCR, 커밋 SHA 태그) → 스캔 → `gitops/values/dev/hello-service.yaml` 갱신.
3. 로컬 ArgoCD가 이 저장소를 계속 보고 있으므로, 몇 분 안에 `hello-dev` 네임스페이스가
   새 이미지로 바뀐다. `make status`로 확인.
4. dev에서 확인이 끝나면, GitHub Actions에서 `Promote hello-service to prod`를
   수동 실행(`image_tag`에 dev 태그 입력)한다. **직접 push가 아니라 PR이 열린다.**
5. PR을 리뷰하고 병합하면, ArgoCD `root-prod`가 감지해서 `hello-prod` 네임스페이스에 반영한다.
6. `make apps-forward-prod`로 확인.

## 정리

```bash
make down    # kind 클러스터 통째로 삭제
```
