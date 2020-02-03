SHELL := bash
PYTHON_NAME = "rhasspyvoltron"
SERVICE_NAME = "rhasspy-voltron"
RHASSPY_DIRS = $(shell cat RHASSPY_DIRS)
REQUIREMENTS = $(shell find . -mindepth 2 -maxdepth 2 -type f -name requirements.txt)
REQUIREMENTS_DEV = $(shell find . -mindepth 2 -maxdepth 2 -type f -name requirements_dev.txt)
PYTHON_FILES = **/*.py
PIP_INSTALL ?= install
DOWNLOAD_DIR = download

.PHONY: venv update-bin install-kaldi dist sdist debian pyinstaller docker-alsa docker-pulseaudio docker-downloads

version := $(shell cat VERSION)
architecture := $(shell bash architecture.sh)

debian_package := $(SERVICE_NAME)_$(version)_$(architecture)
debian_dir := debian/$(debian_package)

# -----------------------------------------------------------------------------
# Python
# -----------------------------------------------------------------------------

reformat:
	black .
	isort $(PYTHON_FILES)

check:
	flake8 $(PYTHON_FILES)
	pylint $(PYTHON_FILES)
	mypy $(PYTHON_FILES)
	black --check .
	isort --check-only $(PYTHON_FILES)
	yamllint .
	pip list --outdated

# Gather non-Rhasspy requirements from all submodules.
# Rhasspy libraries will be used from the submodule source code.
requirements.txt: $(REQUIREMENTS)
	cat $^ | grep -v '^rhasspy' | sort | uniq > $@

# Gather development requirements from all submodules.
requirements_dev.txt: $(REQUIREMENTS_DEV)
	cat $^ | grep -v '^-e' | sort | uniq > $@

# Create virtual environment and install all (non-Rhasspy) dependencies.
venv: requirements.txt snowboy-1.3.0.tar.gz update-bin
	rm -rf .venv/
	python3 -m venv .venv
	.venv/bin/pip3 $(PIP_INSTALL) wheel setuptools
	.venv/bin/pip3 $(PIP_INSTALL) -r requirements.txt
	.venv/bin/pip3 $(PIP_INSTALL) $(DOWNLOAD_DIR)/snowboy-1.3.0.tar.gz
	.venv/bin/pip3 $(PIP_INSTALL) -r requirements_dev.txt

# Copy submodule scripts to shared bin directory.
update-bin:
	$(shell find . -mindepth 3 -maxdepth 3 -type f -name 'rhasspy-*' -path '*/bin/*' -exec cp '{}' bin/ \;)
	chmod +x bin/*

# Build and copy Vue web artifacts to web directory.
update-web:
	rm -rf web
	cd rhasspy-web-vue && make && mv dist ../web

# Build Python Kaldi nnet3 extension.
# Requires you to put the path to your Kaldi installation in a file named
# rhasspy-asr-kaldi/kaldiroot.
install-kaldi: rhasspy-asr-kaldi/kaldiroot
	cd rhasspy-asr-kaldi && ../.venv/bin/python3 kaldi_setup.py install

# Create source/binary/debian distribution files
dist: sdist debian

# Create source distribution
sdist:
	python3 setup.py sdist

# -----------------------------------------------------------------------------
# Docker
# -----------------------------------------------------------------------------

docker-downloads: $(DOWNLOAD_DIR)/snowboy-1.3.0.tar.gz $(DOWNLOAD_DIR)/kaldi-2019-$(architecture).tar.gz $(DOWNLOAD_DIR)/kaldi-2019.tar.gz $(DOWNLOAD_DIR)/mitlm-0.4.2-$(architecture).tar.gz $(DOWNLOAD_DIR)/phonetisaurus-2019-$(architecture).tar.gz $(DOWNLOAD_DIR)/pocketsphinx-python.tar.gz $(DOWNLOAD_DIR)/openfst-1.6.7.tar.gz

# Build ALSA Docker image.
docker-alsa: docker-downloads
	docker build . -f Dockerfile.source.alsa \
    -t "rhasspy/$(SERVICE_NAME):$(version)" \
    -t "rhasspy/$(SERVICE_NAME):latest"

# Build PulseAudio Docker image.
docker-pulseaudio: docker-downloads
	docker build . -f Dockerfile.source.pulseaudio \
    -t "rhasspy/$(SERVICE_NAME):$(version)-pulseaudio" \
    -t "rhasspy/$(SERVICE_NAME):latest-pulseaudio"

# -----------------------------------------------------------------------------
# Debian
# -----------------------------------------------------------------------------

pyinstaller:
	mkdir -p dist
	pyinstaller -y --workpath pyinstaller/build --distpath pyinstaller/dist $(PYTHON_NAME).spec
	tar -C pyinstaller/dist -czf dist/$(SERVICE_NAME)_$(version)_$(architecture).tar.gz rhasspyvoltron/

debian: pyinstaller
	mkdir -p dist
	rm -rf "$(debian_dir)"
	mkdir -p "$(debian_dir)/DEBIAN" "$(debian_dir)/usr/bin" "$(debian_dir)/usr/lib"
	cat debian/DEBIAN/control | version=$(version) architecture=$(architecture) envsubst > "$(debian_dir)/DEBIAN/control"
	cp debian/bin/* "$(debian_dir)/usr/bin/"
	cp -R pyinstaller/dist/$(PYTHON_NAME) "$(debian_dir)/usr/lib/"
	cd debian/ && fakeroot dpkg --build "$(debian_package)"
	mv "debian/$(debian_package).deb" dist/


# -----------------------------------------------------------------------------
# Downloads
# -----------------------------------------------------------------------------

# Download snowboy.
$(DOWNLOAD_DIR)/snowboy-1.3.0.tar.gz:
	curl -sSfL -o $@ 'https://github.com/Kitt-AI/snowboy/archive/v1.3.0.tar.gz'

# Download pre-built Kaldi binaries.
$(DOWNLOAD_DIR)/kaldi-2019-$(architecture).tar.gz:
	curl -sSfL -o $@ "https://github.com/synesthesiam/docker-kaldi/releases/download/v2019.1/kaldi-2019-$(architecture).tar.gz"

# Download Kaldi source code.
$(DOWNLOAD_DIR)/kaldi-2019.tar.gz:
	curl -sSfL -o $@ 'https://github.com/synesthesiam/docker-kaldi/raw/master/download/kaldi-2019.tar.gz'

# Download OpenFST source code.
$(DOWNLOAD_DIR)/openfst-1.6.7.tar.gz:
	curl -sSfL -o $@ 'http://openfst.org/twiki/pub/FST/FstDownload/openfst-1.6.7.tar.gz'

# Download pre-built MITLM binaries.
$(DOWNLOAD_DIR)/mitlm-0.4.2-$(architecture).tar.gz:
	curl -sSfL -o $@ "https://github.com/synesthesiam/docker-mitlm/releases/download/v0.4.2/mitlm-0.4.2-$(architecture).tar.gz"

# Download pre-built Phonetisaurus binaries.
$(DOWNLOAD_DIR)/phonetisaurus-2019-$(architecture).tar.gz:
	curl -sSfL -o $@ "https://github.com/synesthesiam/docker-phonetisaurus/releases/download/v2019.1/phonetisaurus-2019-$(architecture).tar.gz"

# Download Python Pocketsphinx library with no dependency on PulseAudio.
$(DOWNLOAD_DIR)/pocketsphinx-python.tar.gz:
	curl -sSfL -o $@ 'https://github.com/synesthesiam/pocketsphinx-python/releases/download/v1.0/pocketsphinx-python.tar.gz'
