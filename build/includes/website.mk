# Copyright 2018 Google LLC All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


#  __        __   _         _ _
#  \ \      / /__| |__  ___(_) |_ ___
#   \ \ /\ / / _ \ '_ \/ __| | __/ _ \
#    \ V  V /  __/ |_) \__ \ | |_  __/
#     \_/\_/ \___|_.__/|___/_|\__\___|
#

#
# Website targets
#

# generate the latest website
site-server: ARGS ?=-F
site-server: ENV ?= RELEASE_VERSION="$(base_version)" RELEASE_BRANCH=master
site-server: ensure-build-image
	docker run --rm $(common_mounts) --workdir=$(mount_path)/site $(DOCKER_RUN_ARGS) -p 1313:1313 $(build_tag) bash -c \
	"$(ENV) hugo server --watch --baseURL=http://localhost:1313/ --bind=0.0.0.0 $(ARGS)"

site-static: ensure-build-image
	-docker run --rm $(common_mounts) --workdir=$(mount_path)/site $(DOCKER_RUN_ARGS) $(build_tag) rm -r ./public
	-mkdir $(agones_path)/site/public
	# for some reason, this only work locally
	docker run --rm $(common_mounts) --workdir=$(mount_path)/site $(DOCKER_RUN_ARGS) $(build_tag) \
		bash -c "npm list postcss-cli || npm install postcss-cli"
	docker run --rm $(common_mounts) --workdir=$(mount_path)/site $(DOCKER_RUN_ARGS) $(build_tag) \
		bash -c "npm list autoprefixer || npm install autoprefixer"
	docker run --rm $(common_mounts) --workdir=$(mount_path)/site $(DOCKER_RUN_ARGS) $(build_tag) bash -c \
		"$(ENV) hugo --config=config.toml $(ARGS)"

site-gen-app-yaml: SERVICE ?= default
site-gen-app-yaml:
	docker run --rm $(common_mounts) --workdir=$(mount_path)/site $(DOCKER_RUN_ARGS) $(build_tag) bash -c \
			"SERVICE=$(SERVICE) envsubst < app.yaml > .app.yaml"

site-deploy: site-gen-app-yaml site-static
	docker run -t --rm $(common_mounts) --workdir=$(mount_path) $(DOCKER_RUN_ARGS) \
	-e GO111MODULE=on -e SHORT_SHA=$(shell git rev-parse --short=7 HEAD) $(build_tag) bash -c \
	'printenv && cd  ./site && \
    gcloud app deploy .app.yaml --no-promote --quiet --version=$$SHORT_SHA'

site-static-preview:
	$(MAKE) site-static ARGS="-F" ENV="RELEASE_VERSION=$(base_version) RELEASE_BRANCH=master"

site-deploy-preview: site-static-preview
	$(MAKE) site-deploy SERVICE=preview

hugo-test: site-static-preview
	for i in {1..5}; \
		do echo "Html Test: Attempt $$i" && \
		  docker run --rm -t -e "TERM=xterm-256color" $(common_mounts) $(DOCKER_RUN_ARGS) $(build_tag) bash -c \
			"mkdir -p /tmp/website && cp -r $(mount_path)/site/public /tmp/website/site && htmltest -c $(mount_path)/site/htmltest.yaml /tmp/website" && \
	break || sleep 60; done

site-test:
	# generate actual html and run test against - provides a more accurate tests
	$(MAKE) test-gen-api-docs
	$(MAKE) hugo-test

# generate site images, if they don't exist
site-images: $(site_path)/static/diagrams/gameserver-states.dot.png $(site_path)/static/diagrams/gameserver-lifecycle.puml.png $(site_path)/static/diagrams/gameserver-reserved.puml.png

# generate pngs from dot files
%.dot.png: %.dot
	docker run -i --rm $(common_mounts) $(DOCKER_RUN_ARGS) $(build_tag) bash -c \
	  'dot -Tpng /dev/stdin' < $< > $@.tmp && mv $@.tmp $@

# general pngs from puml files
%.puml.png: %.puml
	docker run -i --rm $(common_mounts) $(DOCKER_RUN_ARGS) $(build_tag) bash -c \
		'plantuml -pipe' < $< > $@

# Path to a file and docker command
REL_PATH := content/en/docs/Reference/agones_crd_api_reference.html
GEN_API_DOCS := docker run -e FILE="$(mount_path)/site/$(REL_PATH)" -e VERSION=${base_version} --rm -i $(common_mounts) $(build_tag) bash -c "/go/src/agones.dev/agones/site/gen-api-docs.sh"

# generate Agones CRD reference docs
gen-api-docs: ensure-build-image
	$(GEN_API_DOCS)

# test generated Agones CRD reference docs
test-gen-api-docs: expected_docs := $(site_path)/$(REL_PATH)
test-gen-api-docs: ensure-build-image
	cp $(expected_docs) /tmp/generated.html
	sort /tmp/generated.html > /tmp/generated.html.sorted
	$(GEN_API_DOCS)
	sort $(expected_docs) > /tmp/result.sorted
	diff -bB /tmp/result.sorted /tmp/generated.html.sorted