SHELL = /bin/sh
VERSION = 1.38
IGNORE = ~|CVS|var/|smokeping-$(VERSION)/smokeping-$(VERSION)|cvsignore|rej|orig|DEAD
GROFF = groff
.PHONY: man html txt ref examples check-examples patch killdoc doc tar
.SUFFIXES:
.SUFFIXES: .pm .pod .txt .html .man .1

POD := $(wildcard doc/*.pod)   lib/ISG/ParseConfig.pm \
        lib/Smokeping.pm 
PODPROBE :=  $(wildcard lib/probes/*.pm)
PODMATCH :=  $(wildcard lib/matchers/*.pm)

BASE = $(addprefix doc/,$(subst .pod,,$(notdir $(POD)))) $(subst .pm,,$(subst lib/probes,doc/probes,$(PODPROBE))) $(addprefix doc/matchers/,$(subst .pod,,$(notdir $(PODMATCH)))) doc/smokeping
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
doc/%.1: lib/%
	$(POD2MAN)
doc/probes/%.pod: lib/probes/%.pm
	$(MAKEPOD) probes::$* > $@
doc/probes/%.1: doc/probes/%.pod
	$(POD2MAN)
doc/matchers/%.1: lib/matchers/%
	$(POD2MAN)
doc/%.1: lib/ISG/%
	$(POD2MAN)
doc/smokeping.1: bin/smokeping.dist
	$(POD2MAN)

doc/%.html: doc/%.pod
	$(POD2HTML)
doc/%.html: lib/%
	$(POD2HTML)
doc/%.html: lib/ISG/%
	$(POD2HTML)
doc/probes/%.html: doc/probes/%.pod
	$(POD2HTML)
doc/matchers/%.html: lib/matchers/%
	$(POD2HTML)
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
	-rm doc/*.1 doc/*.txt doc/*.html

doc:    killdoc ref man html txt

tar:	doc patch
	-ln -s . smokeping-$(VERSION)
	find smokeping-$(VERSION)/* -type f -follow -o -type l | egrep -v '$(IGNORE)' | gtar -T - -czvf smokeping-$(VERSION).tar.gz
	rm smokeping-$(VERSION)
	
dist:   tar
	mv smokeping-$(VERSION).tar.gz /home/oetiker/public_html/webtools/smokeping/pub/
	cp CHANGES /home/oetiker/public_html/webtools/smokeping/pub/CHANGES
