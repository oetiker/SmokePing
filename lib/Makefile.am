# Copyright (C) 2010 Stanislav Sinyagin
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

#
AUTOMAKE_OPTIONS =  foreign


PM :=  $(wildcard *.pm)

SP :=  $(wildcard Smokeping/*.pm)
       
SORT := $(wildcard Smokeping/sorters/*.pm)

PROBE := $(wildcard Smokeping/probes/*.pm)

MATCH := $(wildcard Smokeping/matchers/*.pm)

EXTRA_DIST = $(PM) $(SP) $(SORT) $(PROBE) $(MATCH)

perllibdir = $(prefix)/lib
nobase_perllib_DATA = $(EXTRA_DIST)
