SHELL = /bin/sh
VERSION = 2.1.1
############ A is for features
############ B is for bugfixes
############ V.AAABBB
############ 2.000001
############ 2.000002
NUMVERSION = 2.001001
IGNORE = ~|CVS|var/|smokeping-$(VERSION)/smokeping-$(VERSION)|cvsignore|rej|orig|DEAD|pod2htm[di]\.tmp|\.svn|tar\.gz|DEADJOE
GROFF = groff
PERL = perl-5.8.8
.PHONY: man html txt ref examples check-examples patch killdoc doc tar rename-man symlinks remove-symlinks
.SUFFIXES:
.SUFFIXES: .pm .pod .txt .html .man .1 .3 .5 .7

DOCS = $(filter-out doc/smokeping_config.pod doc/smokeping.pod doc/smokeping.cgi.pod,$(wildcard doc/*.pod)) doc/smokeping_examples.pod # section 7
DOCSCONFIG := doc/smokeping_config.pod # section 5
PM :=  lib/Config/Grammar.pm lib/Smokeping.pm lib/Smokeping/Examples.pm lib/Smokeping/RRDtools.pm
PODPROBE :=  $(wildcard lib/Smokeping/probes/*.pm)
PODMATCH :=  $(wildcard lib/Smokeping/matchers/*.pm)
PODSORT :=  $(wildcard lib/Smokeping/sorters/*.pm)

DOCSBASE = $(subst .pod,,$(DOCS))
MODBASE = $(subst .pm,,$(subst lib/,doc/,$(PM))) \
	$(subst .pm,,$(subst lib/,doc/,$(PODPROBE))) \
	$(subst .pm,,$(subst lib/,doc/,$(PODMATCH))) \
	$(subst .pm,,$(subst lib/,doc/,$(PODSORT)))
PROGBASE = doc/smokeping doc/smokeping.cgi doc/tSmoke
DOCSCONFIGBASE = doc/smokeping_config

BASE = $(DOCSBASE) $(MODBASE) $(PROGBASE) $(DOCSCONFIGBASE)

MAN = $(addsuffix .3,$(MODBASE)) $(addsuffix .5,$(DOCSCONFIGBASE)) $(addsuffix .7,$(DOCSBASE)) $(addsuffix .1,$(PROGBASE))
TXT = $(addsuffix .txt,$(BASE))
HTML= $(addsuffix .html,$(BASE))

POD2MAN = pod2man --release=$(VERSION) --center=SmokePing $<
MAN2TXT = $(GROFF) -man -Tascii $< > $@
# pod2html apparently needs to be in the target directory to get L<> links right
POD2HTML= cd $(dir $@); top="$(shell echo $(dir $@)|sed -e 's,doc/,,' -e 's,[^/]*/,../,g' -e 's,/$$,,')"; top=$${top:-.}; pod2html --infile=$(CURDIR)/$< --noindex --htmlroot=. --podroot=. --podpath=$${top} --title=$* | $${top}/../util/fix-pod2html.pl > $(notdir $@)
# we go to this trouble to ensure that MAKEPOD only uses modules in the installation directory
MAKEPOD= $(PERL) -I/home/oetiker/lib/fake-perl/ -Ilib -I/usr/pack/rrdtool-1.2svn-to/lib/perl -mSmokeping -e 'Smokeping::main()' -- --makepod
GENEX= $(PERL) -I/home/oetiker/lib/fake-perl/ -Ilib -I/usr/pack/rrdtool-1.2svn-to/lib/perl -mSmokeping -e 'Smokeping::main()' -- --gen-examples

doc/%.7: doc/%.pod
	$(POD2MAN) --section 7 > $@
doc/%.5: doc/%.pod
	$(POD2MAN) --section 5 > $@

doc/Smokeping.3: lib/Smokeping.pm
	$(POD2MAN) --section 3 > $@
doc/Smokeping/Examples.3: lib/Smokeping/Examples.pm
	$(POD2MAN) --section 3 > $@
doc/Smokeping/RRDtools.3: lib/Smokeping/RRDtools.pm
	$(POD2MAN) --section 3 > $@

doc/Smokeping/probes/%.pod: lib/Smokeping/probes/%.pm
	$(MAKEPOD) Smokeping::probes::$* > $@

doc/Smokeping/probes/%.3: doc/Smokeping/probes/%.pod
	$(POD2MAN) --section 3 > $@
doc/Smokeping/matchers/%.3: lib/Smokeping/matchers/%.pm
	$(POD2MAN) --section 3 > $@
doc/Smokeping/sorters/%.3: lib/Smokeping/sorters/%.pm
	$(POD2MAN) --section 3 > $@
doc/Config/%.3: lib/Config/%.pm
	$(POD2MAN) --section 3 > $@
doc/smokeping.1: bin/smokeping.dist
	$(POD2MAN) --section 1 > $@
doc/smokeping.cgi.1: htdocs/smokeping.cgi.dist
	$(POD2MAN) --section 1 > $@
doc/tSmoke.1: bin/tSmoke.dist
	$(POD2MAN) --section 1 > $@

doc/%.html: doc/%.pod
	$(POD2HTML)
doc/Smokeping.html: lib/Smokeping.pm
	$(POD2HTML)
doc/Smokeping/Examples.html: lib/Smokeping/Examples.pm
	$(POD2HTML)
doc/Smokeping/RRDtools.html: lib/Smokeping/RRDtools.pm
	$(POD2HTML)

doc/Smokeping/matchers/%.html: lib/Smokeping/matchers/%.pm
	$(POD2HTML)
doc/Smokeping/sorters/%.html: lib/Smokeping/sorters/%.pm
	$(POD2HTML)
doc/Config/%.html: lib/Config/%.pm
	$(POD2HTML)
doc/smokeping.html: bin/smokeping.dist
	$(POD2HTML)
doc/smokeping.cgi.html: htdocs/smokeping.cgi.dist
	$(POD2HTML)
doc/tSmoke.html: bin/tSmoke.dist
	$(POD2HTML)

doc/%.txt: doc/%.1
	$(MAN2TXT)
doc/%.txt: doc/%.3
	$(MAN2TXT)
doc/%.txt: doc/%.5
	$(MAN2TXT)
doc/%.txt: doc/%.7
	$(MAN2TXT)

man: $(MAN)

html: symlinks $(HTML) remove-symlinks

txt: $(TXT)

rename-man: $(MAN)
	for j in probes matchers sorters; do \
	  for i in doc/Smokeping/$$j/*.3; do \
	    if echo $$i | grep Smokeping::$$j>/dev/null; then :; else \
	      mv $$i `echo $$i | sed s,$$j/,$$j/Smokeping::$$j::,`; \
	    fi; \
	  done; \
	done
	mv doc/Config/Grammar.3 doc/Config/Config::Grammar.3
	mv doc/Smokeping/Examples.3 doc/Smokeping/Smokeping::Examples.3
	mv doc/Smokeping/RRDtools.3 doc/Smokeping/Smokeping::RRDtools.3

ref: doc/smokeping_config.pod

symlinks:
	-ln -s bin/smokeping.dist doc/smokeping.pod
	-ln -s htdocs/smokeping.cgi.dist doc/smokeping.cgi.pod

remove-symlinks:
	-rm doc/smokeping.pod
	-rm doc/smokeping.cgi.pod

examples:
	$(GENEX)

check-examples:
	$(GENEX) --check

doc/smokeping_config.pod: lib/Smokeping.pm
	$(MAKEPOD) > $@
doc/smokeping_examples.pod: lib/Smokeping/Examples.pm etc/config.dist
	$(GENEX)
patch:
	$(PERL) -i~ -p -e 's/VERSION="\d.*?"/VERSION="$(NUMVERSION)"/' lib/Smokeping.pm 
	$(PERL) -i~ -p -e 's/Smokeping \d.*?;/Smokeping $(NUMVERSION);/' bin/smokeping.dist htdocs/smokeping.cgi.dist bin/tSmoke.dist
	$(PERL) -i~ -p -e 'do { my @d = localtime; my $$d = (1900+$$d[5])."/".(1+$$d[4])."/".$$d[3]; print "$$d -- released version $(VERSION)\n\n" } unless $$done++ || /version $(VERSION)/' CHANGES

killdoc:
	-rm doc/*.[1357] doc/*.txt doc/*.html doc/Smokeping/* doc/Smokeping/probes/* doc/Smokeping/matchers/* doc/Smokeping/sorters/* doc/Config/* doc/examples/* doc/smokeping_examples.pod doc/smokeping_config.pod doc/smokeping.pod doc/smokeping.cgi.pod

doc:    killdoc ref examples man html txt rename-man

# patch first so Smokeping.pm is older than smokeping_config.pod in the tarball
tar:	patch doc
	-ln -s . smokeping-$(VERSION)
	find smokeping-$(VERSION)/* -type f -follow -o -type l | egrep -v '$(IGNORE)' | tar -T - -czvf smokeping-$(VERSION).tar.gz
	rm smokeping-$(VERSION)

commit:
	svn commit -m "prepare for the release of smokeping-$(VERSION)"
	
dist:   tar commit
	scp CHANGES smokeping-$(VERSION).tar.gz oposs@oss.oetiker.ch:public_html/smokeping/pub/

tag:    dist
	svn ls svn://svn.ee.ethz.ch/smokeping/tags/$(VERSION) || \
	svn copy -m "tagging version $(VERSION)" svn://svn.ee.ethz.ch/smokeping/branches/2.0 svn://svn.ee.ethz.ch/smokeping/tags/$(VERSION)
