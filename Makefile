include properties.mk

SUPPORTED_DEVICES_LIST = $(shell sed -n -e 's/<iq:product id="\(.*\)"\/>/\1/p' manifest-app.xml)
SOURCES = $(shell find source -name '[^.]*.mc')
RESFILES = $(shell find resources* -name '[^.]*.xml')
APPNAME = $(shell grep entry manifest-app.xml | sed 's/.*entry="\([^"]*\).*/\1/' | sed 's/App$$//')
SIMULATOR = LD_LIBRARY_PATH=$(SDK_HOME)/bin $(SDK_HOME)/bin/connectiq
MONKEYC = $(SDK_HOME)/bin/monkeyc

.PHONY: build deploy buildall run package clean sim package-widget package-app

all: build

clean:
	@rm -fr bin
	@find . -name '*~' -print0 | xargs -0 rm -f

build: bin/$(APPNAME)-$(DEVICE).prg bin/$(APPNAME)-widget-$(DEVICE).prg

bin/$(APPNAME)-$(DEVICE).prg: $(SOURCES) $(RESFILES) manifest-app.xml
	$(MONKEYC) --warn --output bin/$(APPNAME)-$(DEVICE).prg \
	-f 'monkey-base.jungle;monkey-app.jungle' \
	-y $(PRIVATE_KEY) \
	-d $(DEVICE)

bin/$(APPNAME)-widget-$(DEVICE).prg: $(SOURCES) $(RESFILES) manifest-widget.xml
	$(MONKEYC) --warn --output bin/$(APPNAME)-widget-$(DEVICE).prg \
	-f 'monkey-base.jungle;monkey-widget.jungle' \
	-y $(PRIVATE_KEY) \
	-d $(DEVICE)

bin/$(APPNAME)-$(DEVICE)-test.prg: $(SOURCES) $(RESFILES)
	$(MONKEYC) --warn --output bin/$(APPNAME)-$(DEVICE)-test.prg \
	-f 'monkey-base.jungle;monkey-app.jungle' \
	-y $(PRIVATE_KEY) \
	--unit-test \
	-d $(DEVICE)

buildall:
	@for device in $(SUPPORTED_DEVICES_LIST); do \
		echo "-----"; \
		echo "Building for" $$device; \
		$(MONKEYC) --warn --output bin/$(APPNAME)-$$device.prg \
			   -f 'monkey-base.jungle;monkey-app.jungle' \
			   -y $(PRIVATE_KEY) \
                           -d $$device; \
	done

sim:
	@pidof 'simulator*' &>/dev/null || ( $(SIMULATOR) & sleep 3 )

run: sim bin/$(APPNAME)-$(DEVICE).prg
	$(SDK_HOME)/bin/monkeydo bin/$(APPNAME)-$(DEVICE).prg $(DEVICE) &

test: sim bin/$(APPNAME)-$(DEVICE)-test.prg
	$(SDK_HOME)/bin/monkeydo bin/$(APPNAME)-$(DEVICE)-test.prg $(DEVICE) -t

$(DEPLOY)/$(APPNAME).prg: bin/$(APPNAME)-$(DEVICE).prg
	@cp bin/$(APPNAME)-$(DEVICE).prg $(DEPLOY)/$(APPNAME).prg
	@touch $(DEPLOY)/LOGS/76963622.TXT

$(DEPLOY)/$(APPNAME)-widget.prg: bin/$(APPNAME)-widget-$(DEVICE).prg
	@cp bin/$(APPNAME)-widget-$(DEVICE).prg $(DEPLOY)/$(APPNAME)-widget.prg
	@touch $(DEPLOY)/LOGS/76A74803.TXT

deploy: build $(DEPLOY)/$(APPNAME).prg $(DEPLOY)/$(APPNAME)-widget.prg

manifest-widget.xml: manifest-app.xml
	sed -e 's/watch-app/widget/g;s/9B0A09CFC89E4F7CA5E4AB21400EE424/B5FD4C5FE0F848E88A03E37E86971CEB/g' < manifest-app.xml > manifest-widget.xml

package: package-app package-widget

package-app:
	$(MONKEYC) --warn -e --output bin/$(APPNAME)-app.iq -f 'monkey-base.jungle;monkey-app.jungle' \
	-y $(PRIVATE_KEY) -r

package-widget: manifest-widget.xml
	@$(MONKEYC) --warn -e --output bin/$(APPNAME)-widget.iq -f 'monkey-base.jungle;monkey-widget.jungle' \
	-y $(PRIVATE_KEY) -r
