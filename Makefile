include properties.mk

sources = $(shell find source -name '[^.]*.mc')
resources = $(shell find resources* -name '[^.]*.xml' | tr '\n' ':' | sed 's/.$$//')
resfiles = $(shell find resources* -name '[^.]*.xml')
appName = $(shell grep entry manifest.xml | sed 's/.*entry="\([^"]*\).*/\1/' | sed 's/App$$//')

FLAGS = -s 2.2.0 -w
MONKEYC = java -Dfile.encoding=UTF-8 -Dapple.awt.UIElement=true -jar $(SDK_HOME)/bin/monkeybrains.jar

.PHONY: build

all: build

clean:
	rm -f bin/$(appName).prg

build: bin/$(appName).prg $(resfiles)

bin/$(appName).prg: $(sources)
	$(MONKEYC) $(FLAGS) --warn --output bin/$(appName).prg -m manifest.xml \
	-z $(resources) \
	-y $(PRIVATE_KEY) \
	-d $(DEVICE) $(sources)

buildall:
	@for device in $(SUPPORTED_DEVICES_LIST); do \
		echo "-----"; \
		echo "Building for" $$device; \
    $(MONKEYC) $(FLAGS) --warn --output bin/$(appName)-$$device.prg -m manifest.xml \
    -z $(resources) \
    -y $(PRIVATE_KEY) \
    -d $$device $(sources); \
	done

run: build
	@$(SDK_HOME)/bin/connectiq &&\
	sleep 3 &&\
	$(SDK_HOME)/bin/monkeydo bin/$(appName).prg $(DEVICE)

deploy: build
	@cp bin/$(appName).prg $(DEPLOY)

package:
	@$(MONKEYC) $(FLAGS) --warn -e --output bin/$(appName).iq -m manifest.xml \
	-z $(resources) \
	-y $(PRIVATE_KEY) \
	$(sources) -r
