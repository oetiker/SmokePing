# Copyright (C) 2024 Tobias Oetiker
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

AUTOMAKE_OPTIONS = foreign

TESTS_FILES = 01_request.t 02_utils.t 03_colorspace.t 04_sorters.t 05_matchers.t

EXTRA_DIST = $(TESTS_FILES)

check-local:
	$(PERL) -I$(top_srcdir)/lib -I$(top_srcdir)/thirdparty/lib/perl5 -MTest::Harness -e 'runtests(@ARGV)' $(srcdir)/01_request.t $(srcdir)/02_utils.t $(srcdir)/03_colorspace.t $(srcdir)/04_sorters.t $(srcdir)/05_matchers.t
