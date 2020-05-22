# Top level makefile, the real shit is at src/Makefile

default: all

.DEFAULT:
	cd src && $(MAKE) $@

install:
	cd src && $(MAKE) $@

# unit tests
CRDT_UNIT_TESTS=test-vc
crdt-ut:
	cd src && $(MAKE) $(CRDT_UNIT_TESTS)
.PHONY: crdt-ut

SDS_UNIT_TESTS=test-sds
sds-ut:
	cd src && $(MAKE) $(SDS_UNIT_TESTS)
.PHONY: sds-ut

.PHONY: install