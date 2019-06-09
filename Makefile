# Top level makefile, the real shit is at src/Makefile

default: all

.DEFAULT:
	cd src && $(MAKE) $@

install:
	cd src && $(MAKE) $@

# unit tests
CRDT_UNIT_TESTS=test-vc test-crdt-common
crdt-ut:
	cd src && $(MAKE) $(CRDT_UNIT_TESTS)
.PHONY: crdt-ut

.PHONY: install
