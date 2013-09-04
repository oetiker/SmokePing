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

JS = cropper/smokeping-zoom.js cropper/lib/unittest.js cropper/lib/slider.js cropper/lib/controls.js \
     cropper/lib/sound.js cropper/lib/dragdrop.js cropper/lib/prototype.js cropper/lib/effects.js \
     cropper/lib/builder.js cropper/lib/scriptaculous.js  cropper/marqueeVert.gif cropper/cropper.uncompressed.js \
     cropper/licence.txt cropper/marqueeHoriz.gif cropper/cropper.js cropper/cropper.css

EXTRA_DIST = $(JS)

jsdir = $(HTDOCSDIR)
nobase_js_DATA = $(JS)

install-data-local:
	$(MKDIR) -p $(DESTDIR)$(HTDOCSDIR)
	$(ECHO)	"#!/bin/sh" > $(DESTDIR)$(HTDOCSDIR)/smokeping.fcgi.dist
	$(ECHO)	"exec $(bindir)/smokeping_cgi $(sysconfdir)/config" >> $(DESTDIR)$(HTDOCSDIR)/smokeping.fcgi.dist
	chmod +x $(DESTDIR)$(HTDOCSDIR)/smokeping.fcgi.dist
