CLUSTER_NAME := devops-study

.PHONY: up down status argocd-password argocd-forward apps-forward-dev apps-forward-prod

## kind 클러스터를 만들고 ArgoCD + 프로젝트 + root Application까지 한 번에 올린다.
up:
	kind create cluster --config infra/local/kind-config.yaml
	kubectl create namespace argocd
	helm repo add argo https://argoproj.github.io/argo-helm --force-update
	helm repo update
	helm install argocd argo/argo-cd --version 7.7.7 --namespace argocd --wait
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
