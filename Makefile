SHELL = /bin/sh
VERSION = 1.38
IGNORE = ~|CVS|var/|smokeping-$(VERSION)/smokeping-$(VERSION)|cvsignore|rej|orig|DEAD
GROFF = groff
.PHONY: man html txt ref examples check-examples patch killdoc doc tar
.SUFFIXES:
.SUFFIXES: .pm .pod .txt .html .man .1

POD := $(wildcard doc/*.pod)
PM :=  lib/ISG/ParseConfig.pm lib/Smokeping.pm 
PODPROBE :=  $(wildcard lib/Smokeping/probes/*.pm)
PODMATCH :=  $(wildcard lib/Smokeping/matchers/*.pm)

BASE = $(subst .pod,,$(POD)) \
	$(subst .pm,,$(subst lib/,doc/,$(PM))) \
	$(subst .pm,,$(subst lib/Smokeping/probes,doc/probes,$(PODPROBE))) \
	$(addprefix doc/matchers/,$(subst .pm,,$(notdir $(PODMATCH)))) \
	doc/smokeping
MAN = $(addsuffix .1,$(BASE))
TXT = $(addsuffix .txt,$(BASE))
HTML= $(addsuffix .html,$(BASE))

POD2MAN = pod2man --release=$(VERSION) --center=SmokePing $<  > $@
POD2HTML= cd doc ; pod2html --infile=../$< --outfile=../$@ --noindex --htmlroot=. --podroot=. --podpath=. --title=$*
# we go to this trouble to ensure that MAKEPOD only uses modules in the installation directory
MAKEPOD= perl -Ilib -I/usr/pack/rrdtool-1.0.47-to/lib/perl -mSmokeping -e 'Smokeping::main()' -- --makepod
GENEX= perl -Ilib -I/usr/pack/rrdtool-1.0.47-to/lib/perl -mSmokeping -e 'Smokeping::main()' -- --gen-examples

doc/%.1: doc/%.pod
	$(POD2MAN)
doc/%.1: lib/%.pm
	$(POD2MAN)
doc/probes/%.pod: lib/Smokeping/probes/%.pm
	$(MAKEPOD) Smokeping::probes::$* > $@
doc/probes/%.1: doc/probes/%.pod
	$(POD2MAN)
doc/matchers/%.1: lib/Smokeping/matchers/%.pm
	$(POD2MAN)
doc/ISG/%.1: lib/Smokeping/ISG/%
	$(POD2MAN)
doc/smokeping.1: bin/smokeping.dist
	$(POD2MAN)

doc/%.html: doc/%.pod
	$(POD2HTML)
doc/%.html: lib/%.pm
	$(POD2HTML)
doc/probes/%.html: doc/probes/%.pod
	$(POD2HTML)
doc/matchers/%.html: lib/Smokeping/matchers/%.pm
	$(POD2HTML)
doc/ISG/%.html: lib/Smokeping/ISG/%
	$(POD2MAN)

doc/smokeping.html: bin/smokeping.dist
	$(POD2MAN)

doc/%.txt: doc/%.1
	$(GROFF) -man -Tascii $< > $@
doc/matchers/%.txt: doc/matchers/%.1
	$(GROFF) -man -Tascii $< > $@
doc/probes/%.txt: doc/probes/%.1
	$(GROFF) -man -Tascii $< > $@

man: $(MAN)

html: $(HTML)

txt: $(TXT)

ref: doc/smokeping_config.pod

examples:
	$(GENEX)

check-examples:
	$(GENEX) --check

doc/smokeping_config.pod: lib/Smokeping.pm
	$(MAKEPOD) > $@
doc/smokeping_examples.pod: lib/Smokeping/Examples.pm etc/config.dist
	$(GENEX)
patch:
	perl -i~ -p -e 's/VERSION="\d.*?"/VERSION="$(VERSION)"/' lib/Smokeping.pm 
	perl -i~ -p -e 's/Smokeping \d.*?;/Smokeping $(VERSION);/' bin/smokeping.dist htdocs/smokeping.cgi.dist

killdoc:
	-rm doc/*.1 doc/*.txt doc/*.html doc/probes/* doc/matchers/* doc/ISG/* doc/examples/*

doc:    killdoc ref man html txt examples

tar:	doc patch
	-ln -s . smokeping-$(VERSION)
	find smokeping-$(VERSION)/* -type f -follow -o -type l | egrep -v '$(IGNORE)' | gtar -T - -czvf smokeping-$(VERSION).tar.gz
	rm smokeping-$(VERSION)
	
dist:   tar
	mv smokeping-$(VERSION).tar.gz /home/oetiker/public_html/webtools/smokeping/pub/
	cp CHANGES /home/oetiker/public_html/webtools/smokeping/pub/CHANGES
