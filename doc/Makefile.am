# Copyright (C) 2011 Tobias Oetiker
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.


AUTOMAKE_OPTIONS =  foreign

# section 7

DOCS = smokeping_extend.pod smokeping_install.pod smokeping_master_slave.pod  smokeping_upgrade.pod

# section 5
DOCSCONFIG = smokeping_config.pod smokeping_examples.pod

#PM :=  ../lib/Smokeping.pm ../lib/Smokeping/Examples.pm ../lib/Smokeping/RRDtools.pm

EXTRA_DIST = $(DOCS) smokeping_install.txt

PODPROBE :=  $(wildcard ../lib/Smokeping/probes/*.pm)
PODMATCH :=  $(wildcard ../lib/Smokeping/matchers/*.pm)
PODSORT :=  $(wildcard ../lib/Smokeping/sorters/*.pm)

DOCSBASE = $(subst .pod,,$(DOCS))

MODBASE = $(subst .pm,,$(subst ../lib/Smokeping/probes/,Smokeping_probes_,$(PODPROBE))) \
	  $(subst .pm,,$(subst ../lib/Smokeping/matchers/,Smokeping_matchers_,$(PODMATCH))) \
	  $(subst .pm,,$(subst ../lib/Smokeping/sorters/,Smokeping_sorters_,$(PODSORT)))

PROGBASE = smokeping smokeping_cgi tSmoke

DOCSCONFIGBASE = smokeping_config smokeping_examples

MAN3 = $(addsuffix .3,$(MODBASE))
MAN5 = $(addsuffix .5,$(DOCSCONFIGBASE))
MAN7 = $(addsuffix .7,$(DOCSBASE))
MAN1 = $(addsuffix .1,$(PROGBASE))

POD2MAN = pod2man --release=$(VERSION) --center=SmokePing $<

# we go to this trouble to ensure that MAKEPOD only uses modules in the installation directory
MAKEPOD= PERL5LIB=$(PERL5LIB) $(PERL) -I$(DESTDIR)$(prefix)/thirdparty/lib/perl5 -I../lib -mSmokeping -e 'Smokeping::main()' -- --makepod
GENEX= PERL5LIB=$(PERL5LIB) $(PERL) -I$(DESTDIR)$(prefix)/thirdparty/lib/perl5  -I../lib -mSmokeping -e 'Smokeping::main()' -- --gen-examples

%.7: %.pod
	$(AM_V_GEN)$(POD2MAN) --section 7 > $@

%.5: %.pod
	$(AM_V_GEN)$(POD2MAN) --section 5 > $@

Smokeping.3: ../lib/Smokeping.pm
	$(AM_V_GEN)$(POD2MAN) --section 3 > $@

Smokeping_Examples.3: ../lib/Smokeping/Examples.pm        
	$(AM_V_GEN)$(POD2MAN) --section 3 > $@

Smokeping_RRDtools.3: ../lib/Smokeping/RRDtools.pm
	$(AM_V_GEN)$(POD2MAN) --section 3 > $@

Smokeping_probes_%.pod: ../lib/Smokeping/probes/%.pm
	$(AM_V_GEN)$(MAKEPOD) Smokeping::probes::$* > $@

Smokeping_probes_%.3: Smokeping_probes_%.pod
	$(AM_V_GEN)$(POD2MAN) --section 3 > $@

Smokeping_matchers_%.3: ../lib/Smokeping/matchers/%.pm
	$(AM_V_GEN)$(POD2MAN) --section 3 > $@

Smokeping_sorters_%.3: ../lib/Smokeping/sorters/%.pm
	$(AM_V_GEN)$(POD2MAN) --section 3 > $@

smokeping.1: ../bin/smokeping
	$(AM_V_GEN)$(POD2MAN) --section 1 > $@

smokeping_cgi.1: ../bin/smokeping_cgi
	$(AM_V_GEN)$(POD2MAN) --section 1 > $@

tSmoke.1: ../bin/tSmoke
	$(AM_V_GEN)$(POD2MAN) --section 1 > $@

smokeping_config.pod: ../lib/Smokeping.pm
	$(AM_V_GEN)$(MAKEPOD) > $@

smokeping_examples.pod: ../lib/Smokeping/Examples.pm ../etc/config.dist
	$(AM_V_GEN)$(MKDIR) -p examples
	$(AM_V_GEN)$(GENEX)

.1.txt .3.txt .5.txt .7.txt:
	$(AM_V_GEN)GROFF_NO_SGR=1 @NROFF@ -man -Tlp $< > $@


CLEANFILES = *.[1357] smokeping_examples.pod smokeping_config.pod examples/*

iman1dir = $(mandir)/man1
iman1_DATA = $(MAN1)

iman3dir = $(mandir)/man3
iman3_DATA = $(MAN3)

iman5dir = $(mandir)/man5
iman5_DATA = $(MAN5)

iman7dir = $(mandir)/man7
iman7_DATA = $(MAN7)

EXAMPLES := $(wildcard examples/config.*)

etcdir = $(sysconfdir)/examples
etc_DATA = $(EXAMPLES)

