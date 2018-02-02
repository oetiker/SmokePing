#  Copyright (C) 2017 Tobias Oetiker

AUTOMAKE_OPTIONS =  foreign

THIRDPARTY_DIR := $(shell pwd)

THIRDPARTY_DIST := $(shell test -d CPAN && find CPAN -type d -name ".??*" -prune -o -not -name ".*" -a -not -name "*~" -a -not -name "*.tmp"  -a -type f -print )

EXTRA_DIST = $(THIRDPARTY_DIST) $(wildcard bin/cpanm)

all-local: touch

touch: CPAN/touch ../config.status ../PERL_MODULES
	echo "If the moduile install hangs, this may be because one of the modules expects you to press [return] without telling you ... just do it!"
	$(AM_V_GEN)cat ../PERL_MODULES  | PERL_CPANM_HOME=$(THIRDPARTY_DIR) xargs $(PERL) $(THIRDPARTY_DIR)/bin/cpanm -q --notest --local-lib-contained $(THIRDPARTY_DIR)  --mirror file://$(THIRDPARTY_DIR)/CPAN --mirror-only
	$(AM_V_GEN)touch touch

CPAN/touch: ../PERL_MODULES
	echo "POPULATING OUR LOCAL micro CPAN"
	$(AM_V_GEN)$(URL_CAT) https://raw.githubusercontent.com/miyagawa/cpanminus/devel/cpanm | PERL_CPANM_HOME=$(THIRDPARTY_DIR) $(PERL) - -q --notest --local-lib $(THIRDPARTY_DIR) --save-dists $(THIRDPARTY_DIR)/CPAN --force App::cpanminus
	$(AM_V_GEN)PERL_CPANM_HOME=$(THIRDPARTY_DIR)/Ore $(THIRDPARTY_DIR)/bin/cpanm -q --notest  --local-lib $(THIRDPARTY_DIR)/Ore File::Which OrePAN
	$(AM_V_GEN)cat ../PERL_MODULES | PERL_CPANM_HOME=$(THIRDPARTY_DIR) xargs $(PERL) $(THIRDPARTY_DIR)/bin/cpanm -q --self-contained --notest --local-lib-contained $(THIRDPARTY_DIR) --save-dists $(THIRDPARTY_DIR)/CPAN
	$(AM_V_GEN)PERL5LIB=$(THIRDPARTY_DIR)/Ore/lib/perl5 $(THIRDPARTY_DIR)/Ore/bin/orepan_index.pl --repository $(THIRDPARTY_DIR)/CPAN
# Ore fails to extract the version form DBI
	$(AM_V_GEN)gunzip -c CPAN/modules/02packages.details.txt.gz | perl -pe 's{^(DBI\s+)undef(\s+\S+/DBI-)(\d+\.\d+)(\.tar)}{$$1$$3$$2$$3$$4}' |  gzip | cat > x.gz && mv x.gz CPAN/modules/02packages.details.txt.gz
	$(AM_V_GEN)touch CPAN/touch

clean-local:
	ls -1 | grep -v Makefile | grep -v bin | grep -v CPAN | xargs rm -rf

distclean-local:
		ls -1 | grep -v Makefile | xargs rm -rf
