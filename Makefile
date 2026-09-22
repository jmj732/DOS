CLUSTER_NAME := devops-study

.PHONY: up down status argocd-password argocd-forward apps-forward-dev apps-forward-prod \
        gitlab-up gitlab-down gitlab-root-password gitlab-runner-register gitlab-deploy apps-forward-dev-gitlab

## kind 클러스터를 만들고 ArgoCD + 프로젝트 + root Application까지 한 번에 올린다.
up:
	kind create cluster --config infra/local/kind-config.yaml
	kubectl create namespace argocd
	helm repo add argo https://argoproj.github.io/argo-helm --force-update
	helm repo update
	helm install argocd argo/argo-cd --version 10.9.2 --namespace argocd --wait
	kubectl apply -f platform/argocd/project-dev.yaml
	kubectl apply -f platform/argocd/project-prod.yaml
	kubectl apply -f platform/argocd/root-dev.yaml
	kubectl apply -f platform/argocd/root-prod.yaml
	@echo ""
	@echo "완료. 'make argocd-password'로 admin 비밀번호를 확인하고,"
	@echo "'make argocd-forward'로 UI를 열어 보세요."

## 클러스터를 통째로 지운다.
down:
	kind delete cluster --name $(CLUSTER_NAME)

## ArgoCD Application 상태를 확인한다.
status:
	kubectl get applications -n argocd
	@echo ""
	kubectl get pods -n hello-dev 2>/dev/null || echo "hello-dev 네임스페이스가 아직 없습니다 (sync 대기 중일 수 있음)"
	kubectl get pods -n hello-prod 2>/dev/null || echo "hello-prod 네임스페이스가 아직 없습니다 (sync 대기 중일 수 있음)"

## ArgoCD 초기 admin 비밀번호.
argocd-password:
	kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
	@echo ""

## ArgoCD UI를 https://localhost:8080 으로 연다.
argocd-forward:
	kubectl port-forward svc/argocd-server -n argocd 8080:443

## dev로 배포된 hello-service를 http://localhost:8081 로 연다.
apps-forward-dev:
	kubectl port-forward svc/hello-service-dev -n hello-dev 8081:80

## prod로 배포된 hello-service를 http://localhost:8082 로 연다.
apps-forward-prod:
	kubectl port-forward svc/hello-service-prod -n hello-prod 8082:80

# ============================================================
# GitLab 실습 (로컬 GitLab CE + 자체 호스팅 GitLab Runner)
# ============================================================

## 로컬 GitLab CE를 Docker로 띄운다. 최초 부팅은 3~5분 걸린다.
gitlab-up:
	docker volume create gitlab-config
	docker volume create gitlab-logs
	docker volume create gitlab-data
	docker run -d --name gitlab \
		--hostname localhost \
		-p 8929:8929 -p 2224:22 -p 5050:5050 \
		--shm-size 512m \
		-v gitlab-config:/etc/gitlab \
		-v gitlab-logs:/var/log/gitlab \
		-v gitlab-data:/var/opt/gitlab \
		-e GITLAB_OMNIBUS_CONFIG="external_url 'http://localhost:8929'; gitlab_rails['gitlab_shell_ssh_port'] = 2224; registry_external_url 'http://localhost:5050'; registry_nginx['listen_port'] = 5050; registry_nginx['listen_https'] = false; registry['enable'] = true;" \
		gitlab/gitlab-ce:latest
	@echo "부팅 중입니다. http://localhost:8929/users/sign_in 이 200을 줄 때까지 기다리세요."

## GitLab을 완전히 지운다 (볼륨까지 삭제 — 프로젝트·계정 데이터가 전부 사라진다).
gitlab-down:
	docker rm -f gitlab gitlab-runner-local 2>/dev/null || true
	docker volume rm gitlab-config gitlab-logs gitlab-data 2>/dev/null || true

## root 계정 초기 비밀번호 (최초 24시간만 유효, UI 로그인용).
gitlab-root-password:
	docker exec gitlab cat /etc/gitlab/initial_root_password | grep '^Password:'

## GitLab Runner를 등록하고 docker executor(+dind)로 실행한다.
## 사전 조건: gitlab-runner-register.sh로 발급받은 토큰을 GITLAB_RUNNER_TOKEN에 넣어야 한다.
gitlab-runner-register:
	docker rm -f gitlab-runner-local 2>/dev/null || true
	docker run -d --name gitlab-runner-local --restart unless-stopped \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v gitlab-runner-config:/etc/gitlab-runner \
		gitlab/gitlab-runner:latest
	docker exec gitlab-runner-local gitlab-runner register \
		--non-interactive \
		--url "http://host.docker.internal:8929" \
		--token "$(GITLAB_RUNNER_TOKEN)" \
		--executor docker \
		--docker-image alpine:latest \
		--docker-privileged \
		--docker-network-mode host

## GitLab 파이프라인으로 배포된 dev-gitlab hello-service를 http://localhost:8083 로 연다.
apps-forward-dev-gitlab:
	kubectl port-forward svc/hello-service-dev-gitlab -n hello-dev-gitlab 8083:80
