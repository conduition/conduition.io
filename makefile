.PHONY: build
build:
	hexo generate

.PHONY: deploy
deploy: clean build
	hexo deploy

.PHONY: server
server:
	hexo server --draft

.PHONY: clean
clean:
	hexo clean
