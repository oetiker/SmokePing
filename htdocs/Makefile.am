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

JS = js/smokeping.js \
    js/prototype.js \
    js/cropper/cropper.js \
    js/cropper/licence.txt \
    js/cropper/marqueeVert.gif \
    js/cropper/cropper.uncompressed.js \
    js/cropper/cropper.css \
    js/cropper/marqueeHoriz.gif \
    js/scriptaculous/controls.js \
    js/scriptaculous/slider.js \
    js/scriptaculous/sound.js \
    js/scriptaculous/effects.js \
    js/scriptaculous/unittest.js \
    js/scriptaculous/builder.js \
    js/scriptaculous/scriptaculous.js \
    js/scriptaculous/dragdrop.js \
    css/smokeping-screen.css

EXTRA_DIST = $(JS)

jsdir = $(HTDOCSDIR)
nobase_js_DATA = $(JS)

install-data-local:
	$(MKDIR) -p $(DESTDIR)$(HTDOCSDIR)
	$(ECHO)	"#!/bin/sh" > $(DESTDIR)$(HTDOCSDIR)/smokeping.fcgi.dist
	$(ECHO)	"exec $(bindir)/smokeping_cgi $(sysconfdir)/config" >> $(DESTDIR)$(HTDOCSDIR)/smokeping.fcgi.dist
	chmod +x $(DESTDIR)$(HTDOCSDIR)/smokeping.fcgi.dist
