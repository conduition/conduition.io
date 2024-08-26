.PHONY: build
build:
	npx hexo generate

.PHONY: deploy
deploy: clean build
	npx hexo deploy

.PHONY: server
server:
	npx hexo server --draft

.PHONY: clean
clean:
	npx hexo clean
