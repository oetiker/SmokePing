SHELL = /bin/sh
VERSION = 1.38
IGNORE = ~|CVS|var/|smokeping-$(VERSION)/smokeping-$(VERSION)|cvsignore|rej|orig|DEAD
GROFF = groff
.PHONY: man html txt ref patch killdoc doc tar
.SUFFIXES:
.SUFFIXES: .pm .pod .txt .html .man .1

POD := doc/$(wildcard doc/*.pod)   lib/ISG/ParseConfig.pm \
        lib/Smokeping.pm 
PODPROBE :=  lib/probes/$(wildcard lib/probes/*.pm)
PODMATCH :=  lib/matchers/$(wildcard lib/matchers/*.pm)

BASE = $(addprefix doc/,$(subst .pod,,$(notdir $(POD))))  $(addprefix doc/probes/,$(subst .pod,,$(notdir $(PODPROBE)))) $(addprefix doc/matchers/,$(subst .pod,,$(notdir $(PODMATCH))))
MAN = $(addsuffix .1,$(BASE))
TXT = $(addsuffix .txt,$(BASE))
HTML= $(addsuffix .html,$(BASE))

POD2MAN = pod2man --release=$(VERSION) --center=SmokePing $<  > $@
POD2HTML= cd doc ; pod2html --infile=../$< --outfile=../$@ --noindex --htmlroot=. --podroot=. --podpath=. --title=$*
doc/%.1: doc/%.pod
	$(POD2MAN)
doc/%.1: lib/%
	$(POD2MAN)
doc/probes/%.1: lib/probes/%
	$(POD2MAN)
doc/matchers/%.1: lib/matchers/%
	$(POD2MAN)
doc/%.1: lib/ISG/%
	$(POD2MAN)

doc/%.html: doc/%.pod
	$(POD2HTML)
doc/%.html: lib/%
	$(POD2HTML)
doc/%.html: lib/ISG/%
	$(POD2HTML)
doc/probes/%.html: lib/probes/%
	$(POD2HTML)
doc/matchers/%.html: lib/matchers/%
	$(POD2HTML)

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

doc/smokeping_config.pod: lib/Smokeping.pm
	perl -Ilib -I/usr/pack/rrdtool-1.0.47-to/lib/perl -mSmokeping ./bin/smokeping.dist --makepod > doc/smokeping_config.pod
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
