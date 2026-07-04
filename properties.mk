# Machine-specific overrides (gitignored, optional)
-include properties.local.mk

DEVICE ?= marqadventurer
ifeq ($(shell uname -s),Darwin)
SDK_HOME ?= $(shell cat $(HOME)/Library/Application\ Support/Garmin/ConnectIQ/current-sdk.cfg)
else
SDK_HOME ?= $(shell cat $(HOME)/.Garmin/ConnectIQ/current-sdk.cfg)
endif
DEPLOY ?= $(HOME)
PRIVATE_KEY ?= $(HOME)/.id_rsa_garmin.der
