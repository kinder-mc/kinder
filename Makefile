# DO NOT CHANGE THIS FILE!
# If you want to change the Makefile, edit Makefile.in instead

# Makefile.  Generated from Makefile.in by configure.

LOCAL_BINDIR=$(CURDIR)/bin
LOCAL_DOCDIR=$(CURDIR)/doc

package=kind2
version=0.1
tarname=kind2
distdir=$(tarname)-$(version).`date +%Y.%m.%d`

prefix=/usr/local
exec_prefix=${prefix}
bindir=${exec_prefix}/bin


all: kind2

.PHONY: ocamlczmq kind2 kind2-prof kind2-top kind2-doc 

ocamlczmq: 
	cd ocamlczmq && ./build.sh

kind2: 
	make -C src
	mkdir -p $(LOCAL_BINDIR)
	cp -f src/_build/kind2.native $(LOCAL_BINDIR)/kind2

kind2-prof: 
	make -C src kind2-prof
	mkdir -p $(LOCAL_BINDIR)
	cp -f src/_build/kind2.native $(LOCAL_BINDIR)/kind2-prof

kind2-top: 
	make -C src kind2-top
	mkdir -p $(LOCAL_BINDIR)
	cp -f src/_build/kind2.top $(LOCAL_BINDIR)/kind2-top

kind2-doc: 
	make -C src kind2-doc
	mkdir -p $(LOCAL_DOCDIR)
	cp -Rf src/_build/kind2.docdir/* $(LOCAL_DOCDIR)

.PHONY: install clean-kind2 clean-ocamlczmq clean 

install: 
	mkdir -p ${bindir}
	for i in $(LOCAL_BINDIR)/*; do install -m 0755 $$i ${bindir}; done

clean-kind2:
	make -C src clean

clean-ocamlczmq:
	make -C ocamlczmq clean

clean: clean-kind2 clean-ocamlczmq


# Remake this Makefile if configuration has changed 
Makefile: Makefile.in ./config.status
	./config.status

./config.status: ./configure
	./config.status --recheck

