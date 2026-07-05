include properties.mk

SUPPORTED_DEVICES_LIST = $(shell sed -n -e 's/<iq:product id="\(.*\)"\/>/\1/p' manifest-app.xml)
SOURCES = $(shell find source -name '[^.]*.mc')
RESFILES = $(shell find resources* -name '[^.]*.xml')
APPNAME = $(shell grep entry manifest-app.xml | sed 's/.*entry="\([^"]*\).*/\1/' | sed 's/App$$//')
SIMULATOR = LD_LIBRARY_PATH="$(SDK_HOME)/bin" "$(SDK_HOME)/bin/connectiq"
MONKEYC = "$(SDK_HOME)/bin/monkeyc"
MONKEYDO = "$(SDK_HOME)/bin/monkeydo"

.PHONY: all build buildall deploy run test sim simcheck package package-app package-widget clean

all: build monkey.jungle

clean:
	@rm -fr bin manifest-widget.xml
	@find . -name '*~' -print0 | xargs -0 rm -f

build: bin/$(APPNAME)-$(DEVICE).prg bin/$(APPNAME)-widget-$(DEVICE).prg

buildall: $(foreach device,$(SUPPORTED_DEVICES_LIST),\
	bin/$(APPNAME)-$(device).prg bin/$(APPNAME)-widget-$(device).prg)

# monkeyc drops scratch files with fixed names (internal-mir/, external-mir/,
# gen/) into the --output directory, so concurrent compiles sharing bin/
# corrupt each other. Each target therefore builds in its own work dir and
# the artifacts are moved into place afterwards — this is what makes
# `make -j buildall` safe.
#
# Both pattern rules match bin/$(APPNAME)-widget-<device>.prg; make
# resolves the ambiguity by picking the rule with the shorter stem,
# i.e. the widget rule.
bin/$(APPNAME)-widget-%.prg: $(SOURCES) $(RESFILES) manifest-widget.xml
	@mkdir -p bin/work/$(@F)
	$(MONKEYC) --warn -l 2 --output bin/work/$(@F)/$(@F) \
	-f 'monkey-base.jungleinc;monkey-widget.jungleinc' \
	-y $(PRIVATE_KEY) \
	-d $*
	@mv bin/work/$(@F)/$(@F) $@
	-@mv bin/work/$(@F)/$(@F).debug.xml bin/ 2>/dev/null
	@rm -rf bin/work/$(@F)

bin/$(APPNAME)-%.prg: $(SOURCES) $(RESFILES) manifest-app.xml
	@mkdir -p bin/work/$(@F)
	$(MONKEYC) --warn -l 2 --output bin/work/$(@F)/$(@F) \
	-f 'monkey-base.jungleinc;monkey-app.jungleinc' \
	-y $(PRIVATE_KEY) \
	-d $*
	@mv bin/work/$(@F)/$(@F) $@
	-@mv bin/work/$(@F)/$(@F).debug.xml bin/ 2>/dev/null
	@rm -rf bin/work/$(@F)

bin/$(APPNAME)-$(DEVICE)-test.prg: $(SOURCES) $(RESFILES) manifest-app.xml
	@mkdir -p bin/work/$(@F)
	$(MONKEYC) --warn -l 2 --output bin/work/$(@F)/$(@F) \
	-f 'monkey-base.jungleinc;monkey-app.jungleinc' \
	-y $(PRIVATE_KEY) \
	--unit-test \
	-d $(DEVICE)
	@mv bin/work/$(@F)/$(@F) $@
	-@mv bin/work/$(@F)/$(@F).debug.xml bin/ 2>/dev/null
	@rm -rf bin/work/$(@F)

sim:
	@pgrep -f "$(SDK_HOME)/bin/simulator" >/dev/null 2>&1 || ( $(SIMULATOR) & sleep 3 )

run: sim bin/$(APPNAME)-$(DEVICE).prg
	$(MONKEYDO) bin/$(APPNAME)-$(DEVICE).prg $(DEVICE) &

test: sim bin/$(APPNAME)-$(DEVICE)-test.prg
	$(MONKEYDO) bin/$(APPNAME)-$(DEVICE)-test.prg $(DEVICE) -t

# Headless smoke test: boot the compiled app in the simulator (under the
# monkey-run FHS sandbox), confirm it loads/runs on $(DEVICE), and save a
# screenshot to bin/simcheck-$(DEVICE)/$(DEVICE).png. Needs the devShell's
# ciq-simcheck: run as `nix develop -c make simcheck DEVICE=...`.
simcheck: bin/$(APPNAME)-$(DEVICE).prg
	ciq-simcheck bin/$(APPNAME)-$(DEVICE).prg $(DEVICE) bin/simcheck-$(DEVICE)

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
	$(MONKEYC) --warn -l 2 -e --output bin/$(APPNAME)-app.iq -f 'monkey-base.jungleinc;monkey-app.jungleinc' \
	-y $(PRIVATE_KEY) -r

package-widget: manifest-widget.xml
	$(MONKEYC) --warn -l 2 -e --output bin/$(APPNAME)-widget.iq -f 'monkey-base.jungleinc;monkey-widget.jungleinc' \
	-y $(PRIVATE_KEY) -r

monkey.jungle: monkey-app.jungleinc monkey-base.jungleinc
	cat monkey-app.jungleinc monkey-base.jungleinc > monkey.jungle
