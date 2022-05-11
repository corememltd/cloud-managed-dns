SHELL = /bin/sh
.DELETE_ON_ERROR:

VENDOR ?= coremem
PROJECT ?= cloud-managed-dns

COMMITID = $(shell git rev-parse --short HEAD | tr -d '\n')$(shell git diff-files --quiet || printf -- -dirty)

TERRAFORM_VERSION = 1.1.9
PACKER_VERSION = 1.8.0

define BUILD_FLAGS_template =
TERRAFORM_BUILD_FLAGS += -var $(1)=$(2)
PACKER_BUILD_FLAGS += -var $(1)=$(2)
endef
$(eval $(call BUILD_FLAGS_template,vendor,$(VENDOR)))
$(eval $(call BUILD_FLAGS_template,project,$(PROJECT)))
$(eval $(call BUILD_FLAGS_template,commit,$(COMMITID)))

KERNEL = $(shell uname -s | tr A-Z a-z)
MACHINE = $(shell uname -m)
ifeq ($(MACHINE),x86_64)
MACHINE = amd64
endif

CLEAN =
DISTCLEAN =

.PHONY: all
all:

.PHONY: clean
clean:
	rm -rf $(CLEAN)

.PHONY: distclean
distclean: clean
	rm -rf $(DISTCLEAN)

.PHONY: notdirty
notdirty:
ifneq ($(findstring -dirty,$(COMMITID)),)
ifeq ($(IDDQD),)
	@{ echo 'DIRTY DEPLOYS FORBIDDEN, REJECTING DEPLOY DUE TO UNCOMMITED CHANGES' >&2; git status; exit 1; }
else
	@echo 'DIRTY DEPLOY BUT GOD MODE ENABLED' >&2
endif
endif

.PHONY: deploy-authoritative
deploy-authoritative: setup.tf setup.tfvars id_rsa.pub .stamp.terraform
	./terraform apply $(TERRAFORM_BUILD_FLAGS) -var-file=setup.tfvars -auto-approve -target random_shuffle.zones
	./terraform $(if $(DRYRUN),plan,apply) $(TERRAFORM_BUILD_FLAGS) -var-file=setup.tfvars

.PHONY: undeploy-authoritative
undeploy-authoritative: PROTECT = azurerm_public_ip.ipv6 azurerm_public_ip.ipv4 azurerm_dns_zone.main
undeploy-authoritative: setup.tf setup.tfvars id_rsa.pub .stamp.terraform
	./terraform state rm $(PROTECT) 2>&- || true
	./terraform destroy $(TERRAFORM_BUILD_FLAGS) -var-file=setup.tfvars || true

id_rsa id_rsa.pub &:
	ssh-keygen -q -t rsa -N '' -f id_rsa
CLEAN += id_rsa id_rsa.pub

setup.tfvars account.json:
	@{ echo 'missing $@, create it as described in the README.md' >&2; exit 1; }

.stamp.terraform: setup.tf terraform
	./terraform init
	./terraform validate
	@touch $@
CLEAN += .stamp.terraform
DISTCLEAN += .terraform .terraform.lock.hcl

.PHONY: setup.pkr.hcl
setup.pkr.hcl: packer
	./$< validate $(PACKER_BUILD_FLAGS) $@

terraform_$(TERRAFORM_VERSION)_$(KERNEL)_$(MACHINE).zip:
	curl -f -O -J -L https://releases.hashicorp.com/terraform/$(TERRAFORM_VERSION)/$@
DISTCLEAN += $(wildcard terraform_*.zip)

terraform: terraform_$(TERRAFORM_VERSION)_$(KERNEL)_$(MACHINE).zip
	unzip -oDD $< $@
CLEAN += terraform

packer_$(PACKER_VERSION)_$(KERNEL)_$(MACHINE).zip:
	curl -f -O -J -L https://releases.hashicorp.com/packer/$(PACKER_VERSION)/$@
DISTCLEAN += $(wildcard packer_*.zip)

packer: packer_$(PACKER_VERSION)_$(KERNEL)_$(MACHINE).zip
	unzip -oDD $< $@
CLEAN += packer
