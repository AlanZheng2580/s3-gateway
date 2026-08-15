.DEFAULT_GOAL := help

.PHONY: help validate up status test logs apply-policies down reset

help:
	@echo "Mock WEKA S3 Lab commands:"
	@echo "  make validate         Validate Compose and POSIX shell syntax"
	@echo "  make up               Start and provision the lab"
	@echo "  make status           Show service status"
	@echo "  make test             Run the complete acceptance test"
	@echo "  make logs             Follow MinIO and VersityGW logs"
	@echo "  make apply-policies   Reapply the VersityGW bucket policies"
	@echo "  make down             Stop containers without deleting data"
	@echo "  make reset            Stop containers and DELETE all lab volumes"

validate:
	docker compose config --quiet
	sh -n scripts/provision-minio.sh \
		scripts/provision-versitygw-users.sh \
		scripts/provision-versitygw-policies.sh \
		test-flow.sh

up:
	docker compose up -d

status:
	docker compose ps -a

test:
	./test-flow.sh

logs:
	docker compose logs -f minio versitygw

apply-policies:
	docker compose run --rm -T versitygw-policy-provisioner

down:
	docker compose down

reset:
	@echo "WARNING: deleting mock bucket data, IAM state, and all named volumes"
	docker compose down -v
