.PHONY: up status provision ping destroy reload sync-keys registry-test registry-smoke app-test jenkins-url jenkins-logs jenkins-status rollback image-tags deployed-images discord-test

up:
	vagrant up

status:
	vagrant status

sync-keys:
	./scripts/sync-vagrant-keys.sh

ping:
	ansible all -i ansible/inventory.ini -m ping

provision:
	ansible-playbook -i ansible/inventory.ini ansible/site.yml

reload:
	vagrant reload

destroy:
	vagrant destroy -f

registry-test:
	curl -fsS http://192.168.56.14:5000/v2/_catalog

registry-smoke:
	ansible cicd -i ansible/inventory.ini -m shell -a "docker pull busybox:latest && docker tag busybox:latest 192.168.56.14:5000/test-busybox:latest && docker push 192.168.56.14:5000/test-busybox:latest"
	ansible app -i ansible/inventory.ini -m shell -a "docker pull 192.168.56.14:5000/test-busybox:latest"
	curl -fsS http://192.168.56.14:5000/v2/_catalog

app-test:
	./scripts/healthcheck.sh

jenkins-url:
	@echo "Jenkins: http://192.168.56.14:8080"
	@echo "Login: admin"
	@echo "Password: admin"

jenkins-logs:
	ansible cicd -i ansible/inventory.ini -m shell -a "docker logs --tail=100 automation-jenkins"

jenkins-status:
	ansible cicd -i ansible/inventory.ini -m shell -a "docker ps --filter name=automation-jenkins"

image-tags:
	curl -fsS http://192.168.56.14:5000/v2/automation-backend/tags/list
	@echo
	curl -fsS http://192.168.56.14:5000/v2/automation-frontend/tags/list
	@echo

deployed-images:
	ansible app -i ansible/inventory.ini -m shell -a "{% raw %}docker ps --filter name=automation-backend --format '{{.Names}} {{.Image}} {{.Status}}'{% endraw %}"
	ansible web -i ansible/inventory.ini -m shell -a "{% raw %}docker ps --filter name=automation-frontend --format '{{.Names}} {{.Image}} {{.Status}}'{% endraw %}"

rollback:
	@if [ -z "$(VERSION)" ]; then echo "Usage: make rollback VERSION=<tag>"; exit 1; fi
	ansible-playbook -i ansible/inventory.ini ansible/rollback.yml -e image_tag=$(VERSION)
	$(MAKE) app-test

discord-test:
	./scripts/notify-discord.sh "Automation Alchemy Discord notification test"