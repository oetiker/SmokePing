# Copyright (C) 2026 Avinash Duduskar
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

AUTOMAKE_OPTIONS = foreign

TESTS = \
    00-load-core.t \
    01-load-probes.t \
    02-load-matchers.t \
    03-load-sorters.t \
    04-config-parse.t

# Tests run as executable Perl scripts via their shebang. PERL5LIB points
# at the in-tree library and at the Carton-installed CPAN deps under
# thirdparty/, so `make check` works after `make` has populated either.
TESTS_ENVIRONMENT = \
    PERL5LIB="$(abs_top_srcdir)/lib:$(abs_top_srcdir)/thirdparty/lib/perl5:$$PERL5LIB"

EXTRA_DIST = $(TESTS) lib/SPTest.pm
