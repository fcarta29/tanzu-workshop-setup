build:
	TAG=`git rev-parse --short=8 HEAD`; \
	docker build --rm -f build-tanzu-workshop-setup.dockerfile -t fcarta29/build-tanzu-workshop-setup:$$TAG .; \
	docker tag fcarta29/build-tanzu-workshop-setup:$$TAG fcarta29/build-tanzu-workshop-setup:latest

clean:
	docker stop build-tanzu-workshop-setup
	docker rm build-tanzu-workshop-setup

rebuild: clean build

#ADD this back in with project examples are ready -v $$PWD/deploy:/deploy 
run:
	docker run --name build-tanzu-workshop-setup -v $$PWD/config/kube.conf:/root/.kube/config -td fcarta29/build-tanzu-workshop-setup:latest
	docker exec -it build-tanzu-workshop-setup bash -l

join:
	docker exec -it build-tanzu-workshop-setup bash -l
start:
	docker start build-tanzu-workshop-setup
stop:
	docker stop build-tanzu-workshop-setup

default: build
